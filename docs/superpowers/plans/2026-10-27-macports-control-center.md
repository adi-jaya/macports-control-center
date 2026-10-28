# MacPorts Control Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and package **MacPorts Control Center**, a native macOS (`SwiftUI` + `AppKit`) desktop and Menu Bar GUI application at `/Users/adijaya/MyFiles/Projects/macports-control-center` that manages MacPorts services, Nginx virtual hosts, multi-PHP FPM & extensions, MariaDB databases, universal MacPorts packages, server logs, and built-in Markdown documentation with ~15–22 MB RAM usage and zero PHP/WebView dependencies.

**Architecture:** A modular Swift Package (`macosx12.0` deployment target) split into a testable core/UI library (`MacPortsControlCenter`) and a lightweight executable entry point (`MacPortsControlCenterApp`), packaged into `build/MacPorts Control Center.app` via `build-app.sh`. All system interactions run asynchronously through a serialized `CommandRunner` streaming `stdout`/`stderr` into a native `NSTextView` docked terminal drawer.

**Tech Stack:** Apple Swift 5.7+ (`SwiftUI`, `AppKit`, `Foundation`, `Combine`, `XCTest`), MacPorts CLI (`/opt/local/bin/port`), Nginx (`/opt/local/sbin/nginx`), MariaDB (`/opt/local/bin/mysql`, `/opt/local/bin/mysqldump`).

**Spec:** `docs/superpowers/specs/2026-10-27-macports-control-center-design.md`

## Global Constraints

- Target OS minimum: `macOS Monterey 12.0+` (`.macOS(.v12)` in `Package.swift`).
- Zero WebView / Electron usage: Do not import `WebKit` or instantiate `WKWebView`; use native `SwiftUI` views and `AppKit` (`NSTextView`, `NSStatusItem`, `NSOpenPanel`, `NSSavePanel`).
- Never use `sudo` when creating or editing files in `/opt/local/etc/nginx/servers/*.conf`; write directly as the current user (`adijaya`).
- Always validate `/opt/local/sbin/nginx -t` before reloading or restarting Nginx. When run as a non-root user, treat syntax as valid if `exitCode == 0` OR output contains `"syntax is ok"` with no `[emerg]` lines other than `/opt/local/var/run/nginx/nginx.pid` permission denied; roll back `.conf` edits if a real syntax error occurs.
- Always enforce `user = <current_user>` (`NSUserName()`) and `group = staff` in `/opt/local/etc/php*/php-fpm.d/www.conf` (never `nobody` or `_www`).
- Serialize all MacPorts write commands (`sudo -n /opt/local/bin/port ...`) in a FIFO queue so two concurrent clicks never trigger `sqlite error: database is locked`.
- Child processes must inherit `PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSHomeDirectory())/.local/bin"`.

## Review Focus

1. **LaunchDaemons directory structure & real `ps aux` process matching:** `/opt/local/etc/LaunchDaemons/` contains subdirectories (`org.macports.nginx`, `org.macports.php83-fpm`, `org.macports.mariadb-10.11-server`), and `ps aux` shows `/opt/local/lib/mariadb-10.11/bin/mysqld` (without `-server`) and `daemondo --label=php83-fpm` / `(/opt/local/etc/php83/php-fpm.conf)` (pinned in Task 1 `testDiscoverLaunchDaemonsMatchesRealMacPortsPsOutput`).
2. **Multi-version packages in `port installed` (`name@version` IDs & active priority):** When multiple versions of a package are installed (e.g., `curl @8.22.0_0` inactive and `curl @8.23.0_0 (active)`), each item must have a distinct `id` (`"\(name)@\(version)"`) and `installedLookupMap` must prioritize the active entry (pinned in Task 1 `testParseInstalledAndSearchOutputHandlesMultiVersionPorts`).
3. **Rapid concurrent `sudo port` invocations:** Clicking two package/service buttons back-to-back must execute sequentially in FIFO order rather than overlapping (pinned in Task 2 `testSerializedQueueRunsCommandsSequentially`).
4. **Commented directives in Nginx `.conf`, `php.ini`, or `www.conf`:** Files containing commented lines like `# listen 8080;` or `;memory_limit = 128M` above the active directive must have comments ignored during parsing and untouched when updating the active directive (pinned in Task 3 `testParseAndUpdateIgnoresCommentedDirectives`).
5. **Non-root `nginx -t` validation & invalid Virtual Host syntax rollback:** Validator must accept non-root `"syntax is ok"` output (ignoring `nginx.pid` permission warning) while rejecting real `[emerg]` syntax errors and rolling back the `.conf` file (pinned in Task 3 `testIsNginxTestOutputValidHandlesNonRootPidWarningAndRejectsSyntaxErrors` and `testSaveVHostRollsBackWhenValidatorFails`).
6. **Multi-PHP FPM `www.conf` port & user normalization:** Preparing `www.conf` for `php82`, `php83`, or `php84` must set `user = <currentUser>`, `group = staff`, and assign `127.0.0.1:9000` for `php83` vs `127.0.0.1:9082` / `127.0.0.1:9084` for other versions so pools never collide (pinned in Task 3 `testConfigureFPMWwwConfSetsUserAndUniquePort`).
7. **Laravel `.env` values with quotes and inline comments:** Reading `../.env` relative to a site's `/public` root must strip surrounding quotes and `#` inline comments from `DB_DATABASE` and `APP_URL` and gracefully return `nil` when `.env` is absent (pinned in Task 3 `testParseLaravelEnvHandlesQuotesAndComments`).

---

### Task 1: Swift Package Scaffolding, Domain Models & MacPorts Output Parsers (`MacPortsService`)

**Files:**
- Create: `Package.swift`
- Create: `Sources/MacPortsControlCenter/Models/DomainModels.swift`
- Create: `Sources/MacPortsControlCenter/Services/MacPortsService.swift`
- Create: `Sources/MacPortsControlCenterApp/MainApp.swift` (minimal placeholder so executable target compiles)
- Test: `Tests/MacPortsControlCenterTests/MacPortsServiceTests.swift`

**Interfaces:**
- Consumes: none (foundational layer)
- Produces:
  - `ServiceItem(id: String, name: String, plistName: String, isRunning: Bool, isEnabledAtBoot: Bool, detail: String)`
  - `VHostItem(id: String, fileName: String, filePath: String, listenPort: String, serverName: String, rootPath: String, fastcgiPass: String, sslEnabled: Bool, laravelDatabase: String?, laravelAppURL: String?)`
  - `PHPVersionItem(version: String, portName: String, isInstalled: Bool, isCLIDefault: Bool, fpmPort: Int, isFPMRunning: Bool, installedExtensions: Set<String>)`
  - `PortPackageItem(name: String, version: String, category: String, summary: String, isInstalled: Bool, isActive: Bool, isOutdated: Bool)` with computed `var id: String { "\(name)@\(version)" }`
  - `PortSelectGroup(group: String, selected: String, options: [String])`
  - `DoctorCheckItem(id: String, title: String, isHealthy: Bool, detail: String, fixActionDescription: String)`
  - `MacPortsService.supportedPHPExtensionSubports: [String]` (`["mysql", "mbstring", "curl", "openssl", "gd", "intl", "zip", "sqlite", "iconv", "opcache", "redis", "imagick", "xdebug", "postgresql", "soap", "exif", "pcntl", "sockets", "sodium", "posix"]`)
  - `MacPortsService.builtInPHPCoreModules: [String]` (`["bcmath", "json", "ctype", "tokenizer", "xml", "dom", "fileinfo", "phar"]`)
  - `MacPortsService.parsePortSelectSummary(_ output: String) -> [PortSelectGroup]`
  - `MacPortsService.parseInstalledPorts(_ output: String) -> [PortPackageItem]`
  - `MacPortsService.buildInstalledLookupMap(_ items: [PortPackageItem]) -> [String: (version: String, active: Bool)]`
  - `MacPortsService.parseOutdatedPorts(_ output: String) -> Set<String>`
  - `MacPortsService.parseSearchOutput(_ output: String, installed: [String: (version: String, active: Bool)], outdated: Set<String>) -> [PortPackageItem]`
  - `MacPortsService.discoverLaunchDaemons(entryNames: [String], enabledSymlinks: Set<String>, psOutput: String) -> [ServiceItem]`

- [ ] **Step 1: Write `Package.swift` and the failing parser tests in `Tests/MacPortsControlCenterTests/MacPortsServiceTests.swift`**

`Package.swift` defines `.macOS(.v12)`, library target `MacPortsControlCenter`, executable target `MacPortsControlCenterApp`, and test target `MacPortsControlCenterTests`.

```swift
import XCTest
@testable import MacPortsControlCenter

final class MacPortsServiceTests: XCTestCase {
    func testParsePortSelectSummaryExtractsAllGroups() {
        let sample = """
        Name     Selected       Options
        ====     ========       =======
        mysql    mariadb-10.11  mariadb-10.11 none
        php      php83          php82 php83 none
        python3  none           python314 none
        """
        let groups = MacPortsService.parsePortSelectSummary(sample)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[1], PortSelectGroup(group: "php", selected: "php83", options: ["php82", "php83", "none"]))
        XCTAssertEqual(groups[2].group, "python3")
    }

    func testParseInstalledAndSearchOutputHandlesMultiVersionPorts() {
        let installedSample = """
        The following ports are currently installed:
          curl @8.22.0_0+ssl
          curl @8.23.0_0+ssl (active)
          curl @8.21.0_0+ssl
          php85 @8.5.12_0
        """
        let installed = MacPortsService.parseInstalledPorts(installedSample)
        XCTAssertEqual(installed.count, 4)
        XCTAssertNotEqual(installed[0].id, installed[1].id)
        XCTAssertFalse(installed[0].isActive)
        XCTAssertTrue(installed[1].isActive)

        let lookup = MacPortsService.buildInstalledLookupMap(installed)
        XCTAssertEqual(lookup["curl"]?.active, true)
        XCTAssertEqual(lookup["curl"]?.version, "@8.23.0_0+ssl")

        let searchSample = "curl\t8.23.0\tnet www\tCommand line tool for transferring data\nffmpeg\t6.1.1\tmultimedia\tAudio/video converter\n"
        let results = MacPortsService.parseSearchOutput(searchSample, installed: lookup, outdated: ["curl"])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].isInstalled)
        XCTAssertTrue(results[0].isActive)
        XCTAssertTrue(results[0].isOutdated)
        XCTAssertFalse(results[1].isInstalled)
    }

    func testDiscoverLaunchDaemonsMatchesRealMacPortsPsOutput() {
        let entries = [
            "org.macports.nginx",
            "org.macports.php83-fpm",
            "org.macports.mariadb-10.11-server",
            "org.macports.redis"
        ]
        let symlinks: Set<String> = [
            "org.macports.nginx.plist",
            "org.macports.php83-fpm.plist",
            "org.macports.mariadb-10.11-server.plist"
        ]
        let ps = """
        root   262 /opt/local/sbin/nginx -g daemon off;
        root   310 php-fpm: master process (/opt/local/etc/php83/php-fpm.conf)
        adijaya 334 php-fpm: pool www
        _mysql 103 /opt/local/lib/mariadb-10.11/bin/mysqld
        root    96 /opt/local/bin/daemondo --label=php83-fpm --start-cmd /opt/local/sbin/php-fpm83 ; --pid=exec
        """
        let services = MacPortsService.discoverLaunchDaemons(entryNames: entries, enabledSymlinks: symlinks, psOutput: ps)
        XCTAssertEqual(services.count, 4)
        XCTAssertTrue(services.first(where: { $0.name == "nginx" })?.isRunning == true)
        XCTAssertTrue(services.first(where: { $0.name == "php83-fpm" })?.isRunning == true)
        XCTAssertTrue(services.first(where: { $0.name == "mariadb-10.11-server" })?.isRunning == true)
        XCTAssertFalse(services.first(where: { $0.name == "redis" })?.isRunning == true)
        XCTAssertFalse(services.first(where: { $0.name == "redis" })?.isEnabledAtBoot == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MacPortsServiceTests`
Expected: FAIL (missing `DomainModels.swift` and `MacPortsService.swift`)

- [ ] **Step 3: Implement `DomainModels.swift` and `MacPortsService.swift`**

Implement all structs conforming to `Identifiable, Equatable` in `Sources/MacPortsControlCenter/Models/DomainModels.swift` and the pure static parsers plus filesystem/command helpers in `Sources/MacPortsControlCenter/Services/MacPortsService.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MacPortsServiceTests`
Expected: PASS (3 tests passing)

- [ ] **Step 5: Commit**

```bash
rtk git add Package.swift Sources/ Tests/
rtk git commit -m "feat(core): add domain models and MacPorts output parsers"
```

---

### Task 2: Async Streaming Command Runner & Serialized Port Queue (`CommandRunner`)

**Files:**
- Create: `Sources/MacPortsControlCenter/Services/CommandRunner.swift`
- Test: `Tests/MacPortsControlCenterTests/CommandRunnerTests.swift`

**Interfaces:**
- Consumes: `Foundation`
- Produces:
  - `struct CommandResult: Equatable { let exitCode: Int32; let stdout: String; let stderr: String }`
  - `@MainActor final class CommandRunner: ObservableObject`
    - `@Published private(set) var terminalLines: [String]`
    - `@Published private(set) var isRunning: Bool`
    - `@Published private(set) var currentCommandLabel: String`
    - `func run(executable: String, arguments: [String], label: String, serialized: Bool = true, onLine: ((String) -> Void)? = nil) async -> CommandResult`
    - `func runShell(_ command: String, label: String, serialized: Bool = true) async -> CommandResult`
    - `func cancelCurrentProcess()`
    - `func clearLog()`

- [ ] **Step 1: Write the failing tests in `Tests/MacPortsControlCenterTests/CommandRunnerTests.swift`**

```swift
import XCTest
@testable import MacPortsControlCenter

@MainActor
final class CommandRunnerTests: XCTestCase {
    func testStreamsOutputLinesAndRecordsExitCode() async {
        let runner = CommandRunner()
        let result = await runner.runShell("printf 'line1\\nline2\\n'", label: "test-echo", serialized: false)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(runner.terminalLines.contains(where: { $0.contains("line1") }))
        XCTAssertTrue(runner.terminalLines.contains(where: { $0.contains("line2") }))
    }

    func testSerializedQueueRunsCommandsSequentially() async {
        let runner = CommandRunner()
        var order: [String] = []
        async let first = runner.runShell("sleep 0.15 && printf 'first\\n'", label: "first", serialized: true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        async let second = runner.runShell("printf 'second\\n'", label: "second", serialized: true)

        let (r1, r2) = await (first, second)
        XCTAssertEqual(r1.exitCode, 0)
        XCTAssertEqual(r2.exitCode, 0)
        for line in runner.terminalLines {
            if line.contains("first") && !line.contains("$") { order.append("first") }
            if line.contains("second") && !line.contains("$") { order.append("second") }
        }
        XCTAssertEqual(order, ["first", "second"])
    }

    func testCancelCurrentProcessTerminatesLongRunningTask() async {
        let runner = CommandRunner()
        let task = Task {
            await runner.runShell("sleep 10", label: "long-sleep", serialized: false)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        runner.cancelCurrentProcess()
        let res = await task.value
        XCTAssertNotEqual(res.exitCode, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CommandRunnerTests`
Expected: FAIL (`CommandRunner` not defined)

- [ ] **Step 3: Implement `CommandRunner.swift`**

Use `Process` and `Pipe` with `readabilityHandler` dispatching lines to `@MainActor`, setting `environment["PATH"] = "/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSHomeDirectory())/.local/bin"`, and chaining `serialized: true` calls onto a previous `Task` reference so MacPorts commands never overlap.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CommandRunnerTests`
Expected: PASS (3 tests passing)

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MacPortsControlCenter/Services/CommandRunner.swift Tests/MacPortsControlCenterTests/CommandRunnerTests.swift
rtk git commit -m "feat(runner): add streaming CommandRunner with serialized MacPorts queue"
```

---

### Task 3: Configuration File Service (`nginx/*.conf`, `php.ini`, `www.conf`, `.env`, `nginx -t`) (`ConfigFileService`)

**Files:**
- Create: `Sources/MacPortsControlCenter/Services/ConfigFileService.swift`
- Test: `Tests/MacPortsControlCenterTests/ConfigFileServiceTests.swift`

**Interfaces:**
- Consumes: `DomainModels.swift`
- Produces:
  - `struct PHPIniTuning: Equatable { var memoryLimit: String; var uploadMaxFilesize: String; var postMaxSize: String; var maxExecutionTime: String; var nginxClientMaxBodySize: String }`
  - `enum VHostTemplateType: String, CaseIterable { case laravel = "Laravel"; case spa = "SPA / Static" }`
  - `ConfigFileService.parseVHost(filePath: String) -> VHostItem?`
  - `ConfigFileService.parseLaravelEnv(at envPath: String) -> (database: String?, appURL: String?)`
  - `ConfigFileService.generateVHostConfig(serverName: String, listenPort: String, rootPath: String, fpmPort: Int, template: VHostTemplateType, sslCertPath: String?, sslKeyPath: String?) -> String`
  - `ConfigFileService.isNginxTestOutputValid(exitCode: Int32, output: String) -> Bool`
  - `ConfigFileService.saveVHostWithValidation(filePath: String, content: String, validator: () async -> (Bool, String)) async throws`
  - `ConfigFileService.configureFPMWwwConf(content: String, version: String, user: String, group: String) -> String`
  - `ConfigFileService.parsePHPIniTuning(phpIniContent: String, nginxConfContent: String) -> PHPIniTuning`
  - `ConfigFileService.updatePHPIni(content: String, tuning: PHPIniTuning) -> String`
  - `ConfigFileService.updateNginxClientMaxBodySize(content: String, maxBodySize: String) -> String`

- [ ] **Step 1: Write the failing tests in `Tests/MacPortsControlCenterTests/ConfigFileServiceTests.swift`**

Include tests covering all 5 config-related Review Focus items:
1. `testParseAndUpdateIgnoresCommentedDirectives`
2. `testConfigureFPMWwwConfSetsUserAndUniquePort`
3. `testParseLaravelEnvHandlesQuotesAndComments`
4. `testIsNginxTestOutputValidHandlesNonRootPidWarningAndRejectsSyntaxErrors`
5. `testSaveVHostRollsBackWhenValidatorFails`

```swift
import XCTest
@testable import MacPortsControlCenter

final class ConfigFileServiceTests: XCTestCase {
    func testParseAndUpdateIgnoresCommentedDirectives() {
        let phpIni = """
        ;memory_limit = 128M
        memory_limit = 256M
        upload_max_filesize = 2M
        post_max_size = 8M
        max_execution_time = 30
        """
        let nginxConf = """
        http {
            # client_max_body_size 1M;
            client_max_body_size 64M;
        }
        """
        let tuning = ConfigFileService.parsePHPIniTuning(phpIniContent: phpIni, nginxConfContent: nginxConf)
        XCTAssertEqual(tuning.memoryLimit, "256M")
        XCTAssertEqual(tuning.nginxClientMaxBodySize, "64M")

        var newTuning = tuning
        newTuning.memoryLimit = "512M"
        newTuning.uploadMaxFilesize = "128M"
        let updatedIni = ConfigFileService.updatePHPIni(content: phpIni, tuning: newTuning)
        XCTAssertTrue(updatedIni.contains(";memory_limit = 128M"))
        XCTAssertTrue(updatedIni.contains("memory_limit = 512M"))
        XCTAssertTrue(updatedIni.contains("upload_max_filesize = 128M"))
    }

    func testConfigureFPMWwwConfSetsUserAndUniquePort() {
        let raw = """
        [www]
        user = nobody
        group = nobody
        listen = 127.0.0.1:9000
        """
        let php82 = ConfigFileService.configureFPMWwwConf(content: raw, version: "82", user: "adijaya", group: "staff")
        XCTAssertTrue(php82.contains("user = adijaya"))
        XCTAssertTrue(php82.contains("group = staff"))
        XCTAssertTrue(php82.contains("listen = 127.0.0.1:9082"))

        let php83 = ConfigFileService.configureFPMWwwConf(content: raw, version: "83", user: "adijaya", group: "staff")
        XCTAssertTrue(php83.contains("listen = 127.0.0.1:9000"))
    }

    func testParseLaravelEnvHandlesQuotesAndComments() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let envContent = """
        APP_NAME="SiAkurat"
        APP_URL="http://localhost:8080" # local url
        # DB_DATABASE=wrong_db
        DB_DATABASE = 'db_siakurat_sifat' # main db
        """
        try envContent.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parsed = ConfigFileService.parseLaravelEnv(at: tmp.path)
        XCTAssertEqual(parsed.database, "db_siakurat_sifat")
        XCTAssertEqual(parsed.appURL, "http://localhost:8080")
    }

    func testIsNginxTestOutputValidHandlesNonRootPidWarningAndRejectsSyntaxErrors() {
        let nonRootValidOutput = """
        nginx: [alert] could not open error log file: open() "/opt/local/var/log/nginx/error.log" failed (13: Permission denied)
        nginx: the configuration file /opt/local/etc/nginx/nginx.conf syntax is ok
        2026/10/27 20:43:41 [emerg] 4076#0: open() "/opt/local/var/run/nginx/nginx.pid" failed (13: Permission denied)
        nginx: configuration file /opt/local/etc/nginx/nginx.conf test failed
        """
        XCTAssertTrue(ConfigFileService.isNginxTestOutputValid(exitCode: 1, output: nonRootValidOutput))

        let realSyntaxErrorOutput = """
        2026/10/27 20:43:41 [emerg] 4076#0: unknown directive "fastcgi_pass_typo" in /opt/local/etc/nginx/servers/test.conf:12
        nginx: configuration file /opt/local/etc/nginx/nginx.conf test failed
        """
        XCTAssertFalse(ConfigFileService.isNginxTestOutputValid(exitCode: 1, output: realSyntaxErrorOutput))
    }

    func testSaveVHostRollsBackWhenValidatorFails() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let confFile = tmpDir.appendingPathComponent("test.conf")
        try "original-valid-config".write(to: confFile, atomically: true, encoding: .utf8)

        do {
            try await ConfigFileService.saveVHostWithValidation(filePath: confFile.path, content: "broken-config") {
                return (false, "nginx: [emerg] invalid directive")
            }
            XCTFail("Expected validation error")
        } catch {
            let restored = try String(contentsOf: confFile, encoding: .utf8)
            XCTAssertEqual(restored, "original-valid-config")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigFileServiceTests`
Expected: FAIL (`ConfigFileService` not defined)

- [ ] **Step 3: Implement `ConfigFileService.swift`**

Implement all parsers, template generators, atomic file writing (without `sudo`), `isNginxTestOutputValid`, `saveVHostWithValidation` rollback, `www.conf` normalizer, and `php.ini`/`nginx.conf` line updaters in `Sources/MacPortsControlCenter/Services/ConfigFileService.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigFileServiceTests`
Expected: PASS (5 tests passing)

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MacPortsControlCenter/Services/ConfigFileService.swift Tests/MacPortsControlCenterTests/ConfigFileServiceTests.swift
rtk git commit -m "feat(config): add Nginx vhost, php.ini, www.conf, and Laravel .env service"
```

---

### Task 4: MariaDB Database Service & Stack Doctor 5-Guardrail Auto-Fixer (`DatabaseService` & `DoctorService`)

**Files:**
- Create: `Sources/MacPortsControlCenter/Services/DatabaseService.swift`
- Create: `Sources/MacPortsControlCenter/Services/DoctorService.swift`
- Test: `Tests/MacPortsControlCenterTests/DoctorAndDatabaseTests.swift`

**Interfaces:**
- Consumes: `DomainModels.swift`, `CommandRunner.swift`, `ConfigFileService.swift`
- Produces:
  - `DatabaseService.parseShowDatabases(_ output: String) -> [String]`
  - `DatabaseService.buildCreateDatabaseCommand(dbName: String, socketPath: String) -> String`
  - `DatabaseService.buildDumpDatabaseCommand(dbName: String, outputPath: String, socketPath: String) -> String`
  - `DatabaseService.buildImportDatabaseCommand(dbName: String, inputPath: String, socketPath: String) -> String`
  - `DoctorService.evaluateChecks(sudoersOK: Bool, nonCompliantFPMFiles: [String], nginxServersWritable: Bool, mariaDBRunning: Bool, mysqlSocketExists: Bool, unreadableLogFiles: [String]) -> [DoctorCheckItem]`
  - `DoctorService.buildFixStoragePermissionsCommand(projectRootPath: String) -> String`
  - `DoctorService.buildPrivilegedAutoFixScript(currentUser: String) -> String`
  - `DoctorService.buildOsascriptAdminCommand(shellScript: String) -> [String]`

- [ ] **Step 1: Write the failing tests in `Tests/MacPortsControlCenterTests/DoctorAndDatabaseTests.swift`**

```swift
import XCTest
@testable import MacPortsControlCenter

final class DoctorAndDatabaseTests: XCTestCase {
    func testParseShowDatabasesFiltersHeaderAndSystemSchemas() {
        let output = """
        Database
        information_schema
        mysql
        performance_schema
        sys
        db_siakurat_sifat
        sik
        """
        let dbs = DatabaseService.parseShowDatabases(output)
        XCTAssertTrue(dbs.contains("db_siakurat_sifat"))
        XCTAssertTrue(dbs.contains("sik"))
        XCTAssertFalse(dbs.contains("Database"))
        XCTAssertFalse(dbs.contains("information_schema"))
    }

    func testBuildDumpAndImportCommandsUseSocketAndSafeQuoting() {
        let dump = DatabaseService.buildDumpDatabaseCommand(dbName: "db_siakurat_sifat", outputPath: "/tmp/backup.sql", socketPath: "/tmp/mysql.sock")
        XCTAssertTrue(dump.contains("/opt/local/bin/mysqldump"))
        XCTAssertTrue(dump.contains("--socket='/tmp/mysql.sock'"))
        XCTAssertTrue(dump.contains("'db_siakurat_sifat' > '/tmp/backup.sql'"))
    }

    func testDoctorServiceEvaluatesAllFiveGuardrailChecksAndBuildsAutoFixScript() {
        let checks = DoctorService.evaluateChecks(
            sudoersOK: true,
            nonCompliantFPMFiles: ["/opt/local/etc/php84/php-fpm.d/www.conf"],
            nginxServersWritable: true,
            mariaDBRunning: true,
            mysqlSocketExists: true,
            unreadableLogFiles: ["/opt/local/var/log/php83/php-fpm.log"]
        )
        XCTAssertEqual(checks.count, 5)
        XCTAssertTrue(checks.first(where: { $0.id == "sudoers" })?.isHealthy == true)
        XCTAssertFalse(checks.first(where: { $0.id == "fpm-user" })?.isHealthy == true)
        XCTAssertFalse(checks.first(where: { $0.id == "log-readable" })?.isHealthy == true)

        let script = DoctorService.buildPrivilegedAutoFixScript(currentUser: "adijaya")
        XCTAssertTrue(script.contains("/etc/sudoers.d/macports"))
        XCTAssertTrue(script.contains("/opt/local/etc/nginx/servers"))
        XCTAssertTrue(script.contains("/opt/local/var/log/php"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DoctorAndDatabaseTests`
Expected: FAIL (`DatabaseService` and `DoctorService` not defined)

- [ ] **Step 3: Implement `DatabaseService.swift` and `DoctorService.swift`**

Implement database output parsing, safe shell command generation for `mysql` and `mysqldump`, and the 5 `AGENTS.md` guardrail evaluators (`sudoers`, `fpm-user`, `nginx-writable`, `mysql-socket`, `log-readable`) plus `osascript` administrator privilege script builder in `Sources/MacPortsControlCenter/Services/`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DoctorAndDatabaseTests`
Expected: PASS (3 tests passing)

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MacPortsControlCenter/Services/DatabaseService.swift Sources/MacPortsControlCenter/Services/DoctorService.swift Tests/MacPortsControlCenterTests/DoctorAndDatabaseTests.swift
rtk git commit -m "feat(services): add MariaDB DatabaseService and 5-guardrail DoctorService"
```

---

### Task 5: Central `@MainActor` Application State, Shell Layout, Docked Terminal Drawer & `Cmd + K` (`AppState` & Shell Views)

**Files:**
- Create: `Sources/MacPortsControlCenter/Models/AppState.swift`
- Create: `Sources/MacPortsControlCenter/Views/MainWindowView.swift`
- Create: `Sources/MacPortsControlCenter/Views/TerminalDrawerView.swift`
- Create: `Sources/MacPortsControlCenter/Views/CommandPaletteView.swift`
- Test: `Tests/MacPortsControlCenterTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `DomainModels.swift`, `CommandRunner.swift`, `MacPortsService.swift`, `ConfigFileService.swift`, `DatabaseService.swift`, `DoctorService.swift`
- Produces:
  - `enum NavigationSection: String, CaseIterable, Identifiable { case services, sites, php, database, packages, logs, docs }`
  - `struct PaletteCommand: Identifiable { let id: String; let title: String; let subtitle: String; let action: @MainActor () -> Void }`
  - `@MainActor final class AppState: ObservableObject` exposing all published collections (`services`, `vhosts`, `phpVersions`, `databases`, `packages`, `portSelectGroups`, `doctorChecks`, `selectedSection`, `isCommandPalettePresented`) and high-level user actions (`refreshAll()`, `toggleService(_:)`, `restartWebStack()`, `stopAllServices()`, `installPHPBundle(_:)`, `togglePHPExtension(version:ext:install:)`, `saveVHost(...)`, `runDoctorAutoFix()`, `searchPackages(query:)`, `runPortSelect(group:option:)`).

- [ ] **Step 1: Write the failing test in `Tests/MacPortsControlCenterTests/AppStateTests.swift`**

```swift
import XCTest
@testable import MacPortsControlCenter

@MainActor
final class AppStateTests: XCTestCase {
    func testCommandPaletteFilteringMatchesQuery() {
        let state = AppState(autoRefreshOnInit: false)
        let filtered = state.filteredPaletteCommands(query: "restart")
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.contains(where: { $0.title.localizedCaseInsensitiveContains("Restart") }))
    }

    func testDocumentationFilesListLoadsRepositoryMarkdownFiles() {
        let state = AppState(autoRefreshOnInit: false)
        XCTAssertFalse(state.docFiles.isEmpty)
        XCTAssertTrue(state.docFiles.contains(where: { $0.fileName == "README.md" }))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppStateTests`
Expected: FAIL (`AppState` not defined)

- [ ] **Step 3: Implement `AppState.swift`, `MainWindowView.swift`, `TerminalDrawerView.swift`, and `CommandPaletteView.swift`**

Implement `AppState` orchestrating all services, `TerminalDrawerView` wrapping a dark-themed `NSTextView` (`NSViewRepresentable`) for zero-lag streaming output, `CommandPaletteView` (`Cmd + K` overlay), and `MainWindowView` with the 7-item sidebar + top status bar + bottom docked terminal drawer.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppStateTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MacPortsControlCenter/Models/AppState.swift Sources/MacPortsControlCenter/Views/ Tests/MacPortsControlCenterTests/AppStateTests.swift
rtk git commit -m "feat(state): add AppState, MainWindowView, NSTextView TerminalDrawer, and Cmd+K palette"
```

---

### Task 6: Core Web Stack Views (`ServicesView`, `SitesView`, `PHPManagerView`)

**Files:**
- Create: `Sources/MacPortsControlCenter/Views/ServicesView.swift`
- Create: `Sources/MacPortsControlCenter/Views/SitesView.swift`
- Create: `Sources/MacPortsControlCenter/Views/PHPManagerView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/MainWindowView.swift`

**Interfaces:**
- Consumes: `AppState` and all models/services from Tasks 1–5
- Produces:
  - `ServicesView`: Auto-discovered LaunchDaemons cards (`isRunning` & `isEnabledAtBoot`), global Start/Restart/Stop Web Stack buttons, 1-click ecosystem utilities (`dnsmasq`, `mkcert`, `redis`, `fnm`/Composer), and the 5-check **Stack Doctor** panel with 1-click Auto-Fix.
  - `SitesView`: Table of `/opt/local/etc/nginx/servers/*.conf` with auto-detected `.env` `DB_DATABASE` & `APP_URL`, 1-click *Fix Storage Permission*, *Open in Browser/Finder*, plus New/Edit VHost sheet (`NSOpenPanel`, Port vs `*.test`, FPM pool selector, `mkcert` HTTPS toggle, `nginx -t` validation with rollback).
  - `PHPManagerView`: PHP 8.1–8.5 cards with 1-click *Install Bundle + Auto-Config `www.conf`*, *Clean Uninstall (`--follow-dependents` + `leaves`)*, CLI default selector (`port select php`), 20 MacPorts extension checkboxes (`postgresql`, `pcntl`, `sockets`, `sodium`, etc.), read-only *Built-in Core Modules* badges (`bcmath`, `json`, `ctype`, `tokenizer`, `xml`, `dom`, `fileinfo`, `phar`), and **Quick Tuning Form** (`php.ini` & Nginx `client_max_body_size`).

- [ ] **Step 1: Implement `ServicesView.swift`, `SitesView.swift`, and `PHPManagerView.swift` and wire them into `MainWindowView.swift`**

Build the 3 views using native `SwiftUI` + `AppKit` (`NSOpenPanel`, `NSWorkspace`) and wire them to `AppState`.

- [ ] **Step 2: Build and run tests to verify compilation and existing tests pass**

Run: `swift test`
Expected: PASS (all unit tests pass and all 3 views compile cleanly)

- [ ] **Step 3: Commit**

```bash
rtk git add Sources/MacPortsControlCenter/Views/
rtk git commit -m "feat(views): add ServicesView, SitesView, and PHPManagerView"
```

---

### Task 7: Data, Package & Utility Views (`DatabaseView`, `PackagesView`, `LogsView`, `DocsView`)

**Files:**
- Create: `Sources/MacPortsControlCenter/Views/DatabaseView.swift`
- Create: `Sources/MacPortsControlCenter/Views/PackagesView.swift`
- Create: `Sources/MacPortsControlCenter/Views/LogsView.swift`
- Create: `Sources/MacPortsControlCenter/Views/DocsView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/MainWindowView.swift`

**Interfaces:**
- Consumes: `AppState` and all models/services from Tasks 1–5
- Produces:
  - `DatabaseView`: MariaDB connection status (`/tmp/mysql.sock` & `127.0.0.1:3306`), 24+ databases grid, *Create Database*, *Backup `.sql` (`NSSavePanel` + `mysqldump`)*, *Import `.sql` (`NSOpenPanel`)*, and MariaDB 11.4 / MySQL 8 installer cards.
  - `PackagesView`: Universal `port search`, filter tabs (*All / Installed / Outdated*), multi-version support (`name@version`) with version-specific Install/Activate/Deactivate/Uninstall actions, *selfupdate*, *Upgrade Outdated*, *Uninstall Leaves*, and **Dynamic Global Version Switcher (`port select --summary`)**.
  - `LogsView`: Sub-tabs for Nginx `error.log`, `access.log`, PHP-FPM `php-fpm.log`, and MariaDB `error.log` with live tail/refresh, Clear Log, and a 1-click **🔓 Perbaiki Izin Baca Log (Stack Doctor)** banner when a log file is unreadable by the current user.
  - `DocsView`: Built-in native Markdown reader (`NSTextView` formatted output) reading `*.md` docs from `/Users/adijaya/MyFiles/Projects/macports-control-center` or `Bundle.main.resourceURL`.

- [ ] **Step 1: Implement `DatabaseView.swift`, `PackagesView.swift`, `LogsView.swift`, and `DocsView.swift` and wire them into `MainWindowView.swift`**

Build the 4 views and connect them to `MainWindowView` so all 7 sidebar sections are active.

- [ ] **Step 2: Build and run tests to verify compilation and all unit tests pass**

Run: `swift test`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
rtk git add Sources/MacPortsControlCenter/Views/
rtk git commit -m "feat(views): add DatabaseView, PackagesView, LogsView, and DocsView"
```

---

### Task 8: Menu Bar Extra (`NSStatusItem`), `.app` Bundle Packaging & Documentation Update

**Files:**
- Modify: `Sources/MacPortsControlCenterApp/MainApp.swift`
- Create: `Resources/Info.plist`
- Create: `build-app.sh`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: `MacPortsControlCenter` library target
- Produces:
  - `MenuBarController` (`NSStatusItem` in `MainApp.swift`) showing live stack status and quick Start/Stop/Restart actions in the macOS Menu Bar even when the main window is closed
  - Executable bundle `/Users/adijaya/MyFiles/Projects/macports-control-center/build/MacPorts Control Center.app`

- [ ] **Step 1: Implement `MainApp.swift` with `AppDelegate` & `NSStatusItem` Menu Bar controller, `Resources/Info.plist`, and `build-app.sh`**

`build-app.sh` runs `swift build -c release`, creates `build/MacPorts Control Center.app/Contents/{MacOS,Resources}`, copies the compiled binary, `Resources/Info.plist`, and all `*.md` documentation files into `Contents/Resources/`, and signs ad-hoc (`codesign --force --deep --sign -`).

- [ ] **Step 2: Build the release `.app` bundle and run the full test suite**

Run: `bash build-app.sh && swift test`
Expected: `swift test` passes all unit tests AND `build/MacPorts Control Center.app/Contents/MacOS/MacPortsControlCenterApp` exists and is executable.

- [ ] **Step 3: Update `README.md` and `AGENTS.md` to reflect the completed Swift Native GUI architecture and build/run instructions**

Update the documentation tables and build/run instructions in `README.md` and `AGENTS.md`.

- [ ] **Step 4: Verify `.app` bundle structure and git status**

Run: `ls -lh "build/MacPorts Control Center.app/Contents/MacOS/MacPortsControlCenterApp"`
Expected: Binary size ~500 KB – 2 MB, zero external framework dependencies.

- [ ] **Step 5: Commit and push to GitHub**

```bash
rtk git add -A
rtk git commit -m "feat(app): complete Swift Native MacPorts Control Center GUI and .app builder"
rtk git push origin main
```
