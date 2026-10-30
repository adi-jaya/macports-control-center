import SwiftUI
import AppKit

public struct SitesView: View {
    @EnvironmentObject public var appState: AppState

    @State private var isNewVHostSheetPresented: Bool = false
    @State private var selectedVHostForEdit: VHostItem? = nil
    @State private var vhostToDelete: VHostItem? = nil
    @State private var isDeleteAlertPresented: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                // Sites List / Table
                sitesListSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $isNewVHostSheetPresented) {
            NewVHostSheet(isPresented: $isNewVHostSheetPresented, onSaved: { name in
                feedbackMessage = "Virtual Host '\(name)' created and validated successfully."
            })
            .environmentObject(appState)
        }
        .sheet(item: $selectedVHostForEdit) { vhost in
            EditVHostSheet(vhost: vhost, isPresented: Binding(
                get: { selectedVHostForEdit != nil },
                set: { if !$0 { selectedVHostForEdit = nil } }
            ), onSaved: {
                feedbackMessage = "Virtual Host '\(vhost.fileName)' updated successfully."
            })
            .environmentObject(appState)
        }
        .alert(isPresented: $isDeleteAlertPresented) {
            Alert(
                title: Text("Delete Virtual Host?"),
                message: Text("Are you sure you want to remove '\(vhostToDelete?.fileName ?? "")'? This deletes the Nginx configuration file in /opt/local/etc/nginx/servers/."),
                primaryButton: .destructive(Text("Delete")) {
                    if let target = vhostToDelete {
                        Task {
                            await appState.deleteVHost(fileName: target.fileName)
                            feedbackMessage = "Removed virtual host '\(target.fileName)'."
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
                Text("Nginx Virtual Hosts")
                    .font(.system(size: 20, weight: .bold))
                Text("Manage server blocks in /opt/local/etc/nginx/servers/ with automatic Laravel .env detection")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    isNewVHostSheetPresented = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New Virtual Host")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button(action: {
                    Task { await appState.reloadNginx() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reload Nginx")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Validates configuration syntax and reloads Nginx server")

                Button(action: {
                    Task { await appState.refreshVHosts() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Rescan /opt/local/etc/nginx/servers/")
            }
        }
    }

    // MARK: - Sites List Section
    private var sitesListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(appState.vhosts.count) Virtual Host\(appState.vhosts.count == 1 ? "" : "s") Detected")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }

            if appState.vhosts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No Nginx virtual host configurations found.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Click '+ New Virtual Host' above to configure your first Laravel or static site.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appState.vhosts) { vhost in
                        vhostCard(vhost)
                    }
                }
            }
        }
    }

    // MARK: - VHost Card View
    private func vhostCard(_ vhost: VHostItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Server Name, Port & Badges
            HStack(spacing: 8) {
                // Host / Domain Icon
                Image(systemName: vhost.sslEnabled ? "lock.fill" : "globe")
                    .font(.system(size: 14))
                    .foregroundColor(vhost.sslEnabled ? .green : .accentColor)

                // Server Name & Port
                Text(vhost.serverName.isEmpty ? "localhost" : vhost.serverName)
                    .font(.system(size: 14, weight: .bold))

                Text(":\(vhost.listenPort.isEmpty ? "80" : vhost.listenPort)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                // SSL Badge
                if vhost.sslEnabled {
                    Text("HTTPS")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.18))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                } else {
                    Text("HTTP")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }

                // FastCGI Pass Badge
                if !vhost.fastcgiPass.isEmpty {
                    Text("FPM: \(vhost.fastcgiPass)")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

                Spacer()

                // Config file name
                Text(vhost.fileName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Middle Row: Root Path
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(vhost.rootPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            // Detected Laravel Environment Info (if .env found)
            if vhost.laravelDatabase != nil || vhost.laravelAppURL != nil {
                HStack(spacing: 12) {
                    if let db = vhost.laravelDatabase {
                        HStack(spacing: 4) {
                            Image(systemName: "cylinder.split.1x2")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                            Text("DB: \(db)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                    }

                    if let url = vhost.laravelAppURL {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text("APP_URL: \(url)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
            }

            Divider()

            // Bottom Actions Bar
            HStack(spacing: 8) {
                // Open in Browser
                Button(action: {
                    openInBrowser(vhost)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                        Text("Open Browser")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Open in Finder
                Button(action: {
                    openInFinder(vhost)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text("Open Folder")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Fix Storage Permissions
                Button(action: {
                    Task {
                        await appState.fixStoragePermissions(for: vhost)
                        feedbackMessage = "Fixed storage & cache permissions for '\(vhost.fileName)'."
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11))
                        Text("Fix Permissions")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Executes chmod -R u+rwX storage bootstrap/cache")

                // Edit .conf
                Button(action: {
                    selectedVHostForEdit = vhost
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                        Text("Edit Conf")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                // Delete VHost Button
                Button(action: {
                    vhostToDelete = vhost
                    isDeleteAlertPresented = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete virtual host file")
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Open in Browser
    private func openInBrowser(_ vhost: VHostItem) {
        let urlString: String
        if let appURL = vhost.laravelAppURL, !appURL.isEmpty, appURL.hasPrefix("http") {
            urlString = appURL
        } else if vhost.sslEnabled {
            let port = (vhost.listenPort == "443" || vhost.listenPort.isEmpty) ? "" : ":\(vhost.listenPort)"
            let host = vhost.serverName.isEmpty ? "localhost" : vhost.serverName.split(separator: " ").first.map(String.init) ?? "localhost"
            urlString = "https://\(host)\(port)"
        } else {
            let port = (vhost.listenPort == "80" || vhost.listenPort.isEmpty) ? "" : ":\(vhost.listenPort)"
            let host = vhost.serverName.isEmpty ? "localhost" : vhost.serverName.split(separator: " ").first.map(String.init) ?? "localhost"
            urlString = "http://\(host)\(port)"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Open in Finder
    private func openInFinder(_ vhost: VHostItem) {
        let path = vhost.rootPath
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            errorMessage = "Folder does not exist: \(path)"
        }
    }
}

// MARK: - New Virtual Host Sheet
public struct NewVHostSheet: View {
    @EnvironmentObject public var appState: AppState
    @Binding public var isPresented: Bool
    public var onSaved: (String) -> Void

    @State private var projectName: String = ""
    @State private var fileName: String = ""
    @State private var rootPath: String = ""
    @State private var accessMode: AccessMode = .portBased
    @State private var listenPort: String = "8081"
    @State private var serverName: String = "localhost 127.0.0.1"
    @State private var fpmPort: Int = 9000
    @State private var templateType: VHostTemplateType = .laravel
    @State private var enableHTTPS: Bool = false
    @State private var isSaving: Bool = false
    @State private var validationErrorMessage: String? = nil

    public enum AccessMode: String, CaseIterable, Identifiable {
        case portBased = "Port-Based (e.g. 8081)"
        case testDomain = "Local Domain (*.test)"
        public var id: String { rawValue }
    }

    public init(isPresented: Binding<Bool>, onSaved: @escaping (String) -> Void) {
        self._isPresented = isPresented
        self.onSaved = onSaved
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Virtual Host")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let err = validationErrorMessage {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                    }

                    // 1. Root Path Chooser
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Root Directory:")
                            .font(.system(size: 12, weight: .semibold))

                        HStack {
                            TextField("Path to public or project root", text: $rootPath)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)

                            Button("Browse...") {
                                chooseFolder()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // 2. File Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Configuration File Name:")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("e.g. myapp.conf", text: $fileName)
                            .font(.system(size: 12, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    // 3. Access Mode
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Access Mode:")
                            .font(.system(size: 12, weight: .semibold))

                        Picker("", selection: $accessMode) {
                            ForEach(AccessMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: accessMode) { newMode in
                            if newMode == .portBased {
                                listenPort = suggestNextFreePort()
                                serverName = "localhost 127.0.0.1"
                            } else {
                                listenPort = enableHTTPS ? "443" : "80"
                                if !projectName.isEmpty {
                                    serverName = "\(projectName).test"
                                }
                            }
                        }
                    }

                    // 4. Server Name & Port
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server Name:")
                                .font(.system(size: 12, weight: .semibold))
                            TextField("e.g. myapp.test or localhost", text: $serverName)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Port:")
                                .font(.system(size: 12, weight: .semibold))
                            TextField("8081", text: $listenPort)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }

                    // 5. Target PHP-FPM Pool
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target PHP-FPM Pool:")
                            .font(.system(size: 12, weight: .semibold))

                        Picker("", selection: $fpmPort) {
                            Text("PHP 8.3 (Port 9000 - Default)").tag(9000)
                            Text("PHP 8.1 (Port 9081)").tag(9081)
                            Text("PHP 8.2 (Port 9082)").tag(9082)
                            Text("PHP 8.4 (Port 9084)").tag(9084)
                            Text("PHP 8.5 (Port 9085)").tag(9085)
                        }
                        .pickerStyle(.menu)
                    }

                    // 6. Template Type
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Virtual Host Template:")
                            .font(.system(size: 12, weight: .semibold))

                        Picker("", selection: $templateType) {
                            Text("Laravel (try_files to index.php with fastcgi)").tag(VHostTemplateType.laravel)
                            Text("SPA / Static (HTML5 fallback try_files)").tag(VHostTemplateType.spa)
                        }
                        .pickerStyle(.radioGroup)
                    }

                    // 7. HTTPS with mkcert
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $enableHTTPS) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Local HTTPS (mkcert)")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Generates and attaches local SSL certificate from /opt/local/etc/nginx/ssl/")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .onChange(of: enableHTTPS) { isHTTPS in
                            if isHTTPS && accessMode == .testDomain {
                                listenPort = "443"
                            } else if !isHTTPS && accessMode == .testDomain {
                                listenPort = "80"
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button(action: {
                    saveVirtualHost()
                }) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Text("Create & Validate Virtual Host")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(rootPath.isEmpty || fileName.isEmpty || isSaving)
            }
            .padding()
        }
        .frame(width: 540, height: 600)
        .onAppear {
            listenPort = suggestNextFreePort()
        }
    }

    // MARK: - Choose Folder Dialog
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project Folder"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let folderName = url.lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-")
            projectName = folderName

            if FileManager.default.fileExists(atPath: "\(path)/public") {
                rootPath = "\(path)/public"
            } else {
                rootPath = path
            }

            if fileName.isEmpty {
                fileName = "\(folderName).conf"
            }
            if accessMode == .testDomain {
                serverName = "\(folderName).test"
            }
        }
    }

    // MARK: - Suggest Next Free Port
    private func suggestNextFreePort() -> String {
        var usedPorts = Set<Int>()
        for vhost in appState.vhosts {
            if let p = Int(vhost.listenPort) {
                usedPorts.insert(p)
            }
        }
        for port in 8081...8100 {
            if !usedPorts.contains(port) {
                return "\(port)"
            }
        }
        return "8081"
    }

    // MARK: - Save Virtual Host
    private func saveVirtualHost() {
        isSaving = true
        validationErrorMessage = nil

        var targetFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !targetFileName.hasSuffix(".conf") {
            targetFileName += ".conf"
        }

        var sslCert: String? = nil
        var sslKey: String? = nil
        if enableHTTPS {
            let domainPrimary = serverName.split(separator: " ").first.map(String.init) ?? "localhost"
            sslCert = "/opt/local/etc/nginx/ssl/\(domainPrimary).pem"
            sslKey = "/opt/local/etc/nginx/ssl/\(domainPrimary).key"
        }

        let content = ConfigFileService.generateVHostConfig(
            serverName: serverName,
            listenPort: listenPort,
            rootPath: rootPath,
            fpmPort: fpmPort,
            template: templateType,
            sslCertPath: sslCert,
            sslKeyPath: sslKey
        )

        Task {
            do {
                try await appState.saveVHost(fileName: targetFileName, content: content)
                await appState.reloadNginx()
                isSaving = false
                isPresented = false
                onSaved(targetFileName)
            } catch {
                isSaving = false
                validationErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Edit Virtual Host Sheet
public struct EditVHostSheet: View {
    @EnvironmentObject public var appState: AppState
    public let vhost: VHostItem
    @Binding public var isPresented: Bool
    public var onSaved: () -> Void

    @State private var fileContent: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    public init(vhost: VHostItem, isPresented: Binding<Bool>, onSaved: @escaping () -> Void) {
        self.vhost = vhost
        self._isPresented = isPresented
        self.onSaved = onSaved
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Virtual Host: \(vhost.fileName)")
                        .font(.system(size: 15, weight: .bold))
                    Text(vhost.filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if let err = errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                }
                .padding(10)
                .background(Color.red.opacity(0.12))
            }

            TextEditor(text: $fileContent)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button(action: {
                    saveChanges()
                }) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Text("Save & Validate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 620, height: 500)
        .onAppear {
            fileContent = (try? String(contentsOfFile: vhost.filePath, encoding: .utf8)) ?? ""
        }
    }

    private func saveChanges() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await appState.saveVHost(fileName: vhost.fileName, content: fileContent)
                await appState.reloadNginx()
                isSaving = false
                isPresented = false
                onSaved()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
