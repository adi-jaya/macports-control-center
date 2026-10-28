import SwiftUI
import AppKit

public struct PHPManagerView: View {
    @EnvironmentObject public var appState: AppState

    @State private var selectedVersion: String = "8.3"
    @State private var tuning: PHPIniTuning = PHPIniTuning()
    @State private var isSavingTuning: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var versionToUninstall: String? = nil
    @State private var isUninstallAlertPresented: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Feedback Banner
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

                // PHP Version Cards (8.1 - 8.5)
                phpVersionsSection

                Divider()

                // Extensions & Core Modules
                extensionsSection

                Divider()

                // Quick Tuning Form
                quickTuningSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            initializeSelection()
        }
        .onChange(of: appState.phpVersions) { _ in
            syncTuningWithSelection()
        }
        .alert(isPresented: $isUninstallAlertPresented) {
            Alert(
                title: Text("Clean Uninstall PHP \(versionToUninstall ?? "")?"),
                message: Text("This will stop PHP-FPM, uninstall 'php\(versionToUninstall?.replacingOccurrences(of: ".", with: "") ?? "")' with --follow-dependents, and clean up leaves."),
                primaryButton: .destructive(Text("Uninstall")) {
                    if let v = versionToUninstall {
                        Task {
                            await appState.uninstallPHPVersion(v)
                            feedbackMessage = "Uninstalled PHP \(v) bundle and cleaned leaves."
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func initializeSelection() {
        if let cliDefault = appState.phpVersions.first(where: { $0.isCLIDefault })?.version {
            selectedVersion = cliDefault
        } else if let firstInstalled = appState.phpVersions.first(where: { $0.isInstalled })?.version {
            selectedVersion = firstInstalled
        } else {
            selectedVersion = "8.3"
        }
        syncTuningWithSelection()
    }

    private func syncTuningWithSelection() {
        tuning = appState.loadQuickTuning(version: selectedVersion)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PHP & Extensions Manager")
                    .font(.system(size: 20, weight: .bold))
                Text("Multi-PHP concurrent pools (8.1 – 8.5), CLI default selector, MacPorts extensions, and php.ini tuning")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        for php in appState.phpVersions where php.isInstalled {
                            _ = await appState.commandRunner.runShell("sudo -n /opt/local/bin/port reload \(php.portName)-fpm || sudo -n /opt/local/bin/port load \(php.portName)-fpm", label: "restart-\(php.portName)-fpm")
                        }
                        await appState.refreshPHPVersions()
                        feedbackMessage = "Restarted all active PHP-FPM pools."
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Restart All FPM Pools")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: {
                    Task { await appState.refreshPHPVersions() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Refresh PHP versions and extensions status")
            }
        }
    }

    // MARK: - PHP Versions Grid Section
    private var phpVersionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PHP Versions & FPM Pools")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("Active CLI: \(appState.phpVersions.first(where: \.isCLIDefault)?.portName ?? "None")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(appState.phpVersions) { item in
                    phpVersionCard(item)
                }
            }
        }
    }

    // MARK: - Single PHP Version Card
    private func phpVersionCard(_ item: PHPVersionItem) -> some View {
        let isSelected = (selectedVersion == item.version)

        return VStack(alignment: .leading, spacing: 10) {
            // Card Title & Badges
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("PHP \(item.version)")
                            .font(.system(size: 15, weight: .bold))

                        if item.isCLIDefault {
                            Text("★ CLI Default")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.18))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text("Package: \(item.portName)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Installed status pill
                Text(item.isInstalled ? "INSTALLED" : "AVAILABLE")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.isInstalled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                    .foregroundColor(item.isInstalled ? .green : .secondary)
                    .cornerRadius(4)
            }

            // FPM Pool Info
            if item.isInstalled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.isFPMRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)

                    Text("FPM: 127.0.0.1:\(item.fpmPort)")
                        .font(.system(size: 11, design: .monospaced))

                    Text(item.isFPMRunning ? "(Running)" : "(Stopped)")
                        .font(.system(size: 11))
                        .foregroundColor(item.isFPMRunning ? .green : .secondary)

                    Spacer()

                    Text("\(item.installedExtensions.count) Exts")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Includes FPM, MySQL, cURL, OpenSSL, GD, Zip & MBString bundle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Actions Row
            if item.isInstalled {
                HStack(spacing: 6) {
                    if !item.isCLIDefault {
                        Button("Set Default") {
                            Task {
                                await appState.runPortSelect(group: "php", option: item.portName)
                                feedbackMessage = "Set \(item.portName) as active CLI default."
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(item.isFPMRunning ? "Stop FPM" : "Start FPM") {
                        Task {
                            let action = item.isFPMRunning ? "unload" : "load"
                            _ = await appState.commandRunner.runShell("sudo -n /opt/local/bin/port \(action) \(item.portName)-fpm", label: "\(action)-\(item.portName)-fpm")
                            await appState.refreshPHPVersions()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(item.isFPMRunning ? .red : .green)
                    .controlSize(.small)

                    Spacer()

                    if isSelected {
                        Button("Selected") {
                            selectedVersion = item.version
                            syncTuningWithSelection()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Select") {
                            selectedVersion = item.version
                            syncTuningWithSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(action: {
                        versionToUninstall = item.version
                        isUninstallAlertPresented = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Clean uninstall PHP \(item.version)")
                }
            } else {
                Button(action: {
                    Task {
                        await appState.installPHPBundle(item.version)
                        feedbackMessage = "Installed PHP \(item.version) bundle and configured www.conf."
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("1-Click Install Bundle")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            selectedVersion = item.version
            syncTuningWithSelection()
        }
    }

    // MARK: - Extensions Section
    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            let activePHPItem = appState.phpVersions.first(where: { $0.version == selectedVersion })
            let isInstalled = activePHPItem?.isInstalled ?? false

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PHP \(selectedVersion) Extensions")
                        .font(.system(size: 14, weight: .bold))
                    Text("Check or uncheck MacPorts subports (php\(selectedVersion.replacingOccurrences(of: ".", with: ""))-[ext]) to install or uninstall")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !isInstalled {
                    Text("⚠️ PHP \(selectedVersion) is not installed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            // 20 MacPorts Extensions Checkbox Grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(MacPortsService.supportedPHPExtensionSubports, id: \.self) { ext in
                    let isExtInstalled = activePHPItem?.installedExtensions.contains(ext) ?? false

                    Toggle(isOn: Binding(
                        get: { isExtInstalled },
                        set: { shouldInstall in
                            guard isInstalled else { return }
                            Task {
                                await appState.togglePHPExtension(version: selectedVersion, ext: ext, install: shouldInstall)
                                feedbackMessage = "\(shouldInstall ? "Installed" : "Uninstalled") php\(selectedVersion.replacingOccurrences(of: ".", with: ""))-\(ext)."
                            }
                        }
                    )) {
                        HStack(spacing: 4) {
                            Text(ext)
                                .font(.system(size: 11, design: .monospaced))
                            if isExtInstalled {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!isInstalled)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }

            // Read-Only Built-In Core Modules
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Built-in Core Modules (statically compiled into MacPorts PHP binary; no subport required):")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(MacPortsService.builtInPHPCoreModules, id: \.self) { module in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(module)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        }
    }

    // MARK: - Quick Tuning Form
    private var quickTuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Tuning (php.ini & Nginx)")
                    .font(.system(size: 14, weight: .bold))
                Text("Adjust upload limits and execution times for PHP \(selectedVersion) and reload servers safely")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    tuningField(
                        label: "memory_limit (php.ini)",
                        description: "Maximum memory allocated per PHP script",
                        value: $tuning.memoryLimit,
                        placeholder: "e.g. 512M"
                    )

                    tuningField(
                        label: "upload_max_filesize (php.ini)",
                        description: "Maximum allowed size for uploaded files",
                        value: $tuning.uploadMaxFilesize,
                        placeholder: "e.g. 64M"
                    )
                }

                HStack(spacing: 16) {
                    tuningField(
                        label: "post_max_size (php.ini)",
                        description: "Max size of POST data (should be >= upload_max_filesize)",
                        value: $tuning.postMaxSize,
                        placeholder: "e.g. 64M"
                    )

                    tuningField(
                        label: "max_execution_time (php.ini)",
                        description: "Max execution time in seconds",
                        value: $tuning.maxExecutionTime,
                        placeholder: "e.g. 120"
                    )
                }

                tuningField(
                    label: "client_max_body_size (nginx.conf)",
                    description: "Maximum client request body size accepted by Nginx",
                    value: $tuning.nginxClientMaxBodySize,
                    placeholder: "e.g. 64M"
                )
            }

            HStack {
                Spacer()

                Button(action: {
                    saveQuickTuning()
                }) {
                    if isSavingTuning {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save & Apply Tuning")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingTuning)
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

    private func tuningField(label: String, description: String, value: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
            TextField(placeholder, text: value)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveQuickTuning() {
        isSavingTuning = true
        Task {
            await appState.applyQuickTuning(version: selectedVersion, tuning: tuning)
            isSavingTuning = false
            feedbackMessage = "Applied tuning to PHP \(selectedVersion) (php.ini) and Nginx (nginx.conf)."
        }
    }
}
