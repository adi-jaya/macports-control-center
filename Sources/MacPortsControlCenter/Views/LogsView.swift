import SwiftUI
import AppKit

// MARK: - LogTypeTab
public enum LogTypeTab: String, CaseIterable, Identifiable {
    case nginxError = "Nginx error.log"
    case nginxAccess = "Nginx access.log"
    case phpFpm = "PHP-FPM Log"
    case mariaDB = "MariaDB error.log"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .nginxError: return "exclamationmark.triangle"
        case .nginxAccess: return "network"
        case .phpFpm: return "chevron.left.forwardslash.chevron.right"
        case .mariaDB: return "cylinder.split.1x2"
        }
    }
}

// MARK: - LogsTextViewRepresentable
public struct LogsTextViewRepresentable: NSViewRepresentable {
    public let text: String
    public let autoScroll: Bool

    public init(text: String, autoScroll: Bool = true) {
        self.text = text
        self.autoScroll = autoScroll
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 2/255.0, green: 6/255.0, blue: 23/255.0, alpha: 1.0)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(red: 2/255.0, green: 6/255.0, blue: 23/255.0, alpha: 1.0)
        textView.textColor = NSColor(red: 226/255.0, green: 232/255.0, blue: 240/255.0, alpha: 1.0) // Slate-200
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            if autoScroll {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
}

// MARK: - LogsView
public struct LogsView: View {
    @EnvironmentObject public var appState: AppState

    @State private var selectedTab: LogTypeTab = .nginxError
    @State private var selectedPHPVersion: String = "83"
    @State private var logContent: String = ""
    @State private var filterQuery: String = ""
    @State private var isAutoTailEnabled: Bool = true
    @State private var isLogUnreadable: Bool = false
    @State private var logFileSize: String = "0 B"
    @State private var feedbackMessage: String? = nil
    @State private var timerSubscription: Timer? = nil

    public init() {}

    private var activeLogPath: String {
        switch selectedTab {
        case .nginxError:
            return "/opt/local/var/log/nginx/error.log"
        case .nginxAccess:
            return "/opt/local/var/log/nginx/access.log"
        case .phpFpm:
            return "/opt/local/var/log/php\(selectedPHPVersion)/php-fpm.log"
        case .mariaDB:
            // Check known candidate paths
            let hostName = ProcessInfo.processInfo.hostName
            let candidates = [
                "/opt/local/var/log/mariadb-10.11/mariadb.err",
                "/opt/local/var/db/mariadb-10.11/\(hostName).err",
                "/opt/local/var/log/mariadb/error.log",
                "/opt/local/var/db/mariadb-10.11/error.log"
            ]
            for path in candidates {
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
            return "/opt/local/var/log/mariadb-10.11/mariadb.err"
        }
    }

    private var filteredLogText: String {
        guard !filterQuery.isEmpty else { return logContent }
        let lines = logContent.components(separatedBy: .newlines)
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterQuery) }
        return filtered.joined(separator: "\n")
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar & Sub-Tabs
            topControlsBar

            Divider()

            // 1-Click Stack Doctor Permission Banner if unreadable
            if isLogUnreadable {
                unreadablePermissionBanner
            }

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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
            }

            // Log Text Viewer Area
            ZStack(alignment: .bottomTrailing) {
                if logContent.isEmpty && !isLogUnreadable {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Log file is empty or does not exist yet at:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(activeLogPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor(red: 2/255.0, green: 6/255.0, blue: 23/255.0, alpha: 1.0)))
                } else {
                    LogsTextViewRepresentable(
                        text: filteredLogText,
                        autoScroll: isAutoTailEnabled
                    )
                }

                // Floating Info Badge
                HStack(spacing: 8) {
                    if isAutoTailEnabled {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Live Tail Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text(logFileSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.75))
                .cornerRadius(4)
                .padding(12)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            reloadLog()
            startAutoTailTimer()
        }
        .onDisappear {
            stopAutoTailTimer()
        }
        .onChange(of: selectedTab) { _ in
            reloadLog()
        }
        .onChange(of: selectedPHPVersion) { _ in
            reloadLog()
        }
    }

    // MARK: - Top Controls Bar
    private var topControlsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Sub-tabs
                Picker("", selection: $selectedTab) {
                    ForEach(LogTypeTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)

                // PHP Version Selector if PHP-FPM tab
                if selectedTab == .phpFpm {
                    Picker("Version:", selection: $selectedPHPVersion) {
                        Text("PHP 8.1").tag("81")
                        Text("PHP 8.2").tag("82")
                        Text("PHP 8.3").tag("83")
                        Text("PHP 8.4").tag("84")
                        Text("PHP 8.5").tag("85")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 120)
                }

                Spacer()

                // Actions: Auto-tail toggle, Refresh, Clear, Copy
                Toggle(isOn: $isAutoTailEnabled) {
                    Text("Auto-Tail")
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                Button(action: {
                    reloadLog()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh log file")

                Button(action: {
                    clearLogFile()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Truncate this log file")

                Button(action: {
                    copyToClipboard()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy log contents to clipboard")
            }

            // Path & Filter Row
            HStack(spacing: 10) {
                Text(activeLogPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Filter log output...", text: $filterQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 180)
                    if !filterQuery.isEmpty {
                        Button(action: { filterQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Unreadable Permission Banner (Stack Doctor 1-Click)
    private var unreadablePermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18))
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Log Read Permission Restricted")
                    .font(.system(size: 12, weight: .bold))
                Text("This file is owned by root or restricted by default (0600) and cannot be read by current user '\(NSUserName())'.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                Task {
                    await appState.runDoctorAutoFix()
                    reloadLog()
                    feedbackMessage = "Permissions repaired via Stack Doctor."
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "lock.open.fill")
                    Text("🔓 Perbaiki Izin Baca Log (Stack Doctor)")
                }
                .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.yellow.opacity(0.3)),
            alignment: .bottom
        )
    }

    // MARK: - Log Operations
    private func reloadLog() {
        let path = activeLogPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            self.logContent = ""
            self.isLogUnreadable = false
            self.logFileSize = "0 B"
            return
        }

        // Check readability
        guard fm.isReadableFile(atPath: path) else {
            self.isLogUnreadable = true
            self.logContent = ""
            self.logFileSize = "Restricted"
            return
        }

        self.isLogUnreadable = false

        // Fetch file size
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            self.logFileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        // Read last 250 KB if file is very large
        let maxBytesToRead: UInt64 = 250 * 1024
        if let fileHandle = FileHandle(forReadingAtPath: path) {
            defer { try? fileHandle.close() }
            let fileSize = fileHandle.seekToEndOfFile()
            if fileSize > maxBytesToRead {
                fileHandle.seek(toFileOffset: fileSize - maxBytesToRead)
            } else {
                fileHandle.seek(toFileOffset: 0)
            }
            let data = fileHandle.readDataToEndOfFile()
            self.logContent = String(decoding: data, as: UTF8.self)
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.logContent = String(decoding: data, as: UTF8.self)
        }
    }

    private func clearLogFile() {
        let path = activeLogPath
        Task {
            _ = await appState.commandRunner.runShell("echo -n '' > '\(path)' 2>/dev/null || sudo -n sh -c '> \"\(path)\"'", label: "clear-\(selectedTab.rawValue)")
            reloadLog()
            feedbackMessage = "Cleared \(selectedTab.rawValue)."
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filteredLogText, forType: .string)
        feedbackMessage = "Copied \(selectedTab.rawValue) to clipboard."
    }

    private func startAutoTailTimer() {
        stopAutoTailTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if isAutoTailEnabled {
                reloadLog()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        timerSubscription = timer
    }

    private func stopAutoTailTimer() {
        timerSubscription?.invalidate()
        timerSubscription = nil
    }
}
