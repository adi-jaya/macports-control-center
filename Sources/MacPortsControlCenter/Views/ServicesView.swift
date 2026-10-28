import SwiftUI
import AppKit

public struct ServicesView: View {
    @EnvironmentObject public var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header & Global Stack Controls
                headerSection

                // Stack Doctor Panel (5 Guardrails AGENTS.md)
                stackDoctorSection

                // Auto-Discovered LaunchDaemons Services
                servicesListSection

                // Ecosystem Utilities
                ecosystemToolsSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header & Global Actions
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Services & Ecosystem Tools")
                        .font(.system(size: 20, weight: .bold))
                    Text("Manage MacPorts LaunchDaemons, system services, and local development tools")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Global Control Action Buttons
                HStack(spacing: 8) {
                    Button(action: {
                        Task { await appState.startWebStack() }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Start Stack")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .help("Load Nginx and PHP 8.3 FPM")

                    Button(action: {
                        Task { await appState.restartWebStack() }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Restart Stack")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Reload or restart Nginx and PHP 8.3 FPM")

                    Button(action: {
                        Task { await appState.stopAllServices() }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop All")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Unload all running MacPorts services")

                    Button(action: {
                        Task { await appState.refreshAll() }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh services and health status")
                }
            }
        }
    }

    // MARK: - Stack Doctor Panel
    private var stackDoctorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let failingCount = appState.doctorChecks.filter { !$0.isHealthy }.count
            let isAllHealthy = failingCount == 0 && !appState.doctorChecks.isEmpty

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: isAllHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isAllHealthy ? .green : .yellow)

                    Text("Stack Doctor (Host Health & Guardrails)")
                        .font(.system(size: 14, weight: .bold))

                    if isAllHealthy {
                        Text("5/5 Checks Passed")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                    } else if failingCount > 0 {
                        Text("\(failingCount) Issue\(failingCount == 1 ? "" : "s") Detected")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundColor(.yellow)
                            .cornerRadius(10)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        Task { await appState.refreshDoctorChecks() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                            Text("Re-Check")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        Task { await appState.runDoctorAutoFix() }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                            Text("⚡ 1-Click Auto-Fix")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .help("Applies safe permissions and fixes non-compliant configurations via admin prompt")
                }
            }

            // Checks List
            VStack(spacing: 8) {
                if appState.doctorChecks.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Evaluating host health checks...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                } else {
                    ForEach(appState.doctorChecks) { check in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: check.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(check.isHealthy ? .green : .yellow)
                                .font(.system(size: 15))
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(check.title)
                                        .font(.system(size: 13, weight: .semibold))

                                    Text(check.isHealthy ? "Healthy" : "Attention Required")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(check.isHealthy ? Color.green.opacity(0.12) : Color.yellow.opacity(0.15))
                                        .foregroundColor(check.isHealthy ? .green : .orange)
                                        .cornerRadius(4)
                                }

                                Text(check.detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !check.isHealthy {
                                    HStack(spacing: 4) {
                                        Text("Recommended Fix:")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(check.fixActionDescription)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - LaunchDaemons Services Section
    private var servicesListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacPorts Services (LaunchDaemons)")
                        .font(.system(size: 14, weight: .bold))
                    Text("Scanned from /opt/local/etc/LaunchDaemons with active process matching")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(appState.services.count) Discovered • \(appState.services.filter(\.isRunning).count) Running")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if appState.services.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No MacPorts LaunchDaemons found in /opt/local/etc/LaunchDaemons")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(appState.services) { service in
                        serviceCard(service)
                    }
                }
            }
        }
    }

    // MARK: - Service Card View
    private func serviceCard(_ service: ServiceItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                // Status Indicator Dot
                Circle()
                    .fill(service.isRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(service.name)
                        .font(.system(size: 13, weight: .bold))
                    Text(service.plistName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Running Status Badge
                Text(service.isRunning ? "RUNNING" : "STOPPED")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(service.isRunning ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                    .foregroundColor(service.isRunning ? .green : .secondary)
                    .cornerRadius(4)
            }

            // Boot Status & Details
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: service.isEnabledAtBoot ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 11))
                        .foregroundColor(service.isEnabledAtBoot ? .blue : .secondary)
                    Text(service.isEnabledAtBoot ? "Enabled at Boot" : "Disabled at Boot")
                        .font(.system(size: 11))
                        .foregroundColor(service.isEnabledAtBoot ? .primary : .secondary)
                }

                if !service.detail.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(service.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Card Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    Task { await appState.toggleService(service) }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: service.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 9))
                        Text(service.isRunning ? "Stop" : "Start")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(service.isRunning ? .red : .green)
                .controlSize(.small)

                if service.isRunning {
                    Button(action: {
                        Task { await appState.restartService(service) }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Restart")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reloads service via MacPorts")
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(service.isRunning ? Color.green.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Ecosystem Tools Section
    private var ecosystemToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("1-Click Ecosystem Utilities")
                    .font(.system(size: 14, weight: .bold))
                Text("Essential local web development stack utilities and dependency tools")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                // dnsmasq Tool
                toolCard(
                    title: "dnsmasq (*.test DNS)",
                    icon: "network",
                    description: "Automatic local resolver for *.test domains pointing to 127.0.0.1 without editing /etc/hosts.",
                    buttonTitle: "Setup & Start dnsmasq",
                    action: {
                        Task { await appState.setupDnsmasq() }
                    }
                )

                // mkcert Tool
                toolCard(
                    title: "mkcert (Local HTTPS)",
                    icon: "lock.shield",
                    description: "Zero-config local CA and SSL certificate generation for *.test and localhost.",
                    buttonTitle: "Install & Setup mkcert",
                    action: {
                        Task { await appState.setupMkcert() }
                    }
                )

                // Redis Tool
                toolCard(
                    title: "Redis Server",
                    icon: "bolt.horizontal",
                    description: "In-memory database for Laravel caching, session management, and queued background jobs.",
                    buttonTitle: "Install / Start Redis",
                    action: {
                        Task { await appState.setupRedis() }
                    }
                )

                // fnm & Composer Tool
                toolCard(
                    title: "Node.js (fnm) & Composer",
                    icon: "shippingbox",
                    description: "Fast Node Manager (fnm) and PHP Composer dependency manager for MacPorts dev workflow.",
                    buttonTitle: "Install fnm & Composer",
                    action: {
                        Task { await appState.setupFnmAndComposer() }
                    }
                )
            }
        }
    }

    // MARK: - Generic Tool Card View
    private func toolCard(
        title: String,
        icon: String,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }

            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 38, alignment: .topLeading)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
