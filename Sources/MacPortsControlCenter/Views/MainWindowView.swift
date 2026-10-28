import SwiftUI

// MARK: - Section Placeholder View
public struct SectionPlaceholderView: View {
    public let section: NavigationSection
    @ObservedObject public var appState: AppState

    public init(section: NavigationSection, appState: AppState) {
        self.section = section
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: section.systemImage)
                .font(.system(size: 48))
                .foregroundColor(.accentColor.opacity(0.8))

            Text(section.displayName)
                .font(.title2.weight(.bold))

            Text("This view will be fully activated in subsequent tasks.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Preview metrics based on section
            Group {
                switch section {
                case .services:
                    Text("\(appState.services.count) services discovered • \(appState.services.filter(\.isRunning).count) running")
                case .sites:
                    Text("\(appState.vhosts.count) Nginx virtual hosts configured")
                case .php:
                    Text("\(appState.phpVersions.count) PHP versions tracked • Default: \(appState.phpVersions.first(where: \.isCLIDefault)?.version ?? "None")")
                case .database:
                    Text("\(appState.databases.count) MariaDB databases detected")
                case .packages:
                    Text("\(appState.packages.count) packages loaded • \(appState.portSelectGroups.count) port select groups")
                case .logs:
                    Text("Live log tailer ready for Nginx, PHP-FPM, and MariaDB")
                case .docs:
                    Text("\(appState.docFiles.count) documentation guides available")
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - MainWindowView
public struct MainWindowView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            // Main App Shell Layout
            HStack(spacing: 0) {
                // Left Navigation Sidebar
                sidebarView
                    .frame(width: 210)
                    .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Right Content Area & Docked Terminal Drawer
                VStack(spacing: 0) {
                    // Top Status Bar & Quick Actions
                    topStatusBar

                    Divider()

                    // Dynamic Section Content Area
                    contentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom Docked Live Terminal Drawer
                    TerminalDrawerView(
                        runner: appState.commandRunner,
                        isExpanded: $appState.isTerminalDrawerExpanded
                    )
                }
            }

            // Command Palette (Cmd + K) Modal Overlay
            if appState.isCommandPalettePresented {
                CommandPaletteView(appState: appState)
                    .transition(.opacity)
            }
        }
        .environmentObject(appState)
        .frame(minWidth: 920, minHeight: 620)
        // Hidden button to catch Cmd + K keyboard shortcut
        .background(
            Button("") {
                appState.isCommandPalettePresented.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
        )
    }

    // MARK: - Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Branding Header
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacPorts")
                        .font(.system(size: 12, weight: .bold))
                    Text("Control Center")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider()

            // Navigation Sections List
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(NavigationSection.allCases) { section in
                        let isSelected = (appState.selectedSection == section)
                        Button(action: {
                            appState.selectedSection = section
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 20)
                                    .foregroundColor(isSelected ? .white : .secondary)

                                Text(section.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .white : .primary)

                                Spacer()

                                // Section Badge
                                if section == .services {
                                    let running = appState.services.filter(\.isRunning).count
                                    if running > 0 {
                                        Text("\(running)")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(isSelected ? Color.white.opacity(0.25) : Color.green.opacity(0.2))
                                            .foregroundColor(isSelected ? .white : .green)
                                            .cornerRadius(8)
                                    }
                                } else if section == .database && !appState.databases.isEmpty {
                                    Text("\(appState.databases.count)")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                                        .foregroundColor(isSelected ? .white : .secondary)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Spacer()

            Divider()

            // Footer Command Palette Hint
            Button(action: {
                appState.isCommandPalettePresented = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.system(size: 11))
                    Text("Palette (Cmd + K)")
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Top Status Bar
    private var topStatusBar: some View {
        HStack(spacing: 12) {
            // Running daemons summary
            let runningCount = appState.services.filter(\.isRunning).count
            HStack(spacing: 6) {
                Circle()
                    .fill(runningCount > 0 ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text("\(runningCount) Running")
                    .font(.system(size: 12, weight: .medium))
            }

            // Doctor health status
            let failingDoctorChecks = appState.doctorChecks.filter { !$0.isHealthy }
            if !failingDoctorChecks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 11))
                    Text("\(failingDoctorChecks.count) Issue\(failingDoctorChecks.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.yellow)
                }
            }

            Spacer()

            // Quick Action: Restart Web Stack
            Button(action: {
                Task { await appState.restartWebStack() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Restart Stack")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Quick Action: Doctor Auto-Fix
            if !failingDoctorChecks.isEmpty {
                Button(action: {
                    Task { await appState.runDoctorAutoFix() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cross.case.fill")
                        Text("Auto-Fix")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Quick Action: Refresh
            Button(action: {
                Task { await appState.refreshAll() }
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Refresh all services and configurations")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Content Area
    @ViewBuilder
    private var contentArea: some View {
        switch appState.selectedSection {
        case .services:
            ServicesView()
        case .sites:
            SitesView()
        case .php:
            PHPManagerView()
        case .database:
            DatabaseView()
        case .packages:
            PackagesView()
        case .logs:
            LogsView()
        case .docs:
            DocsView()
        }
    }
}
