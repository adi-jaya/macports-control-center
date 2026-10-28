import Foundation

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
            guard parts.count >= 2 else { continue }
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

            let isRunning: Bool = {
                // 1. Daemondo label matching
                if psOutput.contains("--label=\(name)") || psOutput.contains("--label=\(entry)") {
                    return true
                }
                // 2. PHP-FPM daemon matching (e.g. php83-fpm)
                if name.hasSuffix("-fpm") {
                    let phpVersion = name.replacingOccurrences(of: "-fpm", with: "")
                    if psOutput.contains("/opt/local/etc/\(phpVersion)/php-fpm.conf") ||
                       psOutput.contains("php-fpm\(phpVersion)") ||
                       (psOutput.contains("php-fpm") && psOutput.contains(phpVersion)) {
                        return true
                    }
                }
                // 3. Server daemon matching (e.g. mariadb-10.11-server, postgresql16-server)
                if name.hasSuffix("-server") {
                    let baseName = name.replacingOccurrences(of: "-server", with: "")
                    if psOutput.contains("/\(baseName)/") ||
                       psOutput.contains(baseName) ||
                       psOutput.contains("--label=\(baseName)") {
                        return true
                    }
                }
                // 4. Binary paths or exact process matching
                if psOutput.contains("/opt/local/sbin/\(name)") ||
                   psOutput.contains("/opt/local/bin/\(name)") ||
                   psOutput.contains("/\(name) ") ||
                   psOutput.contains("/\(name)\n") {
                    return true
                }
                return false
            }()

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
