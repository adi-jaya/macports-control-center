import SwiftUI
import AppKit

// MARK: - Notifications
public extension Notification.Name {
    static let mpccMainWindowDidClose = Notification.Name("mpccMainWindowDidClose")
}

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

// MARK: - LogFileTailer
@MainActor
public final class LogFileTailer: ObservableObject {
    @Published public var logContent: String = ""
    @Published public var displayedLogText: String = ""
    @Published public var isLogUnreadable: Bool = false
    @Published public var logFileSize: String = "0 B"
    @Published public var isAutoTailEnabled: Bool = true {
        didSet {
            if isAutoTailEnabled != oldValue {
                if isAutoTailEnabled {
                    attachWatcher()
                } else {
                    stopSourceOnly()
                    stopMissingFileTimer()
                }
            }
        }
    }

    private var activePath: String = ""
    private var filterQuery: String = ""
    private var filterTask: Task<Void, Never>? = nil
    private var lastInode: UInt64 = 0
    private var lastSize: UInt64 = 0
    private var lastModDate: Date = .distantPast

    private var fileSource: DispatchSourceFileSystemObject? = nil
    private var watchedFD: Int32 = -1
    private var missingFileTimer: Timer? = nil
    private var windowCloseObserver: NSObjectProtocol? = nil

    public init() {
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: .mpccMainWindowDidClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopWatching()
            }
        }
    }

    deinit {
        if let obs = windowCloseObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    public static func readTail(atPath path: String, maxBytes: UInt64 = 250 * 1024) -> (content: String, fileSize: Int64, isUnreadable: Bool, exists: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return ("", 0, false, false)
        }
        guard fm.isReadableFile(atPath: path) else {
            return ("", 0, true, true)
        }

        let fileSize = (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0

        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let content = String(decoding: data, as: UTF8.self)
                return (content, fileSize, false, true)
            }
            return ("", fileSize, true, true)
        }
        defer { try? fileHandle.close() }

        let totalSize = UInt64(max(0, fileSize))
        let seekOffset: UInt64
        if totalSize > maxBytes {
            seekOffset = totalSize - maxBytes
        } else {
            seekOffset = 0
        }

        fileHandle.seek(toFileOffset: seekOffset)
        var data = fileHandle.readDataToEndOfFile()

        if seekOffset > 0, let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data.suffix(from: data.index(after: nl))
        }

        let content = String(decoding: data, as: UTF8.self)
        return (content, fileSize, false, true)
    }

    public func startWatching(path: String) {
        if self.activePath != path {
            stopWatching()
            self.activePath = path
            self.lastInode = 0
            self.lastSize = 0
            self.lastModDate = .distantPast
        }

        reloadLog(force: true)

        guard isAutoTailEnabled else { return }
        attachWatcher()
    }

    public func stopWatching() {
        stopSourceOnly()
        stopMissingFileTimer()
        filterTask?.cancel()
        filterTask = nil
    }

    public func reloadLog(force: Bool = false) {
        let path = activePath
        guard !path.isEmpty else {
            self.logContent = ""
            self.displayedLogText = ""
            self.isLogUnreadable = false
            self.logFileSize = "0 B"
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            self.lastInode = 0
            self.lastSize = 0
            self.lastModDate = .distantPast
            self.logContent = ""
            self.displayedLogText = ""
            self.isLogUnreadable = false
            self.logFileSize = "0 B"
            return
        }

        guard fm.isReadableFile(atPath: path) else {
            self.lastInode = 0
            self.lastSize = 0
            self.lastModDate = .distantPast
            self.logContent = ""
            self.displayedLogText = ""
            self.isLogUnreadable = true
            self.logFileSize = "Restricted"
            return
        }

        self.isLogUnreadable = false

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date) ?? .distantPast

            if !force && inode == lastInode && size == lastSize && mtime == lastModDate {
                return
            }

            self.lastInode = inode
            self.lastSize = size
            self.lastModDate = mtime
        }

        let tail = Self.readTail(atPath: path)
        if tail.isUnreadable {
            self.isLogUnreadable = true
            self.logContent = ""
            self.displayedLogText = ""
            self.logFileSize = "Restricted"
            return
        }

        self.isLogUnreadable = false
        self.logContent = tail.content
        self.logFileSize = ByteCountFormatter.string(fromByteCount: tail.fileSize, countStyle: .file)
        self.applyFilter()
    }

    public func setFilterQuery(_ query: String) {
        self.filterQuery = query
        filterTask?.cancel()
        if query.isEmpty {
            self.displayedLogText = self.logContent
            return
        }
        filterTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.applyFilter()
        }
    }

    public func setAutoTailEnabled(_ enabled: Bool) {
        self.isAutoTailEnabled = enabled
    }

    private func applyFilter() {
        guard !filterQuery.isEmpty else {
            self.displayedLogText = logContent
            return
        }
        let lines = logContent.components(separatedBy: .newlines)
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterQuery) }
        self.displayedLogText = filtered.joined(separator: "\n")
    }

    private func attachWatcher() {
        stopSourceOnly()
        guard isAutoTailEnabled, !activePath.isEmpty else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: activePath), fm.isReadableFile(atPath: activePath) else {
            startMissingFileTimer()
            return
        }

        stopMissingFileTimer()

        let fd = open(activePath, O_EVTONLY)
        guard fd >= 0 else {
            startMissingFileTimer()
            return
        }

        self.watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.extend, .write, .attrib, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.reloadLog(force: true)
                self.attachWatcher()
            } else {
                self.reloadLog(force: false)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.fileSource = source
        source.resume()
    }

    private func stopSourceOnly() {
        if let source = fileSource {
            fileSource = nil
            source.cancel()
            watchedFD = -1
        } else if watchedFD >= 0 {
            close(watchedFD)
            watchedFD = -1
        }
    }

    private func startMissingFileTimer() {
        guard missingFileTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let fm = FileManager.default
                if fm.fileExists(atPath: self.activePath) && fm.isReadableFile(atPath: self.activePath) {
                    self.reloadLog(force: true)
                    self.attachWatcher()
                }
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        self.missingFileTimer = timer
    }

    private func stopMissingFileTimer() {
        missingFileTimer?.invalidate()
        missingFileTimer = nil
    }
}

// MARK: - LogsView
public struct LogsView: View {
    @EnvironmentObject public var appState: AppState

    @StateObject private var tailer = LogFileTailer()
    @State private var selectedTab: LogTypeTab = .nginxError
    @State private var selectedPHPVersion: String = "83"
    @State private var filterQuery: String = ""
    @State private var feedbackMessage: String? = nil
    @State private var cachedMariaDBPath: String = ""

    public init() {}

    private func resolveMariaDBPath() -> String {
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

    private var activeLogPath: String {
        switch selectedTab {
        case .nginxError:
            return "/opt/local/var/log/nginx/error.log"
        case .nginxAccess:
            return "/opt/local/var/log/nginx/access.log"
        case .phpFpm:
            return "/opt/local/var/log/php\(selectedPHPVersion)/php-fpm.log"
        case .mariaDB:
            return cachedMariaDBPath.isEmpty ? "/opt/local/var/log/mariadb-10.11/mariadb.err" : cachedMariaDBPath
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar & Sub-Tabs
            topControlsBar

            Divider()

            // 1-Click Stack Doctor Permission Banner if unreadable
            if tailer.isLogUnreadable {
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
                if tailer.logContent.isEmpty && !tailer.isLogUnreadable {
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
                        text: tailer.displayedLogText,
                        autoScroll: tailer.isAutoTailEnabled
                    )
                }

                // Floating Info Badge
                HStack(spacing: 8) {
                    if tailer.isAutoTailEnabled {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Live Tail Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text(tailer.logFileSize)
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
            if selectedTab == .mariaDB {
                cachedMariaDBPath = resolveMariaDBPath()
            }
            tailer.startWatching(path: activeLogPath)
        }
        .onDisappear {
            tailer.stopWatching()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .mariaDB {
                cachedMariaDBPath = resolveMariaDBPath()
            }
            tailer.startWatching(path: activeLogPath)
        }
        .onChange(of: selectedPHPVersion) { _ in
            tailer.startWatching(path: activeLogPath)
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
                Toggle(isOn: $tailer.isAutoTailEnabled) {
                    Text("Auto-Tail")
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                Button(action: {
                    tailer.reloadLog(force: true)
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
                        .onChange(of: filterQuery) { query in
                            tailer.setFilterQuery(query)
                        }
                    if !filterQuery.isEmpty {
                        Button(action: {
                            filterQuery = ""
                            tailer.setFilterQuery("")
                        }) {
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
                    tailer.reloadLog(force: true)
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
    private func clearLogFile() {
        let path = activeLogPath
        Task {
            _ = await appState.commandRunner.runShell("echo -n '' > '\(path)' 2>/dev/null || sudo -n sh -c '> \"\(path)\"'", label: "clear-\(selectedTab.rawValue)")
            tailer.reloadLog(force: true)
            feedbackMessage = "Cleared \(selectedTab.rawValue)."
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tailer.displayedLogText, forType: .string)
        feedbackMessage = "Copied \(selectedTab.rawValue) to clipboard."
    }
}
