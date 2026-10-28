import Foundation
import Combine

// MARK: - NavigationSection
public enum NavigationSection: String, CaseIterable, Identifiable {
    case services = "services"
    case sites = "sites"
    case php = "php"
    case database = "database"
    case packages = "packages"
    case logs = "logs"
    case docs = "docs"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .services: return "Services & Doctor"
        case .sites: return "Virtual Hosts"
        case .php: return "PHP Manager"
        case .database: return "Databases"
        case .packages: return "MacPorts Packages"
        case .logs: return "Server Logs"
        case .docs: return "Documentation"
        }
    }

    public var systemImage: String {
        switch self {
        case .services: return "server.rack"
        case .sites: return "globe"
        case .php: return "chevron.left.forwardslash.chevron.right"
        case .database: return "cylinder.split.1x2"
        case .packages: return "shippingbox"
        case .logs: return "doc.text.magnifyingglass"
        case .docs: return "book"
        }
    }
}

// MARK: - PaletteCommand
public struct PaletteCommand: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let action: @MainActor () -> Void

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String = "",
        action: @MainActor @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

// MARK: - AppState
@MainActor
public final class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published public var services: [ServiceItem] = []
    @Published public var vhosts: [VHostItem] = []
    @Published public var phpVersions: [PHPVersionItem] = []
    @Published public var databases: [String] = []
    @Published public var packages: [PortPackageItem] = []
    @Published public var portSelectGroups: [PortSelectGroup] = []
    @Published public var doctorChecks: [DoctorCheckItem] = []
    @Published public var selectedSection: NavigationSection = .services
    @Published public var isCommandPalettePresented: Bool = false
    @Published public var isTerminalDrawerExpanded: Bool = true
    @Published public var docFiles: [DocItem] = []
    @Published public var selectedDoc: DocItem? = nil
    @Published public var selectedDocContent: String = ""
    @Published public var isLoading: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var packageSearchQuery: String = ""
    @Published public var isSearchingPackages: Bool = false

    // MARK: - Services & Configuration
    public let commandRunner: CommandRunner
    public let repoPath: String
    public let nginxServersPath: String
    public let defaultSocketPath: String

    // MARK: - Initializer
    public init(
        autoRefreshOnInit: Bool = true,
        repoPath: String? = nil,
        nginxServersPath: String = "/opt/local/etc/nginx/servers",
        defaultSocketPath: String = "/tmp/mysql.sock",
        commandRunner: CommandRunner? = nil
    ) {
        self.commandRunner = commandRunner ?? CommandRunner()
        self.nginxServersPath = nginxServersPath
        self.defaultSocketPath = defaultSocketPath

        // Resolve repository path
        let resolvedRepoPath: String = {
            if let custom = repoPath, FileManager.default.fileExists(atPath: "\(custom)/README.md") {
                return custom
            }
            let cwd = FileManager.default.currentDirectoryPath
            if FileManager.default.fileExists(atPath: "\(cwd)/README.md") {
                return cwd
            }
            let standardPath = "/Users/adijaya/MyFiles/Projects/macports-control-center"
            if FileManager.default.fileExists(atPath: "\(standardPath)/README.md") {
                return standardPath
            }
            if let bundleResource = Bundle.main.resourceURL?.path,
               FileManager.default.fileExists(atPath: "\(bundleResource)/README.md") {
                return bundleResource
            }
            return cwd
        }()
        self.repoPath = resolvedRepoPath

        // Load documentation files synchronously
        loadDocumentationFiles()

        // Optionally trigger initial scan
        if autoRefreshOnInit {
            Task { [weak self] in
                await self?.refreshAll()
            }
        }
    }

    // MARK: - Documentation Loader
    public func loadDocumentationFiles() {
        var items: [DocItem] = []
        let fm = FileManager.default

        // Standard known documentation files in order of presentation
        let knownFiles: [(name: String, title: String)] = [
            ("README.md", "README: Overview & Quickstart"),
            ("AGENTS.md", "AGENTS: Architecture & Conventions"),
            ("VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md", "Virtual Hosts & Domains Guide"),
            ("FRESH_INSTALL_GUIDE.md", "Fresh Install & Multi-PHP Guide"),
            ("FINAL_MACPORTS_ENVIRONMENT_SETUP.md", "Host Setup & Port Audit"),
            ("HANDOFF_MACPORTS_MIGRATION.md", "Migration Handoff Notes")
        ]

        var loadedFileNames = Set<String>()

        for entry in knownFiles {
            let fullPath = (repoPath as NSString).appendingPathComponent(entry.name)
            if fm.fileExists(atPath: fullPath) {
                items.append(DocItem(
                    id: entry.name,
                    fileName: entry.name,
                    title: entry.title,
                    filePath: fullPath
                ))
                loadedFileNames.insert(entry.name)
            }
        }

        // Check directory for any additional markdown files
        if let contents = try? fm.contentsOfDirectory(atPath: repoPath) {
            for file in contents.sorted() where file.hasSuffix(".md") && !file.hasPrefix(".") {
                guard !loadedFileNames.contains(file) else { continue }
                let fullPath = (repoPath as NSString).appendingPathComponent(file)
                let title = file
                    .replacingOccurrences(of: ".md", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                items.append(DocItem(
                    id: file,
                    fileName: file,
                    title: title,
                    filePath: fullPath
                ))
                loadedFileNames.insert(file)
            }
        }

        self.docFiles = items
        if selectedDoc == nil, let first = items.first {
            selectedDoc = first
            selectedDocContent = loadDocContent(doc: first)
        }
    }

    public func selectDoc(_ doc: DocItem) {
        self.selectedDoc = doc
        self.selectedDocContent = loadDocContent(doc: doc)
    }

    public func loadDocContent(doc: DocItem) -> String {
        guard let content = try? String(contentsOfFile: doc.filePath, encoding: .utf8) else {
            return "# \(doc.title)\n\n*Unable to load contents of \(doc.fileName)*"
        }
        return content
    }

    // MARK: - Command Palette
    public func buildPaletteCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        // Navigation Commands
        for section in NavigationSection.allCases {
            commands.append(PaletteCommand(
                title: "Go to \(section.displayName)",
                subtitle: "Switch view to \(section.displayName)",
                action: { [weak self] in
                    self?.selectedSection = section
                    self?.isCommandPalettePresented = false
                }
            ))
        }

        // Quick Stack Actions
        commands.append(PaletteCommand(
            title: "Restart Web Stack",
            subtitle: "Reload Nginx and active PHP-FPM daemons",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.restartWebStack() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Start Web Stack",
            subtitle: "Load Nginx and PHP-FPM services",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.startWebStack() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Stop All Services",
            subtitle: "Unload running web and database services",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.stopAllServices() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Reload Nginx",
            subtitle: "Validate configuration syntax and reload Nginx server",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.reloadNginx() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Run Stack Doctor Auto-Fix",
            subtitle: "Repair permissions, sudoers, and configs with 1-click",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.runDoctorAutoFix() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Refresh All Services & Status",
            subtitle: "Rescan daemons, vhosts, databases, and doctor checks",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.refreshAll() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Sync MacPorts (port selfupdate)",
            subtitle: "Update PortIndex and MacPorts base system",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.runSelfUpdate() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Upgrade Outdated Ports",
            subtitle: "Upgrade all installed ports that have new versions",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.runUpgradeOutdated() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Uninstall Leaves",
            subtitle: "Clean unneeded dependency packages (port uninstall leaves)",
            action: { [weak self] in
                self?.isCommandPalettePresented = false
                Task { [weak self] in await self?.runUninstallLeaves() }
            }
        ))

        commands.append(PaletteCommand(
            title: "Clear Terminal Output",
            subtitle: "Clear all streamed output in the docked terminal drawer",
            action: { [weak self] in
                self?.commandRunner.clearLog()
                self?.isCommandPalettePresented = false
            }
        ))

        commands.append(PaletteCommand(
            title: "Toggle Terminal Drawer",
            subtitle: "Expand or collapse the bottom terminal drawer",
            action: { [weak self] in
                self?.isTerminalDrawerExpanded.toggle()
                self?.isCommandPalettePresented = false
            }
        ))

        // Dynamic Switch PHP CLI commands
        for php in phpVersions where php.isInstalled {
            commands.append(PaletteCommand(
                title: "Switch CLI to PHP \(php.version)",
                subtitle: "Set system default PHP via port select --set php \(php.portName)",
                action: { [weak self] in
                    self?.isCommandPalettePresented = false
                    Task { [weak self] in
                        await self?.runPortSelect(group: "php", option: php.portName)
                    }
                }
            ))
        }

        return commands
    }

    public func filteredPaletteCommands(query: String) -> [PaletteCommand] {
        let all = buildPaletteCommands()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(trimmed) ||
            cmd.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Refresh All Operations
    public func refreshAll() async {
        isLoading = true
        defer { isLoading = false }

        await refreshServices()
        await refreshVHosts()
        await refreshPHPVersions()
        await refreshDatabases()
        await refreshPortSelect()
        await refreshDoctorChecks()
    }

    public func refreshServices() async {
        let entries = MacPortsService.listLaunchDaemonEntries()
        let symlinks = MacPortsService.listEnabledBootSymlinks()
        let psResult = await commandRunner.runShell("ps aux", label: "check-services-ps", serialized: false)
        let discovered = MacPortsService.discoverLaunchDaemons(
            entryNames: entries,
            enabledSymlinks: symlinks,
            psOutput: psResult.stdout
        )
        self.services = discovered
    }

    public func refreshVHosts() async {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: nginxServersPath) else {
            self.vhosts = []
            return
        }
        var items: [VHostItem] = []
        for file in files.sorted() where file.hasSuffix(".conf") && !file.hasPrefix(".") {
            let fullPath = (nginxServersPath as NSString).appendingPathComponent(file)
            if let vhost = ConfigFileService.parseVHost(filePath: fullPath) {
                items.append(vhost)
            }
        }
        self.vhosts = items
    }

    public func refreshPHPVersions() async {
        let psResult = await commandRunner.runShell("ps aux", label: "check-php-ps", serialized: false)
        let installedResult = await commandRunner.runShell("/opt/local/bin/port installed", label: "check-php-installed", serialized: false)
        let selectResult = await commandRunner.runShell("/opt/local/bin/port select --summary", label: "check-php-select", serialized: false)

        let installedPorts = MacPortsService.parseInstalledPorts(installedResult.stdout)
        let installedNames = Set(installedPorts.map { $0.name })
        let selectGroups = MacPortsService.parsePortSelectSummary(selectResult.stdout)
        let defaultPHP = selectGroups.first(where: { $0.group == "php" })?.selected ?? "none"

        let supportedVersions: [(version: String, portName: String, fpmPort: Int)] = [
            ("8.1", "php81", 9081),
            ("8.2", "php82", 9082),
            ("8.3", "php83", 9000),
            ("8.4", "php84", 9084),
            ("8.5", "php85", 9085)
        ]

        var items: [PHPVersionItem] = []
        for entry in supportedVersions {
            let isInstalled = installedNames.contains(entry.portName)
            let isCLIDefault = (defaultPHP == entry.portName)
            let isFPMRunning = psResult.stdout.contains("\(entry.portName)-fpm") ||
                               (psResult.stdout.contains("php-fpm") && psResult.stdout.contains(entry.portName))

            // Check installed extension subports
            var extensions = Set<String>()
            for subport in MacPortsService.supportedPHPExtensionSubports {
                let pkgName = "\(entry.portName)-\(subport)"
                if installedNames.contains(pkgName) {
                    extensions.insert(subport)
                }
            }

            items.append(PHPVersionItem(
                version: entry.version,
                portName: entry.portName,
                isInstalled: isInstalled,
                isCLIDefault: isCLIDefault,
                fpmPort: entry.fpmPort,
                isFPMRunning: isFPMRunning,
                installedExtensions: extensions
            ))
        }

        self.phpVersions = items
    }

    public func refreshDatabases() async {
        let cmd = DatabaseService.buildShowDatabasesCommand(socketPath: defaultSocketPath)
        let result = await commandRunner.runShell(cmd, label: "show-databases", serialized: false)
        let dbs = DatabaseService.parseShowDatabases(result.stdout)
        self.databases = dbs
    }

    public func refreshPortSelect() async {
        let result = await commandRunner.runShell("/opt/local/bin/port select --summary", label: "port-select-summary", serialized: false)
        let groups = MacPortsService.parsePortSelectSummary(result.stdout)
        self.portSelectGroups = groups
    }

    public func refreshDoctorChecks() async {
        let sudoersContent = (try? String(contentsOfFile: "/etc/sudoers.d/macports", encoding: .utf8)) ?? ""
        let sudoersOK = sudoersContent.contains("NOPASSWD: /opt/local/bin/port")

        // Find non-compliant FPM pools
        var nonCompliantFPM: [String] = []
        let currentUserName = NSUserName()
        for v in ["81", "82", "83", "84", "85"] {
            let confPath = "/opt/local/etc/php\(v)/php-fpm.d/www.conf"
            if let content = try? String(contentsOfFile: confPath, encoding: .utf8) {
                let hasUser = content.contains("user = \(currentUserName)")
                let hasGroup = content.contains("group = staff")
                if !hasUser || !hasGroup {
                    nonCompliantFPM.append(confPath)
                }
            }
        }

        let nginxWritable = DoctorService.isNginxServersWritable(path: nginxServersPath)
        let isMariaDBRunning = services.first(where: { $0.name.contains("mariadb") || $0.name.contains("mysql") })?.isRunning == true
        let mysqlSocketPresent = DoctorService.isMySQLSocketPresent(path: defaultSocketPath)
        let unreadableLogs = DoctorService.findUnreadableLogFiles(paths: DoctorService.defaultMonitoredLogPaths())

        let checks = DoctorService.evaluateChecks(
            sudoersOK: sudoersOK,
            nonCompliantFPMFiles: nonCompliantFPM,
            nginxServersWritable: nginxWritable,
            mariaDBRunning: isMariaDBRunning,
            mysqlSocketExists: mysqlSocketPresent,
            unreadableLogFiles: unreadableLogs
        )
        self.doctorChecks = checks
    }

    // MARK: - Service Control Actions
    public func toggleService(_ item: ServiceItem) async {
        let action = item.isRunning ? "unload" : "load"
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port \(action) \(item.name)", label: "toggle-\(item.name)")
        await refreshServices()
    }

    public func restartService(_ item: ServiceItem) async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port reload \(item.name) || (sudo -n /opt/local/bin/port unload \(item.name) && sudo -n /opt/local/bin/port load \(item.name))", label: "restart-\(item.name)")
        await refreshServices()
    }

    public func restartWebStack() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port reload nginx || sudo -n /opt/local/bin/port load nginx", label: "restart-nginx")
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port reload php83-fpm || sudo -n /opt/local/bin/port load php83-fpm", label: "restart-php83-fpm")
        await refreshServices()
    }

    public func startWebStack() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port load nginx", label: "start-nginx")
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port load php83-fpm", label: "start-php83-fpm")
        await refreshServices()
    }

    public func stopAllServices() async {
        for service in services where service.isRunning {
            _ = await commandRunner.runShell("sudo -n /opt/local/bin/port unload \(service.name)", label: "stop-\(service.name)")
        }
        await refreshServices()
    }

    public func reloadNginx() async {
        let test = await commandRunner.runShell("/opt/local/sbin/nginx -t", label: "test-nginx", serialized: false)
        guard ConfigFileService.isNginxTestOutputValid(exitCode: test.exitCode, output: test.stderr + "\n" + test.stdout) else {
            statusMessage = "Nginx syntax error! Reload aborted."
            return
        }
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port reload nginx", label: "reload-nginx")
        await refreshServices()
    }

    // MARK: - PHP Actions
    public func writeConfigFile(content: String, targetPath: String) async {
        do {
            try content.write(toFile: targetPath, atomically: true, encoding: .utf8)
        } catch {
            // If direct write fails (e.g. root-owned destination), write to temp file and copy via sudo
            let tempPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("config.\(UUID().uuidString)")
            if (try? content.write(toFile: tempPath, atomically: true, encoding: .utf8)) != nil {
                _ = await commandRunner.runShell("sudo -n /bin/cp '\(tempPath)' '\(targetPath)'", label: "copy-config-file")
                try? FileManager.default.removeItem(atPath: tempPath)
            }
        }
    }

    public func installPHPBundle(_ version: String) async {
        let v = version.replacingOccurrences(of: ".", with: "")
        let portName = "php\(v)"
        let corePackages = [
            portName,
            "\(portName)-fpm",
            "\(portName)-mysql",
            "\(portName)-mbstring",
            "\(portName)-curl",
            "\(portName)-openssl",
            "\(portName)-gd",
            "\(portName)-intl",
            "\(portName)-zip",
            "\(portName)-sqlite",
            "\(portName)-opcache"
        ].joined(separator: " ")

        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port install \(corePackages)", label: "install-\(portName)-bundle")

        // Auto-configure www.conf with current user and unique port
        let wwwConfPath = "/opt/local/etc/\(portName)/php-fpm.d/www.conf"
        let defaultConfPath = "/opt/local/etc/\(portName)/php-fpm.d/www.conf.default"
        var contentToConfigure: String? = try? String(contentsOfFile: wwwConfPath, encoding: .utf8)
        if contentToConfigure == nil {
            contentToConfigure = try? String(contentsOfFile: defaultConfPath, encoding: .utf8)
        }

        if let existing = contentToConfigure {
            let updated = ConfigFileService.configureFPMWwwConf(
                content: existing,
                version: v,
                user: NSUserName(),
                group: "staff"
            )
            await writeConfigFile(content: updated, targetPath: wwwConfPath)
        }

        await refreshPHPVersions()
    }

    public func togglePHPExtension(version: String, ext: String, install: Bool) async {
        let v = version.replacingOccurrences(of: ".", with: "")
        let pkg = "php\(v)-\(ext)"
        let action = install ? "install" : "uninstall"
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port \(action) \(pkg)", label: "\(action)-\(pkg)")
        await refreshPHPVersions()
    }

    public func uninstallPHPVersion(_ version: String) async {
        let v = version.replacingOccurrences(of: ".", with: "")
        let portName = "php\(v)"
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port unload \(portName)-fpm", label: "unload-\(portName)-fpm")
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port -N uninstall --follow-dependents \(portName)", label: "uninstall-\(portName)")
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port -N uninstall leaves", label: "uninstall-leaves")
        await refreshPHPVersions()
        await refreshPortSelect()
    }

    public func loadQuickTuning(version: String) -> PHPIniTuning {
        let v = version.replacingOccurrences(of: ".", with: "")
        let phpIniPath = "/opt/local/etc/php\(v)/php.ini"
        let phpIniContent = (try? String(contentsOfFile: phpIniPath, encoding: .utf8)) ?? ""
        let nginxConfContent = (try? String(contentsOfFile: "/opt/local/etc/nginx/nginx.conf", encoding: .utf8)) ?? ""
        return ConfigFileService.parsePHPIniTuning(phpIniContent: phpIniContent, nginxConfContent: nginxConfContent)
    }

    public func applyQuickTuning(version: String, tuning: PHPIniTuning) async {
        let v = version.replacingOccurrences(of: ".", with: "")
        let phpIniPath = "/opt/local/etc/php\(v)/php.ini"
        let defaultPhpIniPath = "/opt/local/etc/php\(v)/php.ini-development"
        var currentPHPIni = (try? String(contentsOfFile: phpIniPath, encoding: .utf8)) ?? ""
        if currentPHPIni.isEmpty, let defContent = try? String(contentsOfFile: defaultPhpIniPath, encoding: .utf8) {
            currentPHPIni = defContent
        }
        let updatedPHPIni = ConfigFileService.updatePHPIni(content: currentPHPIni, tuning: tuning)
        await writeConfigFile(content: updatedPHPIni, targetPath: phpIniPath)

        let nginxConfPath = "/opt/local/etc/nginx/nginx.conf"
        if let currentNginxConf = try? String(contentsOfFile: nginxConfPath, encoding: .utf8) {
            let updatedNginxConf = ConfigFileService.updateNginxClientMaxBodySize(content: currentNginxConf, maxBodySize: tuning.nginxClientMaxBodySize)
            await writeConfigFile(content: updatedNginxConf, targetPath: nginxConfPath)
        }

        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port reload php\(v)-fpm || sudo -n /opt/local/bin/port load php\(v)-fpm", label: "reload-php\(v)-fpm")
        await reloadNginx()
    }

    // MARK: - VHost Actions
    public func saveVHost(
        fileName: String,
        content: String
    ) async throws {
        let filePath = (nginxServersPath as NSString).appendingPathComponent(fileName)
        try await ConfigFileService.saveVHostWithValidation(
            filePath: filePath,
            content: content
        ) { [weak self] in
            guard let self = self else { return (false, "AppState deallocated") }
            let test = await self.commandRunner.runShell("/opt/local/sbin/nginx -t", label: "test-nginx", serialized: false)
            let isValid = ConfigFileService.isNginxTestOutputValid(exitCode: test.exitCode, output: test.stderr + "\n" + test.stdout)
            return (isValid, test.stderr)
        }
        await refreshVHosts()
    }

    public func deleteVHost(fileName: String) async {
        let filePath = (nginxServersPath as NSString).appendingPathComponent(fileName)
        try? FileManager.default.removeItem(atPath: filePath)
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port reload nginx", label: "reload-nginx-after-delete")
        await refreshVHosts()
    }

    public func fixStoragePermissions(for vhost: VHostItem) async {
        let projectRoot: String
        if vhost.rootPath.hasSuffix("/public") {
            projectRoot = (vhost.rootPath as NSString).deletingLastPathComponent
        } else {
            projectRoot = vhost.rootPath
        }
        let cmd = DoctorService.buildFixStoragePermissionsCommand(projectRootPath: projectRoot)
        if !cmd.isEmpty {
            _ = await commandRunner.runShell(cmd, label: "fix-storage-\(vhost.fileName)")
        }
    }

    // MARK: - Ecosystem Utilities Actions
    public func setupDnsmasq() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port install dnsmasq", label: "install-dnsmasq")
        let dnsmasqConfPath = "/opt/local/etc/dnsmasq.conf"
        let defaultConf = (try? String(contentsOfFile: dnsmasqConfPath, encoding: .utf8)) ?? ""
        if !defaultConf.contains("address=/.test/127.0.0.1") {
            let newConf = defaultConf + "\naddress=/.test/127.0.0.1\nlisten-address=127.0.0.1\n"
            await writeConfigFile(content: newConf, targetPath: dnsmasqConfPath)
        }
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port load dnsmasq", label: "load-dnsmasq")
        let resolverScript = "mkdir -p /etc/resolver && echo 'nameserver 127.0.0.1' > /etc/resolver/test"
        _ = await commandRunner.runShell("sudo -n sh -c \"\(resolverScript)\"", label: "setup-resolver-test")
        await refreshServices()
    }

    public func setupMkcert() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port install mkcert", label: "install-mkcert")
        _ = await commandRunner.runShell("mkcert -install", label: "mkcert-install-ca")
    }

    public func setupRedis() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port install redis && sudo -n /opt/local/bin/port load redis", label: "install-load-redis")
        await refreshServices()
    }

    public func setupFnmAndComposer() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port install fnm composer", label: "install-fnm-composer")
    }

    // MARK: - Stack Doctor Auto-Fix
    public func runDoctorAutoFix() async {
        let script = DoctorService.buildPrivilegedAutoFixScript(currentUser: NSUserName())
        let escapedScript = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let osascriptText = "do shell script \"\(escapedScript)\" with administrator privileges"
        let singleQuoted = osascriptText.replacingOccurrences(of: "'", with: "'\\''")
        _ = await commandRunner.runShell("/usr/bin/osascript -e '\(singleQuoted)'", label: "doctor-autofix")
        await refreshAll()
    }

    // MARK: - Package Actions
    public func searchPackages(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearchingPackages = true
        defer { isSearchingPackages = false }

        let installedRes = await commandRunner.runShell("/opt/local/bin/port installed", label: "installed-ports", serialized: false)
        let outdatedRes = await commandRunner.runShell("/opt/local/bin/port outdated", label: "outdated-ports", serialized: false)
        let searchRes = await commandRunner.runShell("/opt/local/bin/port search --name --line \(trimmed)", label: "search-\(trimmed)", serialized: false)

        let installedItems = MacPortsService.parseInstalledPorts(installedRes.stdout)
        let installedMap = MacPortsService.buildInstalledLookupMap(installedItems)
        let outdatedSet = MacPortsService.parseOutdatedPorts(outdatedRes.stdout)

        let results = MacPortsService.parseSearchOutput(searchRes.stdout, installed: installedMap, outdated: outdatedSet)
        self.packages = results
    }

    public func runPortSelect(group: String, option: String) async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port select --set \(group) \(option)", label: "select-\(group)-\(option)")
        await refreshPortSelect()
        if group == "php" {
            await refreshPHPVersions()
        }
    }

    public func runSelfUpdate() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port selfupdate", label: "port-selfupdate")
        await refreshAll()
    }

    public func runUpgradeOutdated() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port upgrade outdated", label: "port-upgrade-outdated")
        await refreshAll()
    }

    public func runUninstallLeaves() async {
        _ = await commandRunner.runShell("sudo -n /opt/local/bin/port -N uninstall leaves", label: "port-uninstall-leaves")
        await refreshAll()
    }

    // MARK: - Database Actions
    public func createDatabase(name: String) async {
        let cmd = DatabaseService.buildCreateDatabaseCommand(dbName: name, socketPath: defaultSocketPath)
        _ = await commandRunner.runShell(cmd, label: "create-db-\(name)")
        await refreshDatabases()
    }

    public func dropDatabase(name: String) async {
        let cmd = DatabaseService.buildDropDatabaseCommand(dbName: name, socketPath: defaultSocketPath)
        _ = await commandRunner.runShell(cmd, label: "drop-db-\(name)")
        await refreshDatabases()
    }

    public func dumpDatabase(name: String, outputPath: String) async {
        let cmd = DatabaseService.buildDumpDatabaseCommand(dbName: name, outputPath: outputPath, socketPath: defaultSocketPath)
        _ = await commandRunner.runShell(cmd, label: "dump-db-\(name)")
    }

    public func importDatabase(name: String, inputPath: String) async {
        let cmd = DatabaseService.buildImportDatabaseCommand(dbName: name, inputPath: inputPath, socketPath: defaultSocketPath)
        _ = await commandRunner.runShell(cmd, label: "import-db-\(name)")
        await refreshDatabases()
    }
}
