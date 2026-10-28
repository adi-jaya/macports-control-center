import SwiftUI

// MARK: - CommandPaletteView
public struct CommandPaletteView: View {
    @ObservedObject public var appState: AppState
    @State private var query: String = ""
    @FocusState private var isSearchFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            // Semi-transparent backdrop to dismiss on click
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.isCommandPalettePresented = false
                }

            // Floating Palette Card
            VStack(spacing: 0) {
                // Search Input Header
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("Type a command or jump to section...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isSearchFocused)
                        .onSubmit {
                            let matches = appState.filteredPaletteCommands(query: query)
                            if let first = matches.first {
                                first.action()
                            }
                        }

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("ESC")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Filtered Command List
                let commands = appState.filteredPaletteCommands(query: query)
                if commands.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("No commands matching \"\(query)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(commands) { cmd in
                                Button(action: {
                                    cmd.action()
                                }) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(cmd.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            if !cmd.subtitle.isEmpty {
                                                Text(cmd.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "return")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary.opacity(0.6))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.clear)
                                .cornerRadius(6)
                                .padding(.horizontal, 6)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 280)
                }
            }
            .frame(width: 520)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .onExitCommand {
                appState.isCommandPalettePresented = false
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}
