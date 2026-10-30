import SwiftUI
import AppKit
import Combine

#if canImport(MacPortsControlCenter)
import MacPortsControlCenter
#endif

// MARK: - Menu Bar Controller
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let appState: AppState
    private let onOpenControlCenter: () -> Void
    private var cancellables = Set<AnyCancellable>()

    public init(appState: AppState, onOpenControlCenter: @escaping () -> Void) {
        self.appState = appState
        self.onOpenControlCenter = onOpenControlCenter
        super.init()

        setupStatusItem()
        observeAppState()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = " MP"
            button.imagePosition = .imageLeft
            button.toolTip = "MacPorts Control Center"
            button.image = statusImages[.stopped]
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        applyStatusIndicator(currentStatus)
    }

    private func observeAppState() {
        Publishers.CombineLatest3(appState.$services, appState.$isLoading, appState.commandRunner.$isRunning)
            .map { services, isLoading, isRunning -> StackStatus in
                Self.computeStatus(services: services, isLoading: isLoading, isRunning: isRunning)
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.applyStatusIndicator(status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Status Computation
    public enum StackStatus: String, CaseIterable, Equatable, Hashable {
        case running
        case degraded
        case stopped
        case updating

        public var color: NSColor {
            switch self {
            case .running: return .systemGreen
            case .degraded: return .systemYellow
            case .stopped: return .systemRed
            case .updating: return .systemOrange
            }
        }

        public var displayText: String {
            switch self {
            case .running: return "Running"
            case .degraded: return "Degraded"
            case .stopped: return "Stopped"
            case .updating: return "Updating..."
            }
        }
    }

    private lazy var statusImages: [StackStatus: NSImage] = {
        var dict: [StackStatus: NSImage] = [:]
        for status in StackStatus.allCases {
            dict[status] = Self.makeStatusIndicatorImage(color: status.color)
        }
        return dict
    }()

    public static func computeStatus(services: [ServiceItem], isLoading: Bool, isRunning: Bool) -> StackStatus {
        if isLoading || isRunning {
            return .updating
        }

        let isNginxRunning = services.first(where: { $0.name == "nginx" })?.isRunning ?? false
        let isPHPRunning = services.contains(where: { $0.name.contains("php") && $0.name.contains("fpm") && $0.isRunning })
        let isDBRunning = services.contains(where: { ($0.name.contains("mariadb") || $0.name.contains("mysql")) && $0.isRunning })

        if isNginxRunning && isPHPRunning && isDBRunning {
            return .running
        } else if isNginxRunning || isPHPRunning || isDBRunning {
            return .degraded
        } else {
            return .stopped
        }
    }

    public var currentStatus: StackStatus {
        Self.computeStatus(
            services: appState.services,
            isLoading: appState.isLoading,
            isRunning: appState.commandRunner.isRunning
        )
    }

    private func applyStatusIndicator(_ status: StackStatus) {
        statusItem.button?.image = statusImages[status] ?? Self.makeStatusIndicatorImage(color: status.color)
        statusItem.button?.toolTip = "MacPorts Control Center — Web Stack: \(status.displayText)"
    }

    private static func makeStatusIndicatorImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { _ in
            let circleRect = NSRect(x: 1, y: 1, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: circleRect)
            color.setFill()
            path.fill()

            NSColor.white.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.8
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - NSMenuDelegate
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = currentStatus

        // 1. Status Summary Header
        let summaryItem = NSMenuItem(title: "Web Stack: \(status.displayText)", action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        summaryItem.image = statusImages[status] ?? Self.makeStatusIndicatorImage(color: status.color)
        menu.addItem(summaryItem)

        // Active Components Subtitle
        let activePHP = appState.phpVersions.first(where: \.isCLIDefault)?.version ?? "8.3"
        let activeDB = appState.services.first(where: { ($0.name.contains("mariadb") || $0.name.contains("mysql")) && $0.isRunning })?.name ?? "MariaDB 10.11"
        let detailItem = NSMenuItem(title: "PHP \(activePHP) | \(activeDB)", action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        menu.addItem(detailItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Open Control Center
        let openItem = NSMenuItem(title: "Open Control Center", action: #selector(handleOpenControlCenter), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Quick Actions
        let startItem = NSMenuItem(title: "Start Services", action: #selector(handleStartServices), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        let restartItem = NSMenuItem(title: "Restart Web Stack", action: #selector(handleRestartWebStack), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        let stopItem = NSMenuItem(title: "Stop Services", action: #selector(handleStopServices), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Quick Links
        let openLocalhostItem = NSMenuItem(title: "Open localhost:80", action: #selector(handleOpenLocalhost), keyEquivalent: "")
        openLocalhostItem.target = self
        menu.addItem(openLocalhostItem)

        let openServersItem = NSMenuItem(title: "Open Servers Folder (/opt/local/etc/nginx/servers)", action: #selector(handleOpenServersFolder), keyEquivalent: "")
        openServersItem.target = self
        menu.addItem(openServersItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit MacPorts Control Center", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions
    @objc private func handleOpenControlCenter() {
        onOpenControlCenter()
    }

    @objc private func handleStartServices() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.appState.startWebStack()
            if let db = self.appState.services.first(where: { ($0.name.contains("mariadb") || $0.name.contains("mysql")) && !$0.isRunning }) {
                _ = await self.appState.commandRunner.runShell("sudo -n /opt/local/bin/port load \(db.name)", label: "start-\(db.name)")
                await self.appState.refreshServices()
            }
        }
    }

    @objc private func handleRestartWebStack() {
        Task { [weak self] in
            await self?.appState.restartWebStack()
        }
    }

    @objc private func handleStopServices() {
        Task { [weak self] in
            await self?.appState.stopAllServices()
        }
    }

    @objc private func handleOpenLocalhost() {
        if let url = URL(string: "http://localhost:80") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleOpenServersFolder() {
        let path = "/opt/local/etc/nginx/servers"
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/opt/local/etc/nginx"))
        }
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Application Delegate
@main
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var sharedDelegate: AppDelegate?
    private var mainWindow: NSWindow?
    private var appState: AppState!
    private var menuBarController: MenuBarController?

    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        sharedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()

        let state = AppState()
        state.isTerminalDrawerExpanded = false
        self.appState = state

        self.menuBarController = MenuBarController(appState: state) { [weak self] in
            self?.showMainWindow()
        }

        createAndShowMainWindow()
    }

    private func createAndShowMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPorts Control Center"
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.setFrameAutosaveName("MacPortsControlCenterMainWindow")
        window.delegate = self
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(
            rootView: MainWindowView(appState: appState)
                .environmentObject(appState)
        )
        window.contentView = hostingView

        self.mainWindow = window
        showMainWindow()
    }

    public func showMainWindow() {
        guard let window = mainWindow else {
            createAndShowMainWindow()
            return
        }
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .mpccMainWindowDidClose, object: nil)
        sender.saveFrame(usingName: "MacPortsControlCenterMainWindow")
        sender.delegate = nil
        sender.contentView = nil
        sender.orderOut(nil)
        self.mainWindow = nil
        self.appState.purgeTransientCachesForBackground()
        // Keep NSApp.setActivationPolicy(.regular) so Dock icon stays visible!
        return false
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - System Main Menu
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "MacPorts Control Center")
        appMenu.addItem(withTitle: "About MacPorts Control Center", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide MacPorts Control Center", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit MacPorts Control Center", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let refreshItem = NSMenuItem(title: "Refresh All Services", action: #selector(handleRefreshAll), keyEquivalent: "r")
        refreshItem.target = self
        viewMenu.addItem(refreshItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 4. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func handleRefreshAll() {
        Task { [weak self] in
            await self?.appState.refreshAll()
        }
    }
}
