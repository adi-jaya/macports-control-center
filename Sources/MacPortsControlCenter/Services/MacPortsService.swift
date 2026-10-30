import Foundation
import SQLite3

public struct MacPortsService {
    public static let supportedPHPExtensionSubports: [String] = [
        "mysql", "mbstring", "curl", "openssl", "gd", "intl", "zip",
        "sqlite", "iconv", "opcache", "redis", "imagick", "xdebug",
        "postgresql", "soap", "exif", "pcntl", "sockets", "sodium", "posix"
    ]

    public static let builtInPHPCoreModules: [String] = [
        "bcmath", "json", "ctype", "tokenizer", "xml", "dom", "fileinfo", "phar"
    ]

    public static let portBinary = "/opt/local/bin/port"
    public static let launchDaemonsPath = "/opt/local/etc/LaunchDaemons"
    public static let libraryLaunchDaemonsPath = "/Library/LaunchDaemons"

    /// Parses output of `port select --summary` into structured groups
    public static func parsePortSelectSummary(_ output: String) -> [PortSelectGroup] {
        let lines = output.components(separatedBy: .newlines)
        var groups: [PortSelectGroup] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.starts(with: "Name") || trimmed.starts(with: "====") {
                continue
            }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            let group = parts[0]
            let selected = parts[1]
            let options = Array(parts.dropFirst(2))
            groups.append(PortSelectGroup(group: group, selected: selected, options: options))
        }
        return groups
    }

    /// Parses output of `port installed` into individual package versions
    public static func parseInstalledPorts(_ output: String) -> [PortPackageItem] {
        let lines = output.components(separatedBy: .newlines)
        var items: [PortPackageItem] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.lowercased().hasPrefix("the following ports") {
                continue
            }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2, parts[1].hasPrefix("@") else { continue }
            let name = parts[0]
            let version = parts[1]
            let isActive = trimmed.contains("(active)")
            items.append(PortPackageItem(
                name: name,
                version: version,
                category: "installed",
                summary: "",
                isInstalled: true,
                isActive: isActive,
                isOutdated: false
            ))
        }
        return items
    }

    /// Builds a lookup map prioritizing the active package version when multi-versions exist
    public static func buildInstalledLookupMap(_ items: [PortPackageItem]) -> [String: (version: String, active: Bool)] {
        var lookup: [String: (version: String, active: Bool)] = [:]
        for item in items {
            if let existing = lookup[item.name] {
                if !existing.active && item.isActive {
                    lookup[item.name] = (version: item.version, active: item.isActive)
                }
            } else {
                lookup[item.name] = (version: item.version, active: item.isActive)
            }
        }
        return lookup
    }

    /// Parses output of `port outdated` into a Set of outdated package names
    public static func parseOutdatedPorts(_ output: String) -> Set<String> {
        let lines = output.components(separatedBy: .newlines)
        var outdated = Set<String>()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.lowercased().hasPrefix("the following") || trimmed.lowercased().hasPrefix("no installed") {
                continue
            }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if let first = parts.first {
                outdated.insert(first)
            }
        }
        return outdated
    }

    /// Parses output of `port search --name --line <query>` combined with installed & outdated lookup
    public static func parseSearchOutput(
        _ output: String,
        installed: [String: (version: String, active: Bool)],
        outdated: Set<String>
    ) -> [PortPackageItem] {
        let lines = output.components(separatedBy: .newlines)
        var items: [PortPackageItem] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2 else { continue }
            let name = cols[0]
            let version = cols[1]
            let category = cols.count > 2 ? cols[2] : ""
            let summary = cols.count > 3 ? cols.dropFirst(3).joined(separator: "\t") : ""

            let installedInfo = installed[name]
            let isInstalled = (installedInfo != nil)
            let isActive = installedInfo?.active ?? false
            let isOutdated = outdated.contains(name)

            items.append(PortPackageItem(
                name: name,
                version: version,
                category: category,
                summary: summary,
                isInstalled: isInstalled,
                isActive: isActive,
                isOutdated: isOutdated
            ))
        }
        return items
    }

    /// Discovers LaunchDaemons from directory entry names and cross-references with ps output and boot symlinks
    public static func discoverLaunchDaemons(
        entryNames: [String],
        enabledSymlinks: Set<String>,
        psOutput: String
    ) -> [ServiceItem] {
        let psLines = psOutput.split(separator: "\n")
        var services: [ServiceItem] = []
        for entry in entryNames {
            let name: String
            if entry.hasPrefix("org.macports.") {
                name = String(entry.dropFirst("org.macports.".count))
            } else {
                name = entry
            }

            let plistName: String
            if entry.hasSuffix(".plist") {
                plistName = entry
            } else {
                plistName = "\(entry).plist"
            }

            let isEnabledAtBoot = enabledSymlinks.contains(plistName) ||
                                  enabledSymlinks.contains("\(entry).plist") ||
                                  enabledSymlinks.contains("\(name).plist") ||
                                  enabledSymlinks.contains(entry)

            let isRunning = psLines.contains { line in
                // 1. Daemondo label matching
                if line.contains("--label=\(name)") || line.contains("--label=\(entry)") {
                    return true
                }
                // 2. PHP-FPM daemon matching (e.g. php83-fpm)
                if name.hasSuffix("-fpm") {
                    let phpVersion = name.replacingOccurrences(of: "-fpm", with: "")
                    if line.contains("/opt/local/etc/\(phpVersion)/php-fpm.conf") ||
                       line.contains("php-fpm\(phpVersion)") ||
                       (line.contains("php-fpm") && line.contains(phpVersion)) {
                        return true
                    }
                }
                // 3. Server daemon matching (e.g. mariadb-10.11-server, postgresql16-server)
                if name.hasSuffix("-server") {
                    let baseName = name.replacingOccurrences(of: "-server", with: "")
                    if line.contains("/\(baseName)/") ||
                       line.contains(baseName) ||
                       line.contains("--label=\(baseName)") {
                        return true
                    }
                }
                // 4. Binary paths or exact process matching
                if line.contains("/opt/local/sbin/\(name)") ||
                   line.contains("/opt/local/bin/\(name)") ||
                   line.contains("/\(name) ") ||
                   line.hasSuffix("/\(name)") {
                    return true
                }
                return false
            }

            let detail = isEnabledAtBoot ? "Enabled at boot" : "Manual / Disabled"

            services.append(ServiceItem(
                id: name,
                name: name,
                plistName: plistName,
                isRunning: isRunning,
                isEnabledAtBoot: isEnabledAtBoot,
                detail: detail
            ))
        }
        return services
    }

    /// Reads installed ports directly from MacPorts registry.db using SQLite in read-only mode
    public static func readInstalledPortsSQLite(dbPath: String = "/opt/local/var/macports/registry/registry.db") -> [PortPackageItem]? {
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            return nil
        }
        var db: OpaquePointer?
        let uri = "file:\(dbPath)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        let query = "SELECT name, version, revision, variants, state FROM ports WHERE state IN ('installed', 'imaged');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var items: [PortPackageItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 0),
                  let cVer = sqlite3_column_text(stmt, 1) else {
                continue
            }
            let name = String(cString: cName)
            var cleanVer = String(cString: cVer)
            while cleanVer.hasPrefix("'") && cleanVer.hasSuffix("'") && cleanVer.count >= 2 {
                cleanVer = String(cleanVer.dropFirst().dropLast())
            }
            let rev = sqlite3_column_int(stmt, 2)
            let vars: String
            if let cVars = sqlite3_column_text(stmt, 3) {
                vars = String(cString: cVars)
            } else {
                vars = ""
            }
            let state: String
            if let cState = sqlite3_column_text(stmt, 4) {
                state = String(cString: cState)
            } else {
                state = ""
            }
            let isActive = (state == "installed")
            let formattedVersion = "@\(cleanVer)_\(rev)\(vars)"

            items.append(PortPackageItem(
                name: name,
                version: formattedVersion,
                category: "installed",
                summary: "",
                isInstalled: true,
                isActive: isActive,
                isOutdated: false
            ))
        }

        items.sort {
            let cmp = $0.name.caseInsensitiveCompare($1.name)
            if cmp == .orderedSame {
                return $0.version < $1.version
            }
            return cmp == .orderedAscending
        }
        return items
    }

    /// Reads port select groups directly from /opt/local/etc/select without spawning port CLI
    public static func readPortSelectGroupsFilesystem(selectRootPath: String = "/opt/local/etc/select") -> [PortSelectGroup]? {
        guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: selectRootPath) else {
            return nil
        }
        let sortedGroupDirs = subdirs.filter { !$0.hasPrefix(".") }.sorted()
        var groups: [PortSelectGroup] = []

        for group in sortedGroupDirs {
            let groupPath = (selectRootPath as NSString).appendingPathComponent(group)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: groupPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: groupPath) else {
                continue
            }
            let currentPath = (groupPath as NSString).appendingPathComponent("current")
            var selected = "none"
            if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: currentPath), !dest.isEmpty {
                selected = (dest as NSString).lastPathComponent
            }

            let hasNone = entries.contains("none")
            var options = entries.filter { !$0.hasPrefix(".") && $0 != "base" && $0 != "current" && $0 != "none" }.sorted()
            if hasNone {
                options.append("none")
            }

            groups.append(PortSelectGroup(group: group, selected: selected, options: options))
        }
        return groups
    }

    /// Parses Tcl list key-value pairs from PortIndex record body
    public static func parseTclPortIndexRecord(_ record: String) -> (version: String, categories: String, description: String) {
        var version = ""
        var categories = ""
        var description = ""
        var hasVersion = false
        var hasCategories = false
        var hasDescription = false

        var isKey = true
        var currentKey = ""

        let scalars = Array(record.unicodeScalars)
        let count = scalars.count
        var i = 0

        while i < count {
            while i < count && (scalars[i] == " " || scalars[i] == "\t" || scalars[i] == "\n" || scalars[i] == "\r") {
                i += 1
            }
            if i >= count { break }

            var token = ""
            if scalars[i] == "{" {
                i += 1
                var depth = 1
                var isEscaped = false
                while i < count && depth > 0 {
                    let s = scalars[i]
                    i += 1
                    if isEscaped {
                        token.unicodeScalars.append(s)
                        isEscaped = false
                    } else if s == "\\" {
                        isEscaped = true
                    } else if s == "{" {
                        depth += 1
                        token.unicodeScalars.append(s)
                    } else if s == "}" {
                        depth -= 1
                        if depth > 0 {
                            token.unicodeScalars.append(s)
                        }
                    } else {
                        token.unicodeScalars.append(s)
                    }
                }
            } else {
                var isEscaped = false
                while i < count {
                    let s = scalars[i]
                    if !isEscaped && (s == " " || s == "\t" || s == "\n" || s == "\r") {
                        break
                    }
                    i += 1
                    if isEscaped {
                        token.unicodeScalars.append(s)
                        isEscaped = false
                    } else if s == "\\" {
                        isEscaped = true
                    } else {
                        token.unicodeScalars.append(s)
                    }
                }
            }

            if isKey {
                currentKey = token
                isKey = false
            } else {
                if currentKey == "version" {
                    version = token
                    hasVersion = true
                } else if currentKey == "categories" {
                    categories = token
                    hasCategories = true
                } else if currentKey == "description" {
                    description = token
                    hasDescription = true
                }

                if hasVersion && hasCategories && hasDescription {
                    return (version: version, categories: categories, description: description)
                }
                isKey = true
                currentKey = ""
            }
        }

        return (version: version, categories: categories, description: description)
    }

    /// Resolves PortIndex and PortIndex.quick file paths from sources.conf and default locations
    public static func resolvePortIndexPaths(
        sourcesConfPath: String = "/opt/local/etc/macports/sources.conf",
        sourcesRoot: String = "/opt/local/var/macports/sources"
    ) -> [(quickIndexPath: String, portIndexPath: String)] {
        var candidates: [(quickIndexPath: String, portIndexPath: String)] = []

        if let content = try? String(contentsOfFile: sourcesConfPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }
                let urlPart = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                if urlPart.hasPrefix("file://") {
                    var path = String(urlPart.dropFirst("file://".count))
                    while path.hasSuffix("/") && path.count > 1 {
                        path.removeLast()
                    }
                    candidates.append((
                        quickIndexPath: "\(path)/PortIndex.quick",
                        portIndexPath: "\(path)/PortIndex"
                    ))
                } else if urlPart.hasPrefix("rsync://") {
                    let withoutScheme = String(urlPart.dropFirst("rsync://".count))
                    let components = withoutScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                    if components.count == 2 {
                        let host = String(components[0])
                        var cleanPath = String(components[1])
                        if cleanPath.hasSuffix(".tar") {
                            cleanPath = String(cleanPath.dropLast(".tar".count))
                        }
                        while cleanPath.hasSuffix("/") && cleanPath.count > 1 {
                            cleanPath.removeLast()
                        }
                        candidates.append((
                            quickIndexPath: "\(sourcesRoot)/\(host)/\(cleanPath)/PortIndex.quick",
                            portIndexPath: "\(sourcesRoot)/\(host)/\(cleanPath)/PortIndex"
                        ))
                    }
                }
            }
        }

        let defaultPortIndex = "\(sourcesRoot)/rsync.macports.org/macports/release/tarballs/ports/PortIndex"
        let defaultQuickIndex = "\(sourcesRoot)/rsync.macports.org/macports/release/tarballs/ports/PortIndex.quick"
        if !candidates.contains(where: { $0.portIndexPath == defaultPortIndex }) {
            candidates.append((quickIndexPath: defaultQuickIndex, portIndexPath: defaultPortIndex))
        }

        return candidates.filter {
            FileManager.default.isReadableFile(atPath: $0.quickIndexPath) &&
            FileManager.default.isReadableFile(atPath: $0.portIndexPath)
        }
    }

    /// Fast native search over PortIndex.quick and PortIndex
    public static func searchPortsNativeIndex(
        query: String,
        indexPaths: [(quickIndexPath: String, portIndexPath: String)]? = nil,
        installed: [String: (version: String, active: Bool)],
        outdated: Set<String>
    ) -> [PortPackageItem]? {
        if query.isEmpty || query.contains(where: { "*?[]^$\\".contains($0) }) {
            return nil
        }
        let lowerQuery = query.lowercased()
        let targets = indexPaths ?? resolvePortIndexPaths()
        if targets.isEmpty {
            return nil
        }

        var items: [PortPackageItem] = []
        var seenNames = Set<String>()

        for pair in targets {
            guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: pair.portIndexPath)) else {
                continue
            }
            guard let quickContent = try? String(contentsOfFile: pair.quickIndexPath, encoding: .utf8) else {
                try? fileHandle.close()
                continue
            }

            let lines = quickContent.split(separator: "\n")
            for line in lines {
                let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = cleanLine.split(separator: " ")
                guard parts.count >= 2 else { continue }
                let portName = String(parts[0])
                guard portName.lowercased().contains(lowerQuery) else { continue }
                guard let offset = UInt64(parts[1]) else { continue }

                do {
                    try fileHandle.seek(toOffset: offset)
                    let probeData = fileHandle.readData(ofLength: 256)
                    guard let newlineIndex = probeData.firstIndex(of: 0x0A) else { continue }
                    let headerData = probeData[..<newlineIndex]
                    let headerLength = (newlineIndex - probeData.startIndex) + 1
                    guard let headerStr = String(data: headerData, encoding: .utf8) else { continue }
                    let headerParts = headerStr.split(whereSeparator: { $0.isWhitespace })
                    guard headerParts.count >= 2, let byteLen = Int(headerParts[1]) else { continue }
                    let actualName = String(headerParts[0])

                    if seenNames.contains(actualName.lowercased()) {
                        continue
                    }

                    let bodyOffset = offset + UInt64(headerLength)
                    try fileHandle.seek(toOffset: bodyOffset)
                    let bodyData = fileHandle.readData(ofLength: byteLen)
                    let bodyStr = String(data: bodyData, encoding: .utf8) ?? String(decoding: bodyData, as: UTF8.self)

                    let parsed = parseTclPortIndexRecord(bodyStr)
                    let installedInfo = installed[actualName]
                    let isInstalled = (installedInfo != nil)
                    let isActive = installedInfo?.active ?? false
                    let isOutdated = outdated.contains(actualName)

                    seenNames.insert(actualName.lowercased())
                    items.append(PortPackageItem(
                        name: actualName,
                        version: parsed.version,
                        category: parsed.categories,
                        summary: parsed.description,
                        isInstalled: isInstalled,
                        isActive: isActive,
                        isOutdated: isOutdated
                    ))
                } catch {
                    continue
                }
            }
            try? fileHandle.close()
        }

        items.sort { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
        return items
    }

    /// Lists subdirectories in /opt/local/etc/LaunchDaemons
    public static func listLaunchDaemonEntries(at path: String = launchDaemonsPath) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return entries.filter { $0.hasPrefix("org.macports.") }
    }

    /// Lists active symlinks in /Library/LaunchDaemons
    public static func listEnabledBootSymlinks(at path: String = libraryLaunchDaemonsPath) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return Set(entries.filter { $0.hasPrefix("org.macports.") })
    }
}
