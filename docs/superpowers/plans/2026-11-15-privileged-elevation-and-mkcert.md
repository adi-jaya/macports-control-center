# Privileged Elevation & In-App mkcert Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `setupMkcert` and `setupDnsmasq` in MacPorts Control Center to execute privileged setup commands in-app via the native macOS authorization popup dialog (`osascript`), eliminating unwanted `Terminal.app` window popups and fixing passwordless copy errors.

**Architecture:** Add pure command builder functions to `DoctorService` that generate safe shell scripts executed under macOS root privilege elevation (`do shell script ... with administrator privileges`). Update `AppState` to call these builders and stream progress into the in-app Terminal Drawer, while keeping `openExternalTerminal` preserved in `CommandRunner` for manual or interactive use.

**Tech Stack:** Swift 5.6+, SwiftUI, AppKit, macOS Authorization Services (`/usr/bin/osascript`), POSIX Shell, MacPorts CLI.

**Spec:** `docs/superpowers/specs/2026-11-15-privileged-elevation-and-mkcert-design.md`

## Global Constraints

- Zero third-party dependencies; pure Swift & AppKit standard libraries.
- Must preserve user ownership (`currentUser:staff`) and path location (`~/Library/Application Support/mkcert`) for `mkcert` Root CA so user-generated virtual host certificates remain valid.
- `CommandRunner.openExternalTerminal(command:)` must remain available and untouched for manual user triggers in Terminal Drawer.
- All 73+ existing unit tests must remain passing with zero regressions.
- Target macOS compatibility: macOS 12 Monterey (Intel x86_64) and later.

## Review Focus

1. **User input sanitization:** Spaces or single quotes in user path or username must not break shell quoting in `DoctorService` builders.
2. **Cancellation handling:** If the user presses "Cancel" in the native `osascript` password dialog, the command runner must record the failure cleanly without crashing or hanging the app.
3. **Idempotency:** Running `setupMkcert` or `setupDnsmasq` multiple times must not append duplicate entries or corrupt existing configuration files.
4. **Permissions integrity:** Files generated inside `CAROOT` must belong to the active non-root user (`currentUser:staff`), never locked to `root:wheel`.
5. **Portability of binaries:** Use explicit paths `/opt/local/bin/mkcert` and `/usr/bin/osascript` with fallbacks where applicable.

---

### Task 1: Command Builders in `DoctorService` & Unit Tests

**Files:**
- Modify: `Sources/MacPortsControlCenter/Services/DoctorService.swift`
- Modify: `Tests/MacPortsControlCenterTests/DoctorAndDatabaseTests.swift`

**Interfaces:**
- Produces:
  ```swift
  DoctorService.buildMkcertInstallScript(
      currentUser: String,
      carootPath: String,
      mkcertBinary: String = "/opt/local/bin/mkcert"
  ) -> String

  DoctorService.buildDnsmasqPrivilegedSetupScript(
      dnsmasqConfPath: String = "/opt/local/etc/dnsmasq.conf",
      needsConfigAppend: Bool = true,
      appendConfig: String = "address=/.test/127.0.0.1\\nlisten-address=127.0.0.1",
      resolverDir: String = "/etc/resolver",
      resolverFile: String = "/etc/resolver/test",
      nameserverEntry: String = "nameserver 127.0.0.1"
  ) -> String
  ```

- [ ] **Step 1: Write failing unit tests in `DoctorAndDatabaseTests.swift`**

Add tests validating:
- `testBuildMkcertInstallScriptGeneratesValidPrivilegedScript`: Checks that script creates CAROOT directory, exports `CAROOT`, runs `mkcert -install`, and changes ownership to `$currentUser:staff`.
- `testBuildDnsmasqPrivilegedSetupScript`: Checks that script appends config when needed and populates `/etc/resolver/test`.

- [ ] **Step 2: Run test suite to verify tests fail**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: Compilation failure or missing symbol for new `DoctorService` builder methods.

- [ ] **Step 3: Implement builder methods in `DoctorService.swift`**

Implement `buildMkcertInstallScript` and `buildDnsmasqPrivilegedSetupScript` with shell quoting protection and explicit paths.

- [ ] **Step 4: Run test suite to verify tests pass**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS (all tests green).

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/MacPortsControlCenter/Services/DoctorService.swift Tests/MacPortsControlCenterTests/DoctorAndDatabaseTests.swift
git commit -m "feat(doctor): add privileged script builders for mkcert and dnsmasq"
```

---

### Task 2: Refactor `setupMkcert` & `setupDnsmasq` in `AppState`

**Files:**
- Modify: `Sources/MacPortsControlCenter/Models/AppState.swift:981-1002`
- Test: `Tests/MacPortsControlCenterTests/AppStateTests.swift`

**Interfaces:**
- Consumes:
  - `DoctorService.buildMkcertInstallScript(currentUser:carootPath:)`
  - `DoctorService.buildDnsmasqPrivilegedSetupScript(dnsmasqConfPath:needsConfigAppend:)`
  - `DoctorService.buildOsascriptAdminCommand(shellScript:)`
  - `commandRunner.run(executable:arguments:label:)`

- [ ] **Step 1: Check existing `AppStateTests.swift` test coverage**

Inspect and confirm whether mock command runners or utility tests touch `setupMkcert` or `setupDnsmasq`.

- [ ] **Step 2: Update `setupMkcert()` in `AppState.swift`**

Replace:
```swift
_ = await commandRunner.runShell("sudo -n /opt/local/bin/port install mkcert", label: "install-mkcert")
commandRunner.openExternalTerminal(command: "echo '=== Setup mkcert Root CA ===' && mkcert -install")
invalidatePackageCaches()
```
With:
```swift
_ = await commandRunner.runShell("sudo -n /opt/local/bin/port install mkcert", label: "install-mkcert")
let currentUser = NSUserName()
let carootPath = ("~/Library/Application Support/mkcert" as NSString).expandingTildeInPath
let script = DoctorService.buildMkcertInstallScript(currentUser: currentUser, carootPath: carootPath)
let adminArgs = DoctorService.buildOsascriptAdminCommand(shellScript: script)
_ = await commandRunner.run(executable: DoctorService.osascriptBinary, arguments: adminArgs, label: "setup-mkcert-ca")
invalidatePackageCaches()
```

- [ ] **Step 3: Update `setupDnsmasq()` in `AppState.swift`**

Remove the standalone failing `writeConfigFile(content:targetPath:)` which previously tried `sudo -n /bin/cp`. Instead:
1. Run `port install dnsmasq`.
2. Inspect if `dnsmasqConfPath` already contains `address=/.test/127.0.0.1`.
3. Call `DoctorService.buildDnsmasqPrivilegedSetupScript(needsConfigAppend: !alreadyContains)`.
4. Run the combined admin script via `osascript` in a single prompt.
5. Run `sudo -n /opt/local/bin/port load dnsmasq`.

- [ ] **Step 4: Run test suite to verify tests pass**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: PASS (all tests green).

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/MacPortsControlCenter/Models/AppState.swift Tests/MacPortsControlCenterTests/AppStateTests.swift
git commit -m "refactor(appstate): switch mkcert and dnsmasq to in-app privileged osascript elevation"
```

---

### Task 3: Application Build & End-to-End Verification

**Files:**
- Verify: `build-app.sh`
- Verify: `build/MacPorts Control Center.app`

- [ ] **Step 1: Execute test runner**

Run: `TEST_RUNNER=1 /tmp/run-all-tests`
Expected: 100% pass across all test suites.

- [ ] **Step 2: Compile release app bundle**

Run: `./build-app.sh`
Expected: Clean compilation, ad-hoc codesign verified (`build/MacPorts Control Center.app: valid on disk, satisfies its Designated Requirement`).

- [ ] **Step 3: Verification of git status and diff**

Run: `git status` and `git diff HEAD~2` to ensure only intended changes were committed and no temporary artifacts were left behind.

- [ ] **Step 4: Commit and finalize**

```bash
git log -n 3 --stat
```
