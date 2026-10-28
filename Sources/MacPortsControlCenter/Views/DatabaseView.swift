import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - DatabaseView
public struct DatabaseView: View {
    @EnvironmentObject public var appState: AppState

    @State private var searchQuery: String = ""
    @State private var isNewDBSheetPresented: Bool = false
    @State private var dbToDrop: String? = nil
    @State private var isDropAlertPresented: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var isEngineInstallAlertPresented: Bool = false
    @State private var selectedEngineToInstall: (name: String, portName: String)? = nil

    public init() {}

    private var isSocketConnected: Bool {
        DoctorService.isMySQLSocketPresent(path: appState.defaultSocketPath)
    }

    private var isMariaDBRunning: Bool {
        appState.services.first(where: {
            $0.name.contains("mariadb") || $0.name.contains("mysql")
        })?.isRunning ?? isSocketConnected
    }

    private var filteredDatabases: [String] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return appState.databases
        }
        return appState.databases.filter {
            $0.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Notification Banner
                if let feedback = feedbackMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(feedback)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Dismiss") { feedbackMessage = nil }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Dismiss") { errorMessage = nil }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                }

                // Status & Connection Card
                connectionStatusSection

                // Alternative Engines Card
                databaseEnginesSection

                // Databases Grid / Explorer
                databasesListSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $isNewDBSheetPresented) {
            CreateDatabaseSheet(
                isPresented: $isNewDBSheetPresented,
                onCreated: { newDb in
                    feedbackMessage = "Database '\(newDb)' created successfully."
                }
            )
            .environmentObject(appState)
        }
        .alert(isPresented: $isDropAlertPresented) {
            Alert(
                title: Text("Drop Database?"),
                message: Text("Are you sure you want to permanently drop database '\(dbToDrop ?? "")'? This cannot be undone."),
                primaryButton: .destructive(Text("Drop")) {
                    if let target = dbToDrop {
                        Task {
                            await appState.dropDatabase(name: target)
                            feedbackMessage = "Database '\(target)' was dropped."
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MariaDB & Databases")
                    .font(.system(size: 20, weight: .bold))
                Text("Local database instances, schema explorer, backup & restore, and database engine catalogs")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    isNewDBSheetPresented = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New Database")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button(action: {
                    Task { await appState.refreshDatabases() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Rescan MariaDB databases via /tmp/mysql.sock")
            }
        }
    }

    // MARK: - Connection Status Section
    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isMariaDBRunning ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(isMariaDBRunning ? "MariaDB Service Active" : "MariaDB Service Stopped")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        let confPath = "/opt/local/etc/mariadb-10.11/my.cnf"
                        NSWorkspace.shared.selectFile(confPath, inFileViewerRootedAtPath: "/opt/local/etc/mariadb-10.11")
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text("Open my.cnf")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        let dataPath = "/opt/local/var/db/mariadb-10.11"
                        NSWorkspace.shared.open(URL(fileURLWithPath: dataPath))
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Reveal Datadir")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let mariaService = appState.services.first(where: { $0.name.contains("mariadb") || $0.name.contains("mysql") }) {
                        Button(action: {
                            Task { await appState.restartService(mariaService) }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart DB")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Connection Metrics Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                metricCard(
                    title: "UNIX Socket",
                    value: appState.defaultSocketPath,
                    statusText: isSocketConnected ? "Connected" : "Missing",
                    isGood: isSocketConnected,
                    icon: "cable.connector"
                )

                metricCard(
                    title: "TCP Host & Port",
                    value: "127.0.0.1:3306",
                    statusText: isMariaDBRunning ? "Listening" : "Inactive",
                    isGood: isMariaDBRunning,
                    icon: "network"
                )

                metricCard(
                    title: "Engine / Datadir",
                    value: "MariaDB 10.11.19 LTS",
                    statusText: "\(appState.databases.count) Databases",
                    isGood: true,
                    icon: "cylinder.split.1x2"
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func metricCard(
        title: String,
        value: String,
        statusText: String,
        isGood: Bool,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isGood ? .green : .orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isGood ? Color.green : Color.orange).opacity(0.12))
                    .cornerRadius(4)
            }

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Alternative Database Engines Section
    private var databaseEnginesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Database Engines Catalog")
                .font(.system(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                // MariaDB 10.11 (Active host engine)
                engineCard(
                    title: "MariaDB 10.11 LTS",
                    subtitle: "Fast, resilient, and enterprise-grade relational database",
                    portName: "mariadb-10.11-server",
                    isInstalled: true,
                    isActive: true
                )

                // MariaDB 11.4 LTS
                engineCard(
                    title: "MariaDB 11.4 LTS",
                    subtitle: "Modern LTS release with optimized subqueries & InnoDB",
                    portName: "mariadb-11.4-server",
                    isInstalled: false,
                    isActive: false
                )

                // MySQL 8.0 LTS
                engineCard(
                    title: "MySQL 8.0 LTS",
                    subtitle: "Official Oracle MySQL release with Window Functions & Roles",
                    portName: "mysql8-server",
                    isInstalled: false,
                    isActive: false
                )
            }
        }
    }

    private func engineCard(
        title: String,
        subtitle: String,
        portName: String,
        isInstalled: Bool,
        isActive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            Spacer(minLength: 4)

            HStack {
                if isActive {
                    Text("ACTIVE ENGINE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                } else if isInstalled {
                    Text("INSTALLED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                } else {
                    Button(action: {
                        selectedEngineToInstall = (title, portName)
                        isEngineInstallAlertPresented = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("Install")
                        }
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(minHeight: 90)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .alert(isPresented: $isEngineInstallAlertPresented) {
            Alert(
                title: Text("Install \(selectedEngineToInstall?.name ?? "Database Engine")?"),
                message: Text("This will execute 'port install \(selectedEngineToInstall?.portName ?? "")' via MacPorts. Make sure to stop conflicting engines on port 3306 before starting."),
                primaryButton: .default(Text("Install Engine")) {
                    if let port = selectedEngineToInstall?.portName {
                        Task {
                            await appState.installDatabaseEngine(portName: port)
                            feedbackMessage = "Installation for \(port) queued."
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Databases Explorer Section
    private var databasesListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(appState.databases.count) User Database\(appState.databases.count == 1 ? "" : "s") Detected")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                // Filter / Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Search databases...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 180)
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            if filteredDatabases.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(appState.databases.isEmpty ? "No databases found via /tmp/mysql.sock" : "No databases matching '\(searchQuery)'")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    if appState.databases.isEmpty {
                        Button("Refresh Databases") {
                            Task { await appState.refreshDatabases() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(filteredDatabases, id: \.self) { dbName in
                        databaseCard(dbName: dbName)
                    }
                }
            }
        }
    }

    private func databaseCard(dbName: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cylinder.fill")
                .font(.system(size: 18))
                .foregroundColor(.accentColor.opacity(0.85))

            VStack(alignment: .leading, spacing: 2) {
                Text(dbName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text("Schema: utf8mb4")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Database Action Buttons
            HStack(spacing: 6) {
                // Backup .sql (NSSavePanel)
                Button(action: {
                    promptBackup(dbName: dbName)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.doc")
                        Text("Backup")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export database to .sql dump file using mysqldump")

                // Import .sql (NSOpenPanel)
                Button(action: {
                    promptImport(dbName: dbName)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.doc")
                        Text("Import")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Import SQL file into this database")

                // Drop Database
                Button(action: {
                    dbToDrop = dbName
                    isDropAlertPresented = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Drop this database")
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Native File Panels
    private func promptBackup(dbName: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "Backup Database: \(dbName)"
        let dateStr = DateFormatter.backupDateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "\(dbName)_\(dateStr).sql"
        if #available(macOS 12.0, *) {
            if let sqlUTType = UTType(filenameExtension: "sql") {
                savePanel.allowedContentTypes = [sqlUTType]
            }
        } else {
            savePanel.allowedFileTypes = ["sql"]
        }
        savePanel.canCreateDirectories = true

        if savePanel.runModal() == .OK, let url = savePanel.url {
            Task {
                feedbackMessage = "Dumping database '\(dbName)' to \(url.lastPathComponent)..."
                await appState.dumpDatabase(name: dbName, outputPath: url.path)
                feedbackMessage = "Database '\(dbName)' backed up successfully to \(url.lastPathComponent)."
            }
        }
    }

    private func promptImport(dbName: String) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import SQL into: \(dbName)"
        openPanel.prompt = "Import"
        if #available(macOS 12.0, *) {
            if let sqlUTType = UTType(filenameExtension: "sql") {
                openPanel.allowedContentTypes = [sqlUTType]
            }
        } else {
            openPanel.allowedFileTypes = ["sql"]
        }
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        if openPanel.runModal() == .OK, let url = openPanel.url {
            Task {
                feedbackMessage = "Importing \(url.lastPathComponent) into database '\(dbName)'..."
                await appState.importDatabase(name: dbName, inputPath: url.path)
                feedbackMessage = "Import completed for '\(dbName)' from \(url.lastPathComponent)."
            }
        }
    }
}

// MARK: - DateFormatter Helper
private extension DateFormatter {
    static let backupDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        return df
    }()
}

// MARK: - CreateDatabaseSheet
public struct CreateDatabaseSheet: View {
    @EnvironmentObject public var appState: AppState
    @Binding public var isPresented: Bool
    public let onCreated: (String) -> Void

    @State private var dbName: String = ""
    @State private var charset: String = "utf8mb4"
    @State private var collation: String = "utf8mb4_unicode_ci"
    @State private var validationError: String? = nil
    @State private var isCreating: Bool = false

    public init(
        isPresented: Binding<Bool>,
        onCreated: @escaping (String) -> Void
    ) {
        self._isPresented = isPresented
        self.onCreated = onCreated
    }

    private var isValidDbName: Bool {
        let trimmed = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let regex = "^[a-zA-Z0-9_]+$"
        return trimmed.range(of: regex, options: .regularExpression) != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Create New Database")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Database Name")
                        .font(.system(size: 12, weight: .semibold))

                    TextField("e.g. my_project_db", text: $dbName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    if let error = validationError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else {
                        Text("Only alphanumeric characters and underscores are allowed.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Character Set")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $charset) {
                            Text("utf8mb4 (Recommended)").tag("utf8mb4")
                            Text("utf8").tag("utf8")
                            Text("latin1").tag("latin1")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collation")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $collation) {
                            Text("utf8mb4_unicode_ci").tag("utf8mb4_unicode_ci")
                            Text("utf8mb4_general_ci").tag("utf8mb4_general_ci")
                            Text("utf8_general_ci").tag("utf8_general_ci")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            Spacer()

            Divider()

            // Footer Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    guard isValidDbName else {
                        validationError = "Please enter a valid database name (alphanumeric and underscores)."
                        return
                    }
                    isCreating = true
                    let name = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await appState.createDatabase(name: name)
                        isCreating = false
                        onCreated(name)
                        isPresented = false
                    }
                }) {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Database")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidDbName || isCreating)
            }
        }
        .padding(20)
        .frame(width: 440, height: 320)
    }
}
