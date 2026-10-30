# MacPorts Control Center Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate UI freezes, redundant subprocess spawns, background timer leaks, excess RAM retention, Markdown rendering lag, and unstripped binary bloat across `MacPorts Control Center.app` (`PERF-01` through `PERF-14`) while maintaining 100% pass rate on all 42 existing unit tests plus new regression tests.

**Architecture:** Replace $O(N^2)$ string/data copying in `CommandRunner` and `TerminalDrawerView` with cursor-scanned byte slicing, 30fps batched updates, incremental `NSTextStorage` appends, and quiet `logToTerminal: false` background execution; replace sequential `/bin/zsh -c` polling in `AppState` with concurrent `async let` queries backed by read-only `SQLite3` (`registry.db`), filesystem symlink inspection (`/opt/local/etc/select`), and native `PortIndex.quick` + `PortIndex` search with automatic CLI fallbacks; switch `LogsView` to `DispatchSource` (`kqueue`), cache `MarkdownStyler` & `MenuBarController` assets, tear down `NSHostingView`/`NSWindow` on `Cmd+W` while keeping the `.regular` Dock icon, and strip Mach-O linkedit symbols + ICC icon bloat in `build-app.sh`.

**Tech Stack:** Apple Swift 5.7+ (`SwiftUI`, `AppKit`, `Foundation`, `Combine`, `SQLite3`), Xcode Command Line Tools (`swiftc`, `strip`, `lipo`, `codesign`, `sips`, `iconutil`), macOS Monterey 12.0+ (`x86_64` & `arm64`).

**Spec:** `docs/superpowers/specs/2026-10-30-macports-control-center-performance-design.md`

## Global Constraints

- Target OS minimum: `macOS Monterey 12.0+` (`.macOS(.v12)` in `Package.swift`), zero external Swift packages, zero `WebKit`/`WKWebView`.
- **Command Line Tools Test Execution:** This host uses Xcode Command Line Tools without `XCTest.framework`. Every new test method **must** be added both to its `*Tests.swift` class AND invoked explicitly inside `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`. Compile and run the full suite at every verification step with:
  ```bash
  SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")" && swiftc -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -parse-as-library Sources/MacPortsControlCenter/Models/*.swift Sources/MacPortsControlCenter/Services/*.swift Sources/MacPortsControlCenter/Views/*.swift Tests/MacPortsControlCenterTests/*.swift -lsqlite3 -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests
  ```
- **100% Existing Test Preservation:** Never delete, skip, or weaken assertions in any of the 42 existing tests (`MacPortsServiceTests` 5, `CommandRunnerTests` 6, `ConfigFileServiceTests` 8, `DoctorAndDatabaseTests` 6, `AppStateTests` 17). Preserve all existing public parser signatures, the `TEST_RUNNER == "1"` mock short-circuit in `CommandRunner`, default `logToTerminal: Bool = true` on mutations, and default `AppState.isTerminalDrawerExpanded: Bool = true` at the model init level.
- **SQLite Lock Safety:** Open `/opt/local/var/macports/registry/registry.db` strictly with `"file:\(dbPath)?mode=ro"` and `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI`, finalize statements and close the database handle via `defer` within the same synchronous function, and never use `ORDER BY version` in SQL (avoids MacPorts custom `VERSION` collation).
- **Dock Lifecycle Policy:** When closing the main window (`Cmd+W` / red close button), tear down `NSHostingView` and `NSWindow` to free CoreAnimation/SwiftUI memory, **but keep `NSApp.setActivationPolicy(.regular)`** so the app icon stays in the Dock and reopens cleanly on Dock click (`applicationShouldHandleReopen`) or Menu Bar click.
- **Host Environment Guardrails (`AGENTS.md`):** Never use `sudo` when writing to `/opt/local/etc/nginx/servers/`; always validate `/opt/local/sbin/nginx -t` before reloading Nginx; always enforce `user = <current_user>` and `group = staff` in `www.conf`; keep all `sudo -n /opt/local/bin/port` write commands serialized (`serialized: true`).
- Use `rtk git` for git operations (`rtk git status`, `rtk git add`, `rtk git commit`).

## Review Focus

1. **Fast-exiting subprocess output lost or reordered under 30fps terminal coalescing (`CommandRunner`):** Short commands (`printf 'line1\nline2\n'`) exit in `<3 ms` before a `33 ms` throttle timer fires; pipe `readabilityHandler` and post-exit `readDataToEndOfFile()` must coordinate through a single serial queue and synchronously flush `pendingLines` on `@MainActor` before `run()` returns so `runner.terminalLines` is 100% populated immediately after `await` (pinned in Task 1 `testCoalescedStreamingPreservesAllLinesImmediatelyUponReturn`).
2. **Single-quoted numeric versions & inactive `imaged` rows in `registry.db` (`MacPortsService.readInstalledPortsSQLite`):** MacPorts SQLite wraps numeric-looking versions in single quotes (`'6.6'`, `'2.10'`) and marks inactive versions as `state = 'imaged'` vs active `state = 'installed'`; quotes must be stripped and `isActive` mapped strictly to `state == "installed"` (pinned in Task 2 `testReadInstalledPortsSQLiteStripsQuotesAndDistinguishesActiveState`).
3. **`"none"` ordering & missing `current` symlink in `/opt/local/etc/select` (`MacPortsService.readPortSelectGroupsFilesystem`):** Standard lexicographical sort puts `"none"` before `"python314"`, whereas `port select --summary` places `"none"` last and reports `selected == "none"` when the `current` symlink does not exist (pinned in Task 2 `testReadPortSelectGroupsFilesystemPlacesNoneLastAndHandlesMissingCurrent`).
4. **Nested Tcl braces in `PortIndex` & glob query fallback (`MacPortsService.searchPortsNativeIndex`):** `PortIndex` entries contain nested braces (`platforms {{darwin any}}`, `maintainers {{a @b} {c @d}}`) that break naive `{...}` regex splitting, and glob/regex queries (`php8*`, `^py-`) must return `nil` so `AppState` falls back to `/opt/local/bin/port search` (pinned in Task 2 `testSearchPortsNativeIndexHandlesNestedTclBracesAndFallsBackOnGlob`).
5. **Sliced multi-byte UTF-8 sequences when tailing `>250 KB` log files (`LogFileTailer`):** Seeking to `fileSize - 250*1024` can cut mid-line or mid-emoji/UTF-8 character; `LogFileTailer.readTail` must advance past the first `0x0A` (`\n`) when `fileSize > maxBytes`, while reading from offset `0` without dropping line 1 when `fileSize <= maxBytes` (pinned in Task 4 `testLogFileTailerAdvancesToCleanNewlineBoundaryOnLargeUTF8File`).
6. **Model default vs GUI launch state for `isTerminalDrawerExpanded` (`AppState` / `AppDelegate`):** `AppState(autoRefreshOnInit: false).isTerminalDrawerExpanded` must default to `true` (preserving `testInitialStateProperties`), while setting it to `false` (as `AppDelegate` does on GUI startup) must auto-expand back to `true` only when a mutating (`logToTerminal: true`) command runs—never during quiet (`logToTerminal: false`) polling (pinned in Task 3 `testAutoExpandDrawerOnMutationAndQuietPollingIsolation`).

---

### Task 1: Zero-Copy `StreamCollector`, Quiet Polling Mode, & Incremental `NSTextStorage` (`PERF-01`, `PERF-02`, `PERF-03`, `PERF-04`, `PERF-14b`)

**Files:**
- Modify: `Sources/MacPortsControlCenter/Services/CommandRunner.swift`
- Modify: `Sources/MacPortsControlCenter/Views/TerminalDrawerView.swift`
- Modify: `Tests/MacPortsControlCenterTests/CommandRunnerTests.swift`
- Modify: `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`

**Interfaces:**
- Consumes: `Foundation`, `AppKit`, `SwiftUI`
- Produces:
  - `StreamCollector(splitLines: Bool = true)` with `func appendData(_ data: Data) -> [String]` and `func finish(remainingData: Data?) -> (output: String, finalLines: [String])`
  - `CommandRunner.terminalGeneration: Int` (`@Published public private(set)`)
  - `CommandRunner.onMutationCommandStart: (() -> Void)?` (`public var`)
  - `CommandRunner.runShell(_ command: String, label: String, serialized: Bool = true, logToTerminal: Bool = true) async -> CommandResult`
  - `CommandRunner.run(executable: String, arguments: [String], label: String, serialized: Bool = true, logToTerminal: Bool = true, onLine: ((String) -> Void)? = nil) async -> CommandResult`
  - `TerminalTextViewRepresentable(lines: [String], generation: Int)`

- [ ] **Step 1: Write failing tests in `Tests/MacPortsControlCenterTests/CommandRunnerTests.swift` and register them in `TestRunnerMain.swift`**

Add three tests to `CommandRunnerTests` (and update `TestRunnerMain.swift` to call them and print `(9/9 tests)`):

```swift
    func testStreamCollectorCursorScanAndSplitDisabledMode() {
        let collector = StreamCollector(splitLines: true)
        let part1 = Data("alpha\r\nbeta\ngam".utf8)
        let part2 = Data("ma\ndelta".utf8)
        XCTAssertEqual(collector.appendData(part1), ["alpha", "beta"])
        XCTAssertEqual(collector.appendData(part2), ["gamma"])
        let finished = collector.finish(remainingData: nil)
        XCTAssertEqual(finished.finalLines, ["delta"])
        XCTAssertEqual(finished.output, "alpha\r\nbeta\ngamma\ndelta")

        let rawOnly = StreamCollector(splitLines: false)
        XCTAssertTrue(rawOnly.appendData(Data("line1\nline2\n".utf8)).isEmpty)
        let rawFinished = rawOnly.finish(remainingData: nil)
        XCTAssertTrue(rawFinished.finalLines.isEmpty)
        XCTAssertEqual(rawFinished.output, "line1\nline2\n")
    }

    func testQuietModeSkipsTerminalLinesAndIsRunningState() async {
        let runner = CommandRunner()
        var mutationTriggered = false
        runner.onMutationCommandStart = { mutationTriggered = true }

        let quietRes = await runner.run(
            executable: "/bin/echo",
            arguments: ["background-probe"],
            label: "probe",
            serialized: false,
            logToTerminal: false
        )
        XCTAssertEqual(quietRes.exitCode, 0)
        XCTAssertTrue(quietRes.stdout.contains("background-probe"))
        XCTAssertTrue(runner.terminalLines.isEmpty, "Quiet mode must not pollute terminalLines")
        XCTAssertFalse(runner.isRunning)
        XCTAssertFalse(mutationTriggered, "Quiet mode must not trigger onMutationCommandStart")
    }

    func testCoalescedStreamingPreservesAllLinesImmediatelyUponReturn() async {
        let runner = CommandRunner()
        let res = await runner.runShell(
            "awk 'BEGIN { for (i = 1; i <= 300; i++) printf \"row-%d\\n\", i }'",
            label: "burst-300",
            serialized: false,
            logToTerminal: true
        )
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(runner.terminalLines.first, "$ awk 'BEGIN { for (i = 1; i <= 300; i++) printf \"row-%d\\n\", i }'")
        XCTAssertEqual(runner.terminalLines.last, "row-300")
        XCTAssertEqual(runner.terminalLines.count, 301)
    }
```

- [ ] **Step 2: Run the test suite to verify compilation fails**

Run the `swiftc` test command from **Global Constraints**.
Expected: FAIL (`extra argument 'splitLines'` / `'logToTerminal'` and missing `onMutationCommandStart`).

- [ ] **Step 3: Implement $O(N)$ `StreamCollector`, quiet execution, 30fps batching, and clean `queueTail` in `Sources/MacPortsControlCenter/Services/CommandRunner.swift`**

Key implementation details:
1. In `StreamCollector`: scan `byteBuffer` via `withUnsafeBytes` in a single pass `0..<bytes.count` for `UInt8(ascii: "\n")` (stripping trailing `\r`), decoding each slice directly without mutating `byteBuffer` inside the loop; after the loop, slice `byteBuffer` once (`lineStart == 0 ? byteBuffer : (lineStart < count ? Data(byteBuffer[lineStart...]) : Data())`). When `splitLines == false`, `appendData` only appends to `allBytes` and returns `[]`.
2. In `CommandRunner`:
   - Add `@Published public private(set) var terminalGeneration: Int = 0` (`clearLog()` empties `terminalLines`, clears `pendingLines`, and increments `terminalGeneration += 1`).
   - Add `public var onMutationCommandStart: (() -> Void)? = nil`.
   - Use hysteresis trimming in `appendLines(_ lines: [String])`: append all lines at once (`terminalLines.append(contentsOf: lines)`), and only when `terminalLines.count > 5500`, `terminalLines.removeFirst(terminalLines.count - maxTerminalLines)` and `terminalGeneration += 1`.
   - When `serialized == true`, track `private var queueTailToken: UUID?` alongside `queueTail`; when `task` finishes, if `queueTailToken == myToken`, set `queueTail = nil` and `queueTailToken = nil` so completed tasks are released.
   - When `logToTerminal == false` and `onLine == nil`: instantiate `StreamCollector(splitLines: false)`, do not touch `activeProcesses` / `isRunning` / `currentCommandLabel` / `terminalLines` / `onMutationCommandStart`.
   - When `logToTerminal == true` or `onLine != nil`: call `onMutationCommandStart?()` if `logToTerminal == true`; serialize `readabilityHandler` chunks through a local `DispatchQueue(label: "mpcc.pipe.\(runID)")`, coalesce UI flushes onto `@MainActor` every `33 ms` (`DispatchSourceTimer` or scheduled flag), and after `terminationHandler` fires, run `pipeQueue.sync {}` after clearing `readabilityHandler`s, read remaining EOF data, and flush all buffered + final lines synchronously on `@MainActor` before returning `CommandResult`.

- [ ] **Step 4: Implement incremental `NSTextStorage` rendering in `Sources/MacPortsControlCenter/Views/TerminalDrawerView.swift`**

Replace `TerminalTextViewRepresentable(text: runner.terminalLines.joined(separator: "\n"))` with `TerminalTextViewRepresentable(lines: runner.terminalLines, generation: runner.terminalGeneration)`:
- Add `Coordinator` storing `var lastGeneration: Int = -1` and `var renderedLineCount: Int = 0`, plus prebuilt `defaultAttributes: [NSAttributedString.Key: Any]` matching Slate-200 `#E2E8F0` and `monospacedSystemFont(ofSize: 11, weight: .regular)`.
- In `updateNSView`:
  - If `context.coordinator.lastGeneration != generation || lines.count < context.coordinator.renderedLineCount`: set full text via `textStorage.setAttributedString(...)` from `lines.joined(separator: "\n")`, update `lastGeneration = generation` and `renderedLineCount = lines.count`, and scroll to end if non-empty.
  - Else if `lines.count > context.coordinator.renderedLineCount`: join only `lines[context.coordinator.renderedLineCount..<lines.count]` (prefixed with `"\n"` when `renderedLineCount > 0`), append via `textStorage.beginEditing()` / `textStorage.append(...)` / `textStorage.endEditing()`, set `renderedLineCount = lines.count`, and call `textView.scrollToEndOfDocument(nil)`.

- [ ] **Step 5: Run the full test suite and verify all tests pass**

Run the `swiftc` test command from **Global Constraints**.
Expected: PASS (`45/45` total tests passing, exit code `0`).

- [ ] **Step 6: Commit Task 1**

```bash
rtk git add Sources/MacPortsControlCenter/Services/CommandRunner.swift Sources/MacPortsControlCenter/Views/TerminalDrawerView.swift Tests/MacPortsControlCenterTests/CommandRunnerTests.swift Tests/MacPortsControlCenterTests/TestRunnerMain.swift
rtk git commit -m "perf(runner): use O(N) stream scanning, quiet polling mode, and incremental NSTextStorage"
```

---

### Task 2: Native Read-Only MacPorts Readers (`registry.db`, `/opt/local/etc/select`, `PortIndex.quick`) & Fast Scanning (`PERF-05`, `PERF-06`, `PERF-13a`)

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/MacPortsControlCenter/Services/MacPortsService.swift`
- Modify: `Sources/MacPortsControlCenter/Services/DoctorService.swift`
- Modify: `Tests/MacPortsControlCenterTests/MacPortsServiceTests.swift`
- Modify: `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`

**Interfaces:**
- Consumes: `SQLite3`, `Foundation`, `DomainModels`
- Produces (in `MacPortsService`, while keeping all existing static methods intact):
  - `public static func readInstalledPortsSQLite(dbPath: String = "/opt/local/var/macports/registry/registry.db") -> [PortPackageItem]?`
  - `public static func readPortSelectGroupsFilesystem(selectRootPath: String = "/opt/local/etc/select") -> [PortSelectGroup]?`
  - `public static func parseTclPortIndexRecord(_ record: String) -> (version: String, categories: String, description: String)`
  - `public static func resolvePortIndexPaths(sourcesConfPath: String = "/opt/local/etc/macports/sources.conf", sourcesRoot: String = "/opt/local/var/macports/sources") -> [(quickIndexPath: String, portIndexPath: String)]`
  - `public static func searchPortsNativeIndex(query: String, indexPaths: [(quickIndexPath: String, portIndexPath: String)]? = nil, installed: [String: (version: String, active: Bool)], outdated: Set<String>) -> [PortPackageItem]?`

- [ ] **Step 1: Write failing unit tests in `Tests/MacPortsControlCenterTests/MacPortsServiceTests.swift` and register in `TestRunnerMain.swift`**

Import `SQLite3` in `MacPortsServiceTests.swift`, add three isolated fixture-based tests, and register them in `TestRunnerMain.swift` (`8/8 tests`):

```swift
    func testReadInstalledPortsSQLiteStripsQuotesAndDistinguishesActiveState() {
        let tempDB = (NSTemporaryDirectory() as NSString).appendingPathComponent("reg_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(atPath: tempDB) }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempDB, &db), SQLITE_OK)
        let setupSQL = """
        CREATE TABLE ports (name TEXT, version TEXT, revision INTEGER, variants TEXT, state TEXT);
        INSERT INTO ports VALUES ('ncurses', '''6.6''', 0, '', 'installed');
        INSERT INTO ports VALUES ('curl', '8.22.0', 0, '+http2+ssl', 'imaged');
        INSERT INTO ports VALUES ('curl', '8.23.0', 1, '+http2+ssl', 'installed');
        INSERT INTO ports VALUES ('removed_pkg', '1.0', 0, '', 'uninstalled');
        """
        XCTAssertEqual(sqlite3_exec(db, setupSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let items = MacPortsService.readInstalledPortsSQLite(dbPath: tempDB)
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 3)
        let ncurses = items?.first(where: { $0.name == "ncurses" })
        XCTAssertEqual(ncurses?.version, "@6.6_0")
        XCTAssertEqual(ncurses?.isActive, true)

        let curlVersions = items?.filter { $0.name == "curl" } ?? []
        XCTAssertEqual(curlVersions.count, 2)
        XCTAssertTrue(curlVersions.contains(where: { $0.version == "@8.22.0_0+http2+ssl" && !$0.isActive }))
        XCTAssertTrue(curlVersions.contains(where: { $0.version == "@8.23.0_1+http2+ssl" && $0.isActive }))
        XCTAssertNil(MacPortsService.readInstalledPortsSQLite(dbPath: "/nonexistent/registry.db"))
    }

    func testReadPortSelectGroupsFilesystemPlacesNoneLastAndHandlesMissingCurrent() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("select_\(UUID().uuidString)")
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: root) }

        try fm.createDirectory(atPath: "\(root)/mysql", withIntermediateDirectories: true)
        try "".write(toFile: "\(root)/mysql/base", atomically: true, encoding: .utf8)
        try "".write(toFile: "\(root)/mysql/none", atomically: true, encoding: .utf8)
        try "".write(toFile: "\(root)/mysql/mariadb-10.11", atomically: true, encoding: .utf8)
        try "".write(toFile: "\(root)/mysql/mariadb-11.4", atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: "\(root)/mysql/current", withDestinationPath: "mariadb-10.11")

        try fm.createDirectory(atPath: "\(root)/python3", withIntermediateDirectories: true)
        try "".write(toFile: "\(root)/python3/none", atomically: true, encoding: .utf8)
        try "".write(toFile: "\(root)/python3/python314", atomically: true, encoding: .utf8)

        let groups = MacPortsService.readPortSelectGroupsFilesystem(selectRootPath: root)
        XCTAssertEqual(groups?.count, 2)
        XCTAssertEqual(groups?[0], PortSelectGroup(group: "mysql", selected: "mariadb-10.11", options: ["mariadb-10.11", "mariadb-11.4", "none"]))
        XCTAssertEqual(groups?[1], PortSelectGroup(group: "python3", selected: "none", options: ["python314", "none"]))
    }

    func testSearchPortsNativeIndexHandlesNestedTclBracesAndFallsBackOnGlob() throws {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pidx_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let rec1Body = "variants {universal} platforms {{darwin any}} maintainers {{a @b} {c @d}} description {PHP: Hypertext Preprocessor} name php83 version 8.3.36 categories {lang php www} revision 0\n"
        let rec1Header = "php83 \(rec1Body.utf8.count)\n"
        let rec2Body = "description {Redis extension for PHP 8.3} name php83-redis version 6.0.2 categories {php databases}\n"
        let rec2Header = "php83-redis \(rec2Body.utf8.count)\n"

        let portIndexContent = rec1Header + rec1Body + rec2Header + rec2Body
        let offset2 = (rec1Header + rec1Body).utf8.count
        let quickContent = "php83 0\nphp83-redis \(offset2)\n"

        let pPath = "\(dir)/PortIndex"
        let qPath = "\(dir)/PortIndex.quick"
        try portIndexContent.write(toFile: pPath, atomically: true, encoding: .utf8)
        try quickContent.write(toFile: qPath, atomically: true, encoding: .utf8)

        let results = MacPortsService.searchPortsNativeIndex(
            query: "PHP83",
            indexPaths: [(quickIndexPath: qPath, portIndexPath: pPath)],
            installed: ["php83": (version: "@8.3.36_0", active: true)],
            outdated: ["php83"]
        )
        XCTAssertEqual(results?.count, 2)
        XCTAssertEqual(results?[0].name, "php83")
        XCTAssertEqual(results?[0].version, "8.3.36")
        XCTAssertEqual(results?[0].category, "lang php www")
        XCTAssertEqual(results?[0].summary, "PHP: Hypertext Preprocessor")
        XCTAssertEqual(results?[0].isInstalled, true)
        XCTAssertEqual(results?[0].isOutdated, true)

        let globResult = MacPortsService.searchPortsNativeIndex(
            query: "php8*",
            indexPaths: [(quickIndexPath: qPath, portIndexPath: pPath)],
            installed: [:],
            outdated: []
        )
        XCTAssertNil(globResult, "Glob queries must return nil to trigger CLI fallback")
    }
```

- [ ] **Step 2: Run the test suite to verify compilation fails**

Run the `swiftc` test command from **Global Constraints**.
Expected: FAIL (missing `readInstalledPortsSQLite`, `readPortSelectGroupsFilesystem`, `searchPortsNativeIndex`).

- [ ] **Step 3: Add `sqlite3` linker setting to `Package.swift` and implement native readers + fast scanning in `MacPortsService.swift` and `DoctorService.swift`**

1. In `Package.swift`: add `linkerSettings: [.linkedLibrary("sqlite3")]` to `.target(name: "MacPortsControlCenter", ...)`.
2. In `MacPortsService.swift` (`import SQLite3`):
   - `readInstalledPortsSQLite`: guard `FileManager.default.isReadableFile(atPath: dbPath)`, open with `sqlite3_open_v2("file:\(dbPath)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)`, `defer { sqlite3_close(db) }`, prepare `"SELECT name, version, revision, variants, state FROM ports WHERE state IN ('installed', 'imaged');"`, `defer { sqlite3_finalize(stmt) }`, strip surrounding `'` from `version`, format `"@\(cleanVer)_\(rev)\(vars)"`, set `isActive: state == "installed"`, sort case-insensitively by `name`.
   - `readPortSelectGroupsFilesystem`: enumerate non-dot subdirectories of `selectRootPath` sorted; resolve `current` via `destinationOfSymbolicLink` (taking `(dest as NSString).lastPathComponent`, defaulting to `"none"`); collect entries excluding `"base"`, `"current"`, and dotfiles; sort non-`"none"` entries alphabetically and append `"none"` at the end if `"none"` existed in the directory.
   - `parseTclPortIndexRecord(_ record: String)`: iterate UTF-8/Unicode scalars with a depth counter for `{` and `}` (skipping escaped `\` characters) to yield alternating `(key, value)` tokens without regex; capture `"version"`, `"categories"`, and `"description"`, stopping early once all three are found.
   - `resolvePortIndexPaths`: read uncommented lines from `sourcesConfPath`; map `file:///path` to `("/path/PortIndex.quick", "/path/PortIndex")` and `rsync://host/path` (stripping trailing `.tar` if present, e.g., `ports.tar` -> `ports`) to `"\(sourcesRoot)/\(host)/\(cleanPath)/PortIndex(.quick)"`, appending the standard default `/opt/local/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports/PortIndex` if not already included; filter to pairs where both files are readable.
   - `searchPortsNativeIndex`: return `nil` if `query` is empty or contains any character in `"*?[]^$\\"`; scan `PortIndex.quick` bytes line-by-line matching `query.lowercased()` in the port name column, seek `FileHandle` in `PortIndex` to the parsed `UInt64` offset, read header `<ActualName> <byteLen>\n` + `<byteLen>` bytes, parse via `parseTclPortIndexRecord`, enrich with `installed` & `outdated`, and sort by `name` case-insensitively.
   - Optimize `discoverLaunchDaemons`: split `psOutput` once via `psOutput.split(separator: "\n")` into `[Substring]` lines and match against lines instead of scanning full `psOutput` repeatedly.
3. In `DoctorService.buildPrivilegedAutoFixScript`: replace regex evaluation with a static helper `isValidUsername(_ s: String) -> Bool` checking `!s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-") }`.

- [ ] **Step 4: Run the full test suite and verify all tests pass**

Run the `swiftc` test command from **Global Constraints**.
Expected: PASS (`48/48` total tests passing).

- [ ] **Step 5: Commit Task 2**

```bash
rtk git add Package.swift Sources/MacPortsControlCenter/Services/MacPortsService.swift Sources/MacPortsControlCenter/Services/DoctorService.swift Tests/MacPortsControlCenterTests/MacPortsServiceTests.swift Tests/MacPortsControlCenterTests/TestRunnerMain.swift
rtk git commit -m "perf(macports): add read-only SQLite registry, select symlink, and PortIndex.quick readers"
```

---

### Task 3: Parallel `AppState.refreshAll()`, Package Caching, Batch Unload, & Equality Guards (`PERF-05`, `PERF-06`, `PERF-07b`, `PERF-09b`, `PERF-10a/b`, `PERF-13c`, `PERF-14a`)

**Files:**
- Modify: `Sources/MacPortsControlCenter/Models/AppState.swift`
- Modify: `Tests/MacPortsControlCenterTests/AppStateTests.swift`
- Modify: `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`

**Interfaces:**
- Consumes: `CommandRunner` (`logToTerminal`, `onMutationCommandStart`), `MacPortsService` native readers
- Produces (on `AppState`):
  - `@Published public private(set) var isMySQLSocketConnected: Bool = false`
  - `@Published public private(set) var installedDatabaseEngines: Set<String> = []`
  - `public func ensureSelectedDocLoaded()`
  - `public func invalidatePackageCaches()`
  - `public func purgeTransientCachesForBackground()`

- [ ] **Step 1: Write failing tests in `Tests/MacPortsControlCenterTests/AppStateTests.swift` and register in `TestRunnerMain.swift`**

Add two tests to `AppStateTests` and register them in `TestRunnerMain.swift` (`19/19` in `AppStateTests`):

```swift
    func testPaletteCommandsUseDeterministicStableIDs() {
        let state = AppState(autoRefreshOnInit: false)
        let firstPass = state.filteredPaletteCommands(query: "").map(\.id)
        let secondPass = state.filteredPaletteCommands(query: "").map(\.id)
        XCTAssertFalse(firstPass.isEmpty)
        XCTAssertEqual(firstPass, secondPass, "PaletteCommand IDs must be deterministic across renders")
    }

    func testAutoExpandDrawerOnMutationAndQuietPollingIsolation() async {
        let state = AppState(autoRefreshOnInit: false)
        XCTAssertTrue(state.isTerminalDrawerExpanded, "Model default must remain true")

        // Simulate AppDelegate collapsing drawer on GUI launch
        state.isTerminalDrawerExpanded = false
        _ = await state.commandRunner.run(
            executable: "/bin/echo",
            arguments: ["quiet-check"],
            label: "quiet",
            serialized: false,
            logToTerminal: false
        )
        XCTAssertFalse(state.isTerminalDrawerExpanded, "Quiet polling must not expand drawer")
        XCTAssertTrue(state.commandRunner.terminalLines.isEmpty)

        // Mutating command must auto-expand drawer
        await state.installPackage(name: "htop")
        XCTAssertTrue(state.isTerminalDrawerExpanded, "Mutating command must auto-expand drawer")

        // Purging transient caches keeps docFiles metadata intact while freeing doc text
        state.ensureSelectedDocLoaded()
        XCTAssertFalse(state.selectedDocContent.isEmpty)
        state.purgeTransientCachesForBackground()
        XCTAssertTrue(state.selectedDocContent.isEmpty)
        XCTAssertFalse(state.docFiles.isEmpty)
        XCTAssertNotNil(state.selectedDoc)
    }
```

- [ ] **Step 2: Run the test suite to verify compilation fails**

Run the `swiftc` test command from **Global Constraints**.
Expected: FAIL (missing `ensureSelectedDocLoaded` and `purgeTransientCachesForBackground`).

- [ ] **Step 3: Refactor `AppState.swift` for concurrent `refreshAll()`, package caches, lazy docs, deterministic IDs, and batched `stopAllServices()`**

Implement in `Sources/MacPortsControlCenter/Models/AppState.swift`:
1. **Auto-expand hook & lazy doc loading:**
   - In `init`: wire `self.commandRunner.onMutationCommandStart = { [weak self] in guard let self = self else { return }; if !self.isTerminalDrawerExpanded { self.isTerminalDrawerExpanded = true } }`.
   - In `loadDocumentationFiles()`: set `self.docFiles = items` and `if selectedDoc == nil { selectedDoc = items.first }`, **without** eagerly loading `selectedDocContent` on init. Add `public func ensureSelectedDocLoaded()` which sets `selectedDocContent = loadDocContent(doc: doc)` when `selectedDocContent.isEmpty`, and keep `selectDoc(_:)` + `loadDocContent(doc:)` unchanged.
2. **Deterministic `PaletteCommand` IDs:** pass explicit IDs to every `PaletteCommand(id: ..., title: ...)` (`"nav-\(section.rawValue)"`, `"action-restart-stack"`, `"action-start-stack"`, `"action-stop-all"`, `"action-reload-nginx"`, `"action-doctor-autofix"`, `"action-refresh-all"`, `"action-selfupdate"`, `"action-upgrade-outdated"`, `"action-uninstall-leaves"`, `"action-clear-terminal"`, `"action-toggle-terminal"`, `"php-cli-\(php.portName)"`).
3. **Equality guard helper:** `private func assignIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, _ newValue: T)` so identical refresh results fire zero `@Published` notifications.
4. **Concurrent `refreshAll()` & quiet direct process calls (`logToTerminal: false`, no `/bin/zsh -c`):**
   - Run `/bin/ps` (`arguments: ["-axo", "command"]`, `serialized: false`, `logToTerminal: false`) **once** via `async let` alongside background disk tasks (`Task.detached`) reading `vhosts`, `installedPorts` (`MacPortsService.readInstalledPortsSQLite()` with CLI fallback `/opt/local/bin/port` `["installed"]`), `selectGroups` (`MacPortsService.readPortSelectGroupsFilesystem()` with CLI fallback `/opt/local/bin/port` `["select", "--summary"]`), and socket presence `DoctorService.isMySQLSocketPresent(path: defaultSocketPath)`.
   - Only when socket is present, run `/opt/local/bin/mysql` (`arguments: ["-u", "root", "--socket=\(defaultSocketPath)", "-N", "-B", "-e", "SHOW DATABASES;"]`, `serialized: false`, `logToTerminal: false`); otherwise `databases = []`.
   - Derive `services`, `phpVersions`, `portSelectGroups`, `isMySQLSocketConnected`, `installedDatabaseEngines` (checking installed port names + `/opt/local/etc/{mariadb-10.11,mariadb-11.4,mysql8}` off-main-thread), and `doctorChecks` from the shared snapshots, cache `cachedInstalledPorts = installedPorts`, and update all `@Published` properties via `assignIfChanged`.
   - Also update standalone `refreshServices()`, `refreshPHPVersions()`, `refreshDatabases()`, `refreshPortSelect()`, and `reloadNginx()`'s `nginx -t` check to pass `logToTerminal: false` (keeping `nginx -t` failure error reporting via `statusMessage` / `appendLine` if invalid) and use native readers where applicable.
5. **Cached `searchPackages(query:)` & `loadInstalledPackages()`:**
   - Store `private var cachedInstalledPorts: [PortPackageItem]?` and `private var cachedOutdatedPorts: Set<String>?`.
   - Fetch `installed` from `cachedInstalledPorts ?? MacPortsService.readInstalledPortsSQLite()` (fallback CLI `port installed`, `logToTerminal: false`), and fetch `outdated` from `cachedOutdatedPorts` (if `nil`, call `/opt/local/bin/port` `["outdated"]` with `logToTerminal: false` and cache the resulting `Set<String>`).
   - In `searchPackages(query:)`: try `MacPortsService.searchPortsNativeIndex(query: trimmed, installed: installedMap, outdated: outdatedSet)` on a background task; if `nil`, call `commandRunner.run(executable: "/opt/local/bin/port", arguments: ["search", "--name", "--line", trimmed], label: "search-\(trimmed)", serialized: false, logToTerminal: false)`. Check `!Task.isCancelled` before assigning `self.packages`.
   - Call `invalidatePackageCaches()` inside `refreshAfterPackageChange()`, `installPHPBundle`, `togglePHPExtension`, `uninstallPHPVersion`, `installDatabaseEngine`, `setupDnsmasq`, `setupMkcert`, `setupRedis`, `setupFnmAndComposer`, `runSelfUpdate`, `runUpgradeOutdated`, and `runUninstallLeaves`.
6. **Batch `stopAllServices()` & background cache purge:**
   - In `stopAllServices()`: collect `let runningNames = services.filter(\.isRunning).map(\.name)`; if non-empty, execute a single `commandRunner.runShell("sudo -n /opt/local/bin/port unload \(runningNames.joined(separator: " "))", label: "stop-all-services")` instead of looping.
   - Implement `purgeTransientCachesForBackground()`: set `selectedDocContent = ""`; if `!packageSearchQuery.isEmpty`, set `packageSearchQuery = ""` and `packages = []`.

- [ ] **Step 4: Run the full test suite and verify all tests pass**

Run the `swiftc` test command from **Global Constraints**.
Expected: PASS (`50/50` total tests passing).

- [ ] **Step 5: Commit Task 3**

```bash
rtk git add Sources/MacPortsControlCenter/Models/AppState.swift Tests/MacPortsControlCenterTests/AppStateTests.swift Tests/MacPortsControlCenterTests/TestRunnerMain.swift
rtk git commit -m "perf(state): parallelize refreshAll, cache package metadata, and stabilize palette IDs"
```

---

### Task 4: Event-Driven `LogsView` (`DispatchSource` `kqueue`) & `MarkdownStyler` Fast-Path + Cache (`PERF-08`, `PERF-11`)

**Files:**
- Modify: `Sources/MacPortsControlCenter/Views/LogsView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/DocsView.swift`
- Modify: `Tests/MacPortsControlCenterTests/AppStateTests.swift`
- Modify: `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`

**Interfaces:**
- Consumes: `AppState.ensureSelectedDocLoaded()`, `DispatchSourceFileSystemObject`
- Produces:
  - `extension Notification.Name { public static let mpccMainWindowDidClose = Notification.Name("mpccMainWindowDidClose") }` (in `LogsView.swift`)
  - `LogFileTailer.readTail(atPath path: String, maxBytes: UInt64 = 250 * 1024) -> (content: String, fileSize: Int64, isUnreadable: Bool, exists: Bool)`
  - `MarkdownStyler.cachedStyle(for key: String, markdown: String) -> NSAttributedString` and `MarkdownStyler.clearCache()`

- [ ] **Step 1: Write failing tests in `Tests/MacPortsControlCenterTests/AppStateTests.swift` and register in `TestRunnerMain.swift`**

Add two tests to `AppStateTests` and register them in `TestRunnerMain.swift` (`21/21` in `AppStateTests`):

```swift
    func testLogFileTailerAdvancesToCleanNewlineBoundaryOnLargeUTF8File() throws {
        let tempFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("utf8_log_\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        var payload = ""
        for i in 0..<40 {
            payload += "2026-10-30 [error] 🚀 baris-log-panjang-ke-\(i)\n"
        }
        try payload.write(toFile: tempFile, atomically: true, encoding: .utf8)

        // Small maxBytes cuts into the middle of a multi-byte UTF-8 line
        let tail = LogFileTailer.readTail(atPath: tempFile, maxBytes: 220)
        XCTAssertTrue(tail.exists)
        XCTAssertFalse(tail.isUnreadable)
        XCTAssertTrue(tail.content.hasPrefix("2026-10-30 [error] 🚀 baris-log-panjang-ke-"), "Tail must start cleanly at the next full line")
        XCTAssertFalse(tail.content.contains("\u{FFFD}"), "Tail must never contain replacement characters from sliced UTF-8")

        // File smaller than maxBytes keeps the very first line intact
        let full = LogFileTailer.readTail(atPath: tempFile, maxBytes: 100_000)
        XCTAssertTrue(full.content.hasPrefix("2026-10-30 [error] 🚀 baris-log-panjang-ke-0\n"))
    }

    func testMarkdownStylerCacheHitAndClear() {
        MarkdownStyler.clearCache()
        let md = "# Title\nPlain paragraph without inline markers.\n| A | B |\n|---|---|\n| plain | **bold** |"
        let first = MarkdownStyler.cachedStyle(for: "doc-test", markdown: md)
        let second = MarkdownStyler.cachedStyle(for: "doc-test", markdown: md)
        XCTAssertTrue(first === second, "cachedStyle must return identical NSAttributedString instance on cache hit")
        MarkdownStyler.clearCache()
        let third = MarkdownStyler.cachedStyle(for: "doc-test", markdown: md)
        XCTAssertFalse(first === third, "clearCache must evict cached NSAttributedString instances")
    }
```

- [ ] **Step 2: Run the test suite to verify compilation fails**

Run the `swiftc` test command from **Global Constraints**.
Expected: FAIL (missing `LogFileTailer`, `MarkdownStyler.cachedStyle`, `MarkdownStyler.clearCache`).

- [ ] **Step 3: Implement `LogFileTailer` (`DispatchSource` `kqueue` + clean `\n` slicing + debounced filter) in `Sources/MacPortsControlCenter/Views/LogsView.swift`**

1. Declare `public extension Notification.Name { static let mpccMainWindowDidClose = Notification.Name("mpccMainWindowDidClose") }`.
2. Create `@MainActor public final class LogFileTailer: ObservableObject`:
   - Static pure helper `public static func readTail(atPath path: String, maxBytes: UInt64 = 250 * 1024) -> (content: String, fileSize: Int64, isUnreadable: Bool, exists: Bool)`: if `fileSize > maxBytes`, seek to `fileSize - maxBytes`, read to EOF, and if `let nl = data.firstIndex(of: UInt8(ascii: "\n"))`, drop `data[...nl]` so decoding always starts on a clean line boundary.
   - Track `(lastInode: UInt64, lastSize: UInt64, lastModDate: Date)` via `FileManager.attributesOfItem` (`.systemFileNumber`, `.size`, `.modificationDate`) and skip disk read if unchanged.
   - Manage `private var fileSource: DispatchSourceFileSystemObject?`, `private var watchedFD: Int32 = -1`, and `private var missingFileTimer: Timer?`. When `isAutoTailEnabled` is true and file is readable, `open(path, O_EVTONLY)` and create `DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.extend, .write, .attrib, .delete, .rename], queue: .main)`; reopen on `.delete`/`.rename`. Only start `missingFileTimer` (`3.0s`) when file does not exist yet, invalidating it immediately once opened.
   - Observe `.mpccMainWindowDidClose` and provide `stopWatching()` (closing FD & cancelling source/timer) called on `onDisappear` and window close.
   - Cache MariaDB log path resolution once per tab switch instead of calling `ProcessInfo.processInfo.hostName` + `fileExists` inside `body`, and debounce `filterQuery` (`150 ms` cancellable `Task`) into `@Published var displayedLogText: String`.

- [ ] **Step 4: Implement `MarkdownStyler` fast-paths, static regexes, cache, and single-pass `DocsScrollView` layout in `Sources/MacPortsControlCenter/Views/DocsView.swift`**

1. Precompile `private static let orderedListRegex = try! NSRegularExpression(pattern: #"^(\d+\.)\s+(.*)$"#)` and `private static let brTagRegex = try! NSRegularExpression(pattern: #"<br\s*/?>"# , options: [.caseInsensitive])`.
2. Add early returns: `guard raw.contains("&") else { return raw }` in `decodeHTMLEntities`, `if text.contains("<")` around `brTagRegex` in `cleanCellText`, and `private static func hasInlineSyntax(_ s: String) -> Bool` checking `s.utf8.contains { $0 == 96 || $0 == 42 || $0 == 95 || $0 == 91 || $0 == 126 || $0 == 92 }` (`` ` * _ [ ~ \ ``) so plain table cells and plain paragraphs/bullets skip `AttributedString(markdown:)` completely.
3. Add thread-safe cache (`NSLock` + `[String: (length: Int, hash: Int, rendered: NSAttributedString)]`) exposed via `public static func cachedStyle(for key: String, markdown: String) -> NSAttributedString` and `public static func clearCache()`.
4. In `MarkdownTextViewRepresentable`, pass `docKey: String` (`appState.selectedDoc?.filePath ?? "inline"`) and use `MarkdownStyler.cachedStyle(for: docKey, markdown: markdownText)`. Remove duplicate `ensureLayout` in `updateNSView` when width hasn't changed (`DocsScrollView.layout()` already handles width resize). In `DocsView.onAppear`, call `appState.ensureSelectedDocLoaded()`.

- [ ] **Step 5: Run the full test suite and verify all tests pass**

Run the `swiftc` test command from **Global Constraints**.
Expected: PASS (`52/52` total tests passing).

- [ ] **Step 6: Commit Task 4**

```bash
rtk git add Sources/MacPortsControlCenter/Views/LogsView.swift Sources/MacPortsControlCenter/Views/DocsView.swift Tests/MacPortsControlCenterTests/AppStateTests.swift Tests/MacPortsControlCenterTests/TestRunnerMain.swift
rtk git commit -m "perf(views): replace log timer with kqueue DispatchSource and add MarkdownStyler fast-path cache"
```

---

### Task 5: Window Lifecycle Teardown (Keeping `.regular` Dock Icon), `MenuBarController` Deduplication, & View Virtualization (`PERF-07a`, `PERF-09a`, `PERF-10`, `PERF-13b`)

**Files:**
- Modify: `Sources/MacPortsControlCenterApp/MainApp.swift`
- Modify: `Sources/MacPortsControlCenter/Views/MainWindowView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/PackagesView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/DatabaseView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/PHPManagerView.swift`
- Modify: `Sources/MacPortsControlCenter/Views/SitesView.swift`
- Modify: `Sources/MacPortsControlCenter/Models/AppState.swift` (call `MarkdownStyler.clearCache()` inside `purgeTransientCachesForBackground()`)

**Interfaces:**
- Consumes: `AppState.isMySQLSocketConnected`, `AppState.installedDatabaseEngines`, `AppState.purgeTransientCachesForBackground()`, `MarkdownStyler.clearCache()`, `Notification.Name.mpccMainWindowDidClose`
- Produces:
  - `MenuBarController.StackStatus: Equatable` with cached `[StackStatus: NSImage]` and `CombineLatest3` deduplicated status pipeline
  - `AppDelegate` window teardown on `Cmd+W` preserving `.regular` Dock activation policy and lazy `NSWindow` reconstruction on Dock/Menu Bar reopen
  - `PackagesView` 200-item progressive display (`Load More`) + cancellable search `Task`

- [ ] **Step 1: Update `PackagesView.swift`, `DatabaseView.swift`, `PHPManagerView.swift`, `SitesView.swift`, and `MainWindowView.swift`**

1. `MainWindowView.swift`: remove redundant `.environmentObject(appState)` on line 100 (`AppDelegate.createAndShowMainWindow` already injects `.environmentObject(appState)` at the root `NSHostingView`).
2. `PackagesView.swift`:
   - Add `@State private var visibleLimit: Int = 200` and `@State private var searchTask: Task<Void, Never>? = nil`.
   - Reset `visibleLimit = 200` whenever `triggerSearch()`, clear search, or `selectedFilter` changes; cancel previous `searchTask` before starting a new one.
   - Render `ForEach(filteredPackages.prefix(visibleLimit))` inside `LazyVStack`, followed by a `"Load More (\(filteredPackages.count - visibleLimit) remaining)"` button (`visibleLimit += 200`) whenever `filteredPackages.count > visibleLimit`.
3. `DatabaseView.swift`:
   - Replace `DoctorService.isMySQLSocketPresent(...)` in `isSocketConnected` with `appState.isMySQLSocketConnected`.
   - Replace `FileManager.default.fileExists` and `appState.packages.contains` scans in `isEngineInstalled(portName:)` with `appState.installedDatabaseEngines.contains(portName) || appState.services.contains(where: { $0.name.contains(portName) || portName.contains($0.name) })`.
   - Replace regex in `CreateDatabaseSheet.isValidDbName` with `!trimmed.isEmpty && trimmed.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }`.
4. `PHPManagerView.swift`: load `tuning` asynchronously via `Task.detached` reading `php.ini` + `nginx.conf` off `@MainActor` inside `syncTuningWithSelection()` so clicking PHP version cards never blocks UI frames, and batch `"Restart All FPM Pools"` into a single `port reload` invocation when all target pools are already running (falling back per-pool `load` only for stopped pools).
5. `SitesView.swift`: change the virtual hosts container `VStack(spacing: 10)` (around line 168) to `LazyVStack(spacing: 10)`.
6. `AppState.swift`: add `MarkdownStyler.clearCache()` inside `purgeTransientCachesForBackground()`.

- [ ] **Step 2: Implement `MenuBarController` image cache & Combine deduplication + `AppDelegate` window teardown in `Sources/MacPortsControlCenterApp/MainApp.swift`**

1. Make `MenuBarController.StackStatus: CaseIterable, Equatable, Hashable`. Build `private lazy var statusImages: [StackStatus: NSImage]` once in `MenuBarController` instead of drawing a new `NSImage` on every state change.
2. Replace `appState.objectWillChange` in `observeAppState()` with:
   ```swift
   Publishers.CombineLatest3(appState.$services, appState.$isLoading, appState.commandRunner.$isRunning)
       .map { [weak self] services, isLoading, isRunning -> StackStatus in
           Self.computeStatus(services: services, isLoading: isLoading, isRunning: isRunning)
       }
       .removeDuplicates()
       .receive(on: DispatchQueue.main)
       .sink { [weak self] status in
           self?.applyStatusIndicator(status)
       }
       .store(in: &cancellables)
   ```
3. In `AppDelegate.applicationDidFinishLaunching`: set `state.isTerminalDrawerExpanded = false` right after `let state = AppState()` so the GUI starts with the drawer collapsed (until a mutating command auto-expands it).
4. In `AppDelegate.windowShouldClose(_ sender: NSWindow) -> Bool`:
   ```swift
   NotificationCenter.default.post(name: .mpccMainWindowDidClose, object: nil)
   sender.saveFrame(usingName: "MacPortsControlCenterMainWindow")
   sender.delegate = nil
   sender.contentView = nil
   sender.orderOut(nil)
   self.mainWindow = nil
   self.appState.purgeTransientCachesForBackground()
   // Keep NSApp.setActivationPolicy(.regular) so Dock icon stays visible!
   return false
   ```
5. In `AppDelegate.showMainWindow()`: if `self.mainWindow == nil`, call `createAndShowMainWindow()` (which creates the window, restores autosave frame, attaches `NSHostingView`, and orders front); otherwise deminiaturize if needed, `window.makeKeyAndOrderFront(nil)`, and `NSApp.activate(ignoringOtherApps: true)`.

- [ ] **Step 3: Verify both the unit test suite AND full executable compilation succeed**

Run the `swiftc` test command from **Global Constraints**, AND verify `MainApp.swift` compiles cleanly with all library files:
```bash
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"
swiftc -O -target "$(uname -m)-apple-macos12.0" -sdk "${SDK_PATH}" -whole-module-optimization -parse-as-library \
    Sources/MacPortsControlCenter/Models/*.swift \
    Sources/MacPortsControlCenter/Services/*.swift \
    Sources/MacPortsControlCenter/Views/*.swift \
    Sources/MacPortsControlCenterApp/MainApp.swift \
    -lsqlite3 -o /tmp/mpcc-verify-bin && rm -f /tmp/mpcc-verify-bin
```
Expected: PASS (`52/52` unit tests pass, zero warnings/errors on `MainApp.swift`).

- [ ] **Step 4: Commit Task 5**

```bash
rtk git add Sources/MacPortsControlCenter/Models/AppState.swift Sources/MacPortsControlCenter/Views/MainWindowView.swift Sources/MacPortsControlCenter/Views/PackagesView.swift Sources/MacPortsControlCenter/Views/DatabaseView.swift Sources/MacPortsControlCenter/Views/PHPManagerView.swift Sources/MacPortsControlCenter/Views/SitesView.swift Sources/MacPortsControlCenterApp/MainApp.swift
rtk git commit -m "perf(ui): tear down NSHostingView on close while keeping Dock icon, cache MenuBar images, and paginate packages"
```

---

### Task 6: Native Bundle Stripping, `AppIcon.icns` Compression, & Quantitative End-to-End Verification (`PERF-12`)

**Files:**
- Modify: `build-app.sh`
- Modify: `scripts/generate_icon.sh`
- Modify: `Resources/AppIcon.icns`

**Interfaces:**
- Consumes: all optimized `Sources/` targets, `/usr/bin/strip`, `/usr/bin/lipo`, `/usr/bin/sips`, `/usr/bin/iconutil`, `/usr/bin/codesign`
- Produces:
  - `./build-app.sh` supporting default host-native build (`uname -m`), `--universal` (`x86_64` + `arm64`), `--install`, `--user-install`, `-lsqlite3`, `-Xlinker -dead_strip`, and `strip -x` prior to ad-hoc codesigning
  - Compressed `Resources/AppIcon.icns` (`< 400 KB`) and `build/MacPorts Control Center.app` (`< 2.0 MB`)

- [ ] **Step 1: Update `scripts/generate_icon.sh` and re-pack `Resources/AppIcon.icns` to `< 400 KB`**

1. Update `scripts/generate_icon.sh` so after generating iconset PNGs via `sips`:
   - Strip embedded ICC color profiles (`for f in "${ICONSET_DIR}"/*.png; do sips --deleteColorManagementProperties "$f" >/dev/null; done`).
   - If `command -v pngquant >/dev/null 2>&1`, quantize all PNGs (`pngquant --quality=80-95 --ext .png --force "${ICONSET_DIR}"/*.png`); otherwise omit the 550 KB uncompressed `icon_512x512@2x.png` while retaining crisp Retina sizes up to `512×512` (`icon_256x256@2x.png` + `icon_512x512.png`).
2. Optimize the tracked `Resources/AppIcon.icns` in-place using `iconutil --convert iconset`, stripping ICC color management properties, applying the same rule, and repacking with `iconutil -c icns` into `Resources/AppIcon.icns`. Verify `ls -lh Resources/AppIcon.icns` is `< 400 KB` (`~374 KB`).

- [ ] **Step 2: Update `build-app.sh` with dynamic host architecture, `--universal`, `-lsqlite3`, `-dead_strip`, and `strip -x`**

In `build-app.sh`:
- Add `--universal` option flag (`UNIVERSAL=0` by default; `HOST_ARCH="$(uname -m)"`).
- Compile with `-lsqlite3 -Xlinker -dead_strip` (either single `-target "${HOST_ARCH}-apple-macos12.0"` when `UNIVERSAL=0`, or compiling both `x86_64-apple-macos12.0` and `arm64-apple-macos12.0` and merging via `lipo -create` when `UNIVERSAL=1`).
- Run `strip -x "${MACOS_DIR}/${BINARY_NAME}"` **before** `codesign --force --deep --sign - "${APP_BUNDLE}"`.

- [ ] **Step 3: Build `.app` bundle and verify bundle size, codesign, and unit test suite**

Run:
```bash
./build-app.sh
du -sh "build/MacPorts Control Center.app"
ls -lh "build/MacPorts Control Center.app/Contents/MacOS/MacPortsControlCenterApp"
codesign --verify --verbose "build/MacPorts Control Center.app"
TEST_RUNNER=1 /tmp/run-all-tests
```
Expected:
- Total `.app` size `< 2.0 MB` (`~1.8 – 1.9 MB`), binary size `~1.5 – 1.6 MB`
- `valid on disk` / `satisfies its Designated Requirement`
- `52/52` unit tests pass (`exit code 0`)

- [ ] **Step 4: Run quantitative Before-vs-After benchmark & live `vmmap` / `top` verification**

Compile a temporary benchmark harness in `/tmp/mpcc-bench-after` (`swiftc -O -whole-module-optimization -parse-as-library ... -lsqlite3`) measuring:
1. `MarkdownStyler.style` cold (`< 15 ms` on `AGENTS.md`) & `MarkdownStyler.cachedStyle` warm (`< 0.2 ms`)
2. Incremental `NSTextStorage` streaming 2,500 lines (`< 200 ms`)
3. `StreamCollector.appendData` 1,610 lines (`< 1.0 ms`)
4. `AppState.refreshAll()` end-to-end (`< 120 ms`, `terminalLines.count == 0`)
5. `AppState.searchPackages(query: "php")` end-to-end (`< 35 ms`, `terminalLines.count == 0`)
6. Launch `"build/MacPorts Control Center.app"` briefly (or install via `./build-app.sh --install` if updating `/Applications`), verify with `vmmap -summary <pid>` & `top -l 2 -pid <pid>` that active window footprint is `< 25 MB`, idle CPU is `0.0%`, and closing the window (`Cmd+W`) drops footprint to `< 14 MB` while keeping the Dock icon visible; clean up `/tmp/mpcc-bench-after` and `/tmp/run-all-tests`.

- [ ] **Step 5: Commit Task 6**

```bash
rtk git add build-app.sh scripts/generate_icon.sh Resources/AppIcon.icns
rtk git commit -m "perf(build): strip Mach-O linkedit symbols, support host/universal arch, and compress AppIcon.icns"
```
