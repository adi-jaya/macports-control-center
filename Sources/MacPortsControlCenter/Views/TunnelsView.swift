import SwiftUI
import AppKit

public struct TunnelsView: View {
    @EnvironmentObject public var appState: AppState

    @State private var customPort: String = ""
    @State private var customLabel: String = ""
    @State private var copiedTunnelId: String? = nil
    @State private var validationError: String? = nil

    private let presets: [(port: String, label: String)] = [
        ("3000", "Next.js Dev"),
        ("5173", "Vite Frontend"),
        ("8000", "FastAPI / Python"),
        ("8080", "HTTP Alt / Node")
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header & Controls
                headerSection

                // Missing CLI Banner
                if !appState.isCloudflaredInstalled {
                    missingCliBanner
                }

                // Expose Port Card
                exposePortCard

                // Active Tunnels Section
                activeTunnelsSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tunnels Hub")
                    .font(.system(size: 20, weight: .bold))
                Text("Expose local services to the internet via Cloudflare Quick Tunnel (trycloudflare.com)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    appState.stopAllTunnels()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("Stop All Tunnels")
                    }
                }
                .mpButton(.bordered, tint: .red)
                .controlSize(.regular)
                .disabled(appState.activeTunnels.isEmpty)

                Button(action: {
                    appState.checkCloudflaredInstallation()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .mpButton(.borderless)
                .help("Check cloudflared binary status")
            }
        }
    }

    // MARK: - Missing CLI Banner
    private var missingCliBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("cloudflared CLI not detected")
                    .font(.system(size: 13, weight: .bold))
                Text("Cloudflare Tunnel requires the 'cloudflared' package from MacPorts. Install it to enable 1-click tunneling.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                Task { await appState.installCloudflared() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                    Text("Install via MacPorts")
                }
            }
            .mpButton(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    // MARK: - Expose Port Card
    private var exposePortCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("Expose Local Port")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            // Input Fields
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. 5173", text: $customPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Label (optional)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. Vite SPA, Next.js Dev", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(" ")
                        .font(.system(size: 11))
                    Button(action: {
                        startCustomTunnel()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Start Tunnel")
                        }
                    }
                    .mpButton(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(customPort.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // Preset Chips
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Presets:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(presets, id: \.port) { preset in
                        Button(action: {
                            customPort = preset.port
                            customLabel = preset.label
                            validationError = nil
                        }) {
                            Text("\(preset.port): \(preset.label)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .mpButton(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if let err = validationError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func startCustomTunnel() {
        let cleanPort = customPort.trimmingCharacters(in: .whitespaces)
        guard let portInt = Int(cleanPort), portInt > 0, portInt <= 65535 else {
            validationError = "Please enter a valid port number between 1 and 65535."
            return
        }
        validationError = nil
        let cleanLabel = customLabel.trimmingCharacters(in: .whitespaces)
        appState.startTunnel(
            port: cleanPort,
            label: cleanLabel.isEmpty ? "Port \(cleanPort)" : cleanLabel,
            isVHost: false,
            isSSL: false,
            hostHeader: "localhost"
        )
        customPort = ""
        customLabel = ""
    }

    // MARK: - Active Tunnels Section
    private var activeTunnelsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active Tunnels (\(appState.activeTunnels.count))")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            if appState.activeTunnels.isEmpty {
                emptyTunnelsView
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appState.activeTunnels.values.sorted(by: { $0.startedAt < $1.startedAt })) { tunnel in
                        tunnelCard(tunnel)
                    }
                }
            }
        }
    }

    // MARK: - Tunnel Card
    private func tunnelCard(_ tunnel: ActiveTunnel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Status, Target & Label
            HStack(spacing: 8) {
                Circle()
                    .fill(tunnel.status == .active ? Color.green : (tunnel.status == .starting ? Color.orange : Color.red))
                    .frame(width: 8, height: 8)

                Text(tunnel.status == .active ? "Live Tunnel" : (tunnel.status == .starting ? "Starting..." : "Error"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tunnel.status == .active ? .green : (tunnel.status == .starting ? .orange : .red))

                Text("localhost:\(tunnel.port)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                if !tunnel.label.isEmpty {
                    Text("(\(tunnel.label))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Type badge
                Text(tunnel.isVHost ? "Virtual Host" : "Custom Port")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)

                Spacer()

                Button(action: {
                    appState.stopTunnel(tunnelId: tunnel.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Stop Tunnel")
                    }
                }
                .mpButton(.bordered, tint: .red)
                .controlSize(.small)
            }

            // Public URL Row
            if let publicUrl = tunnel.publicUrl {
                HStack(spacing: 8) {
                    Text(publicUrl)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .textSelection(.enabled)
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(publicUrl, forType: .string)
                        copiedTunnelId = tunnel.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copiedTunnelId == tunnel.id {
                                copiedTunnelId = nil
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copiedTunnelId == tunnel.id ? "checkmark" : "doc.on.doc")
                            Text(copiedTunnelId == tunnel.id ? "Copied" : "Copy URL")
                        }
                    }
                    .mpButton(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        if let url = URL(string: publicUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open Browser")
                        }
                    }
                    .mpButton(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(6)
            } else if let err = tunnel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Connecting to Cloudflare edge and generating public URL...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
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

    // MARK: - Empty State
    private var emptyTunnelsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No active Cloudflare tunnels.")
                .font(.system(size: 13, weight: .medium))
            Text("Start a tunnel using the form above for ad-hoc dev ports (e.g. Vite 5173, Next.js 3000), or click 'Tunnel' on any virtual host card in the Virtual Hosts tab.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}
