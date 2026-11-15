# Cloudflare Quick Tunneling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build 1-click Cloudflare Quick Tunneling into MacPorts Control Center to expose Nginx Virtual Hosts and ad-hoc dev ports (Vite 5173, Next.js 3000) to temporary public HTTPS URLs (`https://*.trycloudflare.com`).

**Architecture:** A dual-tier UX integrates in-context tunnel controls directly on Nginx vhost cards in `SitesView` alongside a new dedicated `TunnelsView` control hub in the main sidebar. A non-blocking asynchronous process supervisor (`TunnelService`) runs user-space `cloudflared` instances, parses `stderr` streams with regex, manages multi-tunnel lifecycles, and synchronizes status through `AppState.activeTunnels`.

**Tech Stack:** Swift 5.6+ (SwiftUI + AppKit), macOS Monterey 12.0+ SDK (`x86_64` & `arm64`), MacPorts `cloudflared` binary, zero external CocoaPods/SPM dependencies.

**Spec:** [`docs/superpowers/specs/2026-11-15-cloudflared-quick-tunneling-design.md`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/docs/superpowers/specs/2026-11-15-cloudflared-quick-tunneling-design.md)

## Global Constraints

- **Platform Target:** macOS Monterey 12.0+ (`x86_64` Intel & `arm64` Apple Silicon).
- **Zero Third-Party Dependency:** Native Swift, SwiftUI, and AppKit only.
- **Unprivileged Execution:** Run `cloudflared tunnel` as normal user (`adijaya`); never with `sudo`.
- **Target Boundary:** Proxy targets strictly locked to `http://127.0.0.1:<port>` or `https://127.0.0.1:<port>`.
- **No Blocking UI:** All process I/O and log streaming must occur on background threads / async handlers.
- **Graceful Termination:** All spawned `cloudflared` processes must be terminated on `applicationWillTerminate`.

## Review Focus

1. **Non-standard binary location:** `cloudflared` installed in `~/.local/bin/cloudflared` or `/usr/local/bin` rather than `/opt/local/bin/cloudflared`. Must resolve binary through multi-path fallback and `PATH`.
2. **Vite 5+ host header rejection:** Frontend dev servers like Vite 5 enforce strict Host header checks and reject external domains with 403 Forbidden. Must supply `--http-host-header localhost` (or vhost serverName).
3. **Local SSL / HTTPS VHosts:** When proxying to an HTTPS vhost (`sslEnabled: true`), must proxy to `https://127.0.0.1:<port>` with `--no-tls-verify` to avoid HTTP 400 Bad Request.
4. **Unexpected process termination:** If `cloudflared` exits prematurely due to network disconnect or port in use, status must transition to `.error` with `errorMessage` and remove stale process references.
5. **App termination cleanup:** When quitting the app, `stopAllTunnels()` must kill all active child processes to prevent background orphan processes.

---

### Task 1: Domain Models & Navigation Expansion

**Files:**
- Modify: `Sources/MacPortsControlCenter/Models/DomainModels.swift`
- Modify: `Sources/MacPortsControlCenter/Models/AppState.swift:5-40`
- Test: `Tests/MacPortsControlCenterTests/TunnelServiceTests.swift`

**Interfaces:**
- Consumes: Existing `DomainModels.swift` and `NavigationSection` enum.
- Produces:
  - `TunnelStatus` enum (`starting`, `active`, `stopped`, `error`).
  - `ActiveTunnel` struct (`id`, `port`, `label`, `publicUrl`, `status`, `errorMessage`, `startedAt`, `isVHost`, `isSSL`).
  - `NavigationSection.tunnels` (`id: "tunnels"`, `displayName: "Tunnels"`, `systemImage: "antenna.radiowaves.left.and.right"`).

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/MacPortsControlCenterTests/TunnelServiceTests.swift
final class TunnelServiceTests: XCTestCase {
    func testActiveTunnelModelInitializationAndCompositeID() {
        let tunnel = ActiveTunnel(port: "8081", label: "portal-berita.test", status: .starting, isVHost: true, isSSL: false)
        XCTAssertEqual(tunnel.id, "8081_portal-berita.test")
        XCTAssertEqual(tunnel.port, "8081")
        XCTAssertEqual(tunnel.status, .starting)
        XCTAssertTrue(tunnel.isVHost)
        XCTAssertFalse(tunnel.isSSL)
        XCTAssertNil(tunnel.publicUrl)
    }

    func testNavigationSectionIncludesTunnels() {
        let sections = NavigationSection.allCases
        XCTAssertTrue(sections.contains(.tunnels))
        XCTAssertEqual(NavigationSection.tunnels.displayName, "Tunnels")
        XCTAssertEqual(NavigationSection.tunnels.systemImage, "antenna.radiowaves.left.and.right")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")" && swiftc -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -parse-as-library Sources/MacPortsControlCenter/Models/*.swift Sources/MacPortsControlCenter/Services/*.swift Sources/MacPortsControlCenter/Views/*.swift Tests/MacPortsControlCenterTests/*.swift -lsqlite3 -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests`
Expected: FAIL with "type 'NavigationSection' has no member 'tunnels'" or "cannot find type 'ActiveTunnel'".

- [ ] **Step 3: Implement `ActiveTunnel`, `TunnelStatus`, and `NavigationSection.tunnels`**

1. In `Sources/MacPortsControlCenter/Models/DomainModels.swift`: Add `TunnelStatus` enum and `ActiveTunnel` struct with composite ID `\(port)_\(label.replacingOccurrences(of: " ", with: "_"))`.
2. In `Sources/MacPortsControlCenter/Models/AppState.swift`: Add `case tunnels = "tunnels"` to `NavigationSection`, with `displayName = "Tunnels"` and `systemImage = "antenna.radiowaves.left.and.right"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")" && swiftc -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -parse-as-library Sources/MacPortsControlCenter/Models/*.swift Sources/MacPortsControlCenter/Services/*.swift Sources/MacPortsControlCenter/Views/*.swift Tests/MacPortsControlCenterTests/*.swift -lsqlite3 -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacPortsControlCenter/Models/DomainModels.swift Sources/MacPortsControlCenter/Models/AppState.swift Tests/MacPortsControlCenterTests/TunnelServiceTests.swift
git commit -m "feat(tunnels): add ActiveTunnel model and NavigationSection.tunnels"
```

---

### Task 2: Tunnel Process Supervisor Service (`TunnelService.swift`)

**Files:**
- Create: `Sources/MacPortsControlCenter/Services/TunnelService.swift`
- Test: `Tests/MacPortsControlCenterTests/TunnelServiceTests.swift`

**Interfaces:**
- Consumes: `DomainModels.ActiveTunnel`, `DomainModels.TunnelStatus`.
- Produces:
  - `TunnelService.findBinaryPath() -> String?`
  - `TunnelService.isCloudflaredInstalled() -> Bool`
  - `TunnelService.extractTunnelURL(from: String) -> String?`
  - `TunnelService.buildProcessArguments(port: String, isSSL: Bool, hostHeader: String?) -> [String]`
  - `TunnelService.startTunnel(port:label:isVHost:isSSL:hostHeader:onUrlDiscovered:onError:onExit:) -> Process?`
  - `TunnelService.stopTunnel(tunnelId: String)`
  - `TunnelService.stopAllTunnels()`

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/MacPortsControlCenterTests/TunnelServiceTests.swift
func testExtractTunnelURLFromRealisticCloudflareLog() {
    let sampleLog = """
    2026-11-14T17:22:52Z INF Requesting new quick Tunnel on trycloudflare.com...
    2026-11-14T17:22:58Z INF +--------------------------------------------------------------------------------------------+
    2026-11-14T17:22:58Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
    2026-11-14T17:22:58Z INF |  https://pump-trading-tiny-opposition.trycloudflare.com                                    |
    2026-11-14T17:22:58Z INF +--------------------------------------------------------------------------------------------+
    """
    let extracted = TunnelService.extractTunnelURL(from: sampleLog)
    XCTAssertEqual(extracted, "https://pump-trading-tiny-opposition.trycloudflare.com")
}

func testBuildProcessArgumentsForHTTPAndViteHostHeader() {
    let args = TunnelService.buildProcessArguments(port: "5173", isSSL: false, hostHeader: "localhost")
    XCTAssertEqual(args, [
        "tunnel",
        "--url", "http://127.0.0.1:5173",
        "--no-autoupdate",
        "--http-host-header", "localhost"
    ])
}

func testBuildProcessArgumentsForHTTPSVHostWithNoTLSVerify() {
    let args = TunnelService.buildProcessArguments(port: "8082", isSSL: true, hostHeader: "my-secure.test")
    XCTAssertEqual(args, [
        "tunnel",
        "--url", "https://127.0.0.1:8082",
        "--no-autoupdate",
        "--no-tls-verify",
        "--http-host-header", "my-secure.test"
    ])
}

func testBinaryDiscoveryChecksMultipleLocations() {
    let path = TunnelService.findBinaryPath()
    XCTAssertNotNil(path)
    XCTAssertTrue(path?.contains("cloudflared") == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: FAIL with "cannot find 'TunnelService' in scope".

- [ ] **Step 3: Implement `TunnelService.swift`**

Create `Sources/MacPortsControlCenter/Services/TunnelService.swift`:
1. `findBinaryPath()`: Checks `/opt/local/bin/cloudflared`, `~/.local/bin/cloudflared`, `/usr/local/bin/cloudflared`, or resolves via `which cloudflared`.
2. `extractTunnelURL(from:)`: Regex match for `https://[a-zA-Z0-9-]+\\.trycloudflare\\.com`.
3. `buildProcessArguments(port:isSSL:hostHeader:)`: Construct CLI arguments with `--url`, `--no-autoupdate`, `--no-tls-verify` (if `isSSL`), and `--http-host-header` (if provided).
4. `startTunnel(...)`: Spawns `Process`, captures `stderr` via `readabilityHandler`, calls `onUrlDiscovered` on first match, registers termination handler for `onExit`.
5. `stopTunnel(tunnelId:)` & `stopAllTunnels()`: Calls `process.terminate()` and clears internal dictionary.

- [ ] **Step 4: Run test to verify it passes**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacPortsControlCenter/Services/TunnelService.swift Tests/MacPortsControlCenterTests/TunnelServiceTests.swift
git commit -m "feat(tunnels): implement TunnelService process supervisor and CLI builder"
```

---

### Task 3: AppState State Management & App Termination Lifecycle

**Files:**
- Modify: `Sources/MacPortsControlCenter/Models/AppState.swift`
- Modify: `Sources/MacPortsControlCenterApp/MainApp.swift`
- Test: `Tests/MacPortsControlCenterTests/TunnelServiceTests.swift`

**Interfaces:**
- Consumes: `TunnelService`, `ActiveTunnel`, `DomainModels.VHostItem`.
- Produces:
  - `@Published public var activeTunnels: [String: ActiveTunnel] = [:]` (key: `tunnelId`)
  - `@Published public var isCloudflaredInstalled: Bool`
  - `appState.checkCloudflaredInstallation()`
  - `appState.startTunnel(port:label:isVHost:isSSL:hostHeader:) async`
  - `appState.startTunnel(for: VHostItem) async`
  - `appState.stopTunnel(tunnelId: String)`
  - `appState.stopAllTunnels()`
  - `appState.installCloudflared() async`
  - `MainApp.applicationWillTerminate` calls `appState.stopAllTunnels()`.

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/MacPortsControlCenterTests/TunnelServiceTests.swift
func testAppStateTunnelLifecycleMethods() async {
    let appState = AppState()
    appState.checkCloudflaredInstallation()
    XCTAssertTrue(appState.isCloudflaredInstalled)

    let testId = "9999_test-unit"
    appState.activeTunnels[testId] = ActiveTunnel(port: "9999", label: "test-unit", status: .active)
    XCTAssertEqual(appState.activeTunnels.count, 1)

    appState.stopTunnel(tunnelId: testId)
    XCTAssertNil(appState.activeTunnels[testId])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: FAIL with "value of type 'AppState' has no member 'activeTunnels'".

- [ ] **Step 3: Implement AppState tunnel methods and MainApp hook**

1. In `AppState.swift`:
   - Add `public let tunnelService = TunnelService()`.
   - Add `@Published public var activeTunnels: [String: ActiveTunnel] = [:]`.
   - Add `@Published public var isCloudflaredInstalled: Bool = false`.
   - Implement `checkCloudflaredInstallation()`.
   - Implement `startTunnel(port:label:isVHost:isSSL:hostHeader:)` and `startTunnel(for vhost: VHostItem)`.
   - Implement `stopTunnel(tunnelId:)` and `stopAllTunnels()`.
   - Implement `installCloudflared() async` executing `sudo port install cloudflared` via CommandRunner.
2. In `Sources/MacPortsControlCenterApp/MainApp.swift`:
   - In `AppDelegate.applicationWillTerminate`: call `appState.stopAllTunnels()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacPortsControlCenter/Models/AppState.swift Sources/MacPortsControlCenterApp/MainApp.swift Tests/MacPortsControlCenterTests/TunnelServiceTests.swift
git commit -m "feat(tunnels): wire TunnelService into AppState and application termination hook"
```

---

### Task 4: In-Context Tunnel Actions & Custom Port Sheet in `SitesView`

**Files:**
- Modify: `Sources/MacPortsControlCenter/Views/SitesView.swift`

**Interfaces:**
- Consumes: `appState.activeTunnels`, `appState.startTunnel(for:)`, `appState.stopTunnel(tunnelId:)`, `appState.startTunnel(port:label:isVHost:isSSL:hostHeader:)`.
- Produces:
  - Header button `[ ⚡ Tunnel Custom Port ]` opening `QuickTunnelPortSheet`.
  - In `vhostCard`: Action button `[ ⚡ Tunnel ]` when inactive, and active tunnel banner when live:
    - Status: `● Live Tunnel`
    - Public URL display
    - Buttons: `Copy URL` (with copied feedback), `Open Browser`, `Stop Tunnel`.

- [ ] **Step 1: Write UI component sheet & update `SitesView.swift`**

1. Create `struct QuickTunnelPortSheet: View` at bottom of `SitesView.swift`:
   - Input: Port (text field, digits only)
   - Input: Label (optional, default "Custom Dev Server")
   - Action: "Start Tunnel" button calling `appState.startTunnel(...)`.
2. In `SitesView.headerSection`: Add `Button` `[ ⚡ Tunnel Port... ]` next to `New Virtual Host`.
3. In `vhostCard(_ vhost: VHostItem)`:
   - Calculate `let tunnelId = "\(vhost.listenPort)_\(vhost.fileName.replacingOccurrences(of: " ", with: "_"))"`.
   - If `let activeTunnel = appState.activeTunnels[tunnelId]`, display live banner above action bar:
     - URL monospaced text.
     - `[ 📋 Copy URL ]` copying to `NSPasteboard.general`.
     - `[ 🌐 Open Browser ]` opening URL via `NSWorkspace.shared.open`.
     - `[ ⏹ Stop ]` calling `appState.stopTunnel(tunnelId: tunnelId)`.
   - If no tunnel running: In bottom actions bar, add `Button` `[ ⚡ Tunnel ]` calling `Task { await appState.startTunnel(for: vhost) }`.

- [ ] **Step 2: Verify compilation and tests**

Run: `SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")" && swiftc -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -parse-as-library Sources/MacPortsControlCenter/Models/*.swift Sources/MacPortsControlCenter/Services/*.swift Sources/MacPortsControlCenter/Views/*.swift Tests/MacPortsControlCenterTests/*.swift -lsqlite3 -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS with 0 compilation errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/MacPortsControlCenter/Views/SitesView.swift
git commit -m "feat(sites): add in-context tunnel controls and QuickTunnelPortSheet"
```

---

### Task 5: Dedicated Tunnels Hub (`TunnelsView.swift`) & Sidebar Integration

**Files:**
- Create: `Sources/MacPortsControlCenter/Views/TunnelsView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/MainWindowView.swift`

**Interfaces:**
- Consumes: `appState.activeTunnels`, `appState.isCloudflaredInstalled`, `appState.startTunnel`, `appState.stopTunnel`, `appState.stopAllTunnels`.
- Produces:
  - `TunnelsView` view.
  - `MainWindowView` routing for `NavigationSection.tunnels -> TunnelsView()`.
  - Active tunnel count badge in sidebar item `Tunnels`.

- [ ] **Step 1: Create `TunnelsView.swift`**

Create `Sources/MacPortsControlCenter/Views/TunnelsView.swift`:
1. **Header Section:** Title "Tunnels Hub", subtitle "Expose local ports to the internet via Cloudflare Quick Tunnel", and button `[ ⏹ Stop All Tunnels ]` (disabled if `activeTunnels.isEmpty`).
2. **Expose New Port Card:**
   - Input Port (`@State private var customPort: String = ""`)
   - Input Label (`@State private var customLabel: String = ""`)
   - Preset chips: `3000: Next.js`, `5173: Vite`, `8000: FastAPI`, `8080: HTTP Alt`. Clicking a chip sets `customPort` and `customLabel`.
   - Button `[ ⚡ Start Tunnel ]` (disabled if `customPort` is empty).
3. **Active Tunnels List:**
   - For each tunnel in `appState.activeTunnels.values`:
     - Badge target `localhost:<port>` + label
     - Status: `● Live` or spinner `Starting...`
     - Public URL text (monospaced)
     - Action buttons: `Copy URL`, `Open Browser`, `Stop Tunnel`.
4. **Empty State:** If `activeTunnels.isEmpty`, display a clean card explaining how quick tunneling works and inviting the user to start one.

- [ ] **Step 2: Update `MainWindowView.swift`**

1. In `contentArea`: Add `case .tunnels: TunnelsView().environmentObject(appState)`.
2. In `SectionPlaceholderView`: Add `case .tunnels: Text("\(appState.activeTunnels.count) active tunnels")`.
3. In `sidebarView`: In the `ForEach(NavigationSection.allCases)` loop, if `section == .tunnels && !appState.activeTunnels.isEmpty`: display a small green pill badge with `\(appState.activeTunnels.filter { $0.value.status == .active }.count)`.

- [ ] **Step 3: Verify compilation and tests**

Run: `SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")" && swiftc -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -parse-as-library Sources/MacPortsControlCenter/Models/*.swift Sources/MacPortsControlCenter/Services/*.swift Sources/MacPortsControlCenter/Views/*.swift Tests/MacPortsControlCenterTests/*.swift -lsqlite3 -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS with 0 compilation errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacPortsControlCenter/Views/TunnelsView.swift Sources/MacPortsControlCenter/Views/MainWindowView.swift
git commit -m "feat(views): create TunnelsView hub and integrate into main navigation shell"
```

---

### Task 6: Test Suite Registration, Runner Verification & Release Packaging

**Files:**
- Modify: `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`

**Interfaces:**
- Consumes: All tests in `TunnelServiceTests.swift`.
- Produces: Complete passing test runner suite, release application bundle `build/MacPorts Control Center.app`.

- [ ] **Step 1: Register `TunnelServiceTests` in `TestRunnerMain.swift`**

In `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`, append execution block:
```swift
print("Running TunnelServiceTests...")
let tunnelTests = TunnelServiceTests()
tunnelTests.setUp()
tunnelTests.testActiveTunnelModelInitializationAndCompositeID()
tunnelTests.tearDown()

tunnelTests.setUp()
tunnelTests.testNavigationSectionIncludesTunnels()
tunnelTests.tearDown()

tunnelTests.setUp()
tunnelTests.testExtractTunnelURLFromRealisticCloudflareLog()
tunnelTests.tearDown()

tunnelTests.setUp()
tunnelTests.testBuildProcessArgumentsForHTTPAndViteHostHeader()
tunnelTests.tearDown()

tunnelTests.setUp()
tunnelTests.testBuildProcessArgumentsForHTTPSVHostWithNoTLSVerify()
tunnelTests.tearDown()

tunnelTests.setUp()
tunnelTests.testBinaryDiscoveryChecksMultipleLocations()
tunnelTests.tearDown()

tunnelTests.setUp()
await tunnelTests.testAppStateTunnelLifecycleMethods()
tunnelTests.tearDown()
print("All TunnelServiceTests passed successfully (7/7 tests)")
```

- [ ] **Step 2: Run full test suite**

Run:
```bash
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")" && swiftc -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -parse-as-library Sources/MacPortsControlCenter/Models/*.swift Sources/MacPortsControlCenter/Services/*.swift Sources/MacPortsControlCenter/Views/*.swift Tests/MacPortsControlCenterTests/*.swift -lsqlite3 -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests
```
Expected: All 64/64 tests pass with exit code 0.

- [ ] **Step 3: Build release app bundle**

Run:
```bash
./build-app.sh
```
Expected: `build/MacPorts Control Center.app` built successfully with valid ad-hoc codesign and size ~4.2 MB.

- [ ] **Step 4: Commit**

```bash
git add Tests/MacPortsControlCenterTests/TestRunnerMain.swift
git commit -m "chore(tests): register TunnelServiceTests and verify build bundle"
```
