#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation
#endif
import AppKit

@MainActor
final class AppStateTests: XCTestCase {
    func testCommandPaletteFilteringMatchesQuery() {
        let state = AppState(autoRefreshOnInit: false)
        let filtered = state.filteredPaletteCommands(query: "restart")
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.contains(where: { $0.title.localizedCaseInsensitiveContains("Restart") }))
    }

    func testCommandPaletteFilteringEmptyReturnsAll() {
        let state = AppState(autoRefreshOnInit: false)
        let all = state.filteredPaletteCommands(query: "")
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.count >= 7, "Should at least have commands for navigation and quick actions")
    }

    func testDocumentationFilesListLoadsRepositoryMarkdownFiles() {
        let state = AppState(autoRefreshOnInit: false)
        XCTAssertFalse(state.docFiles.isEmpty)
        XCTAssertTrue(state.docFiles.contains(where: { $0.fileName == "README.md" }))
    }

    func testNavigationSectionsEnumerationAndIdentification() {
        let sections = NavigationSection.allCases
        XCTAssertEqual(sections.count, 7)
        let rawValues = Set(sections.map { $0.rawValue })
        XCTAssertTrue(rawValues.contains("services"))
        XCTAssertTrue(rawValues.contains("sites"))
        XCTAssertTrue(rawValues.contains("php"))
        XCTAssertTrue(rawValues.contains("database"))
        XCTAssertTrue(rawValues.contains("packages"))
        XCTAssertTrue(rawValues.contains("logs"))
        XCTAssertTrue(rawValues.contains("docs"))

        for section in sections {
            XCTAssertEqual(section.id, section.rawValue)
            XCTAssertFalse(section.displayName.isEmpty)
            XCTAssertFalse(section.systemImage.isEmpty)
        }
    }

    func testInitialStateProperties() {
        let state = AppState(autoRefreshOnInit: false)
        XCTAssertEqual(state.selectedSection, .services)
        XCTAssertFalse(state.isCommandPalettePresented)
        XCTAssertTrue(state.isTerminalDrawerExpanded)
        XCTAssertTrue(state.services.isEmpty)
        XCTAssertTrue(state.vhosts.isEmpty)
        XCTAssertTrue(state.phpVersions.isEmpty)
        XCTAssertTrue(state.databases.isEmpty)
        XCTAssertTrue(state.packages.isEmpty)
        XCTAssertTrue(state.portSelectGroups.isEmpty)
        XCTAssertTrue(state.doctorChecks.isEmpty)
    }

    func testLoadDocContentLoadsValidMarkdown() {
        let state = AppState(autoRefreshOnInit: false)
        guard let readmeDoc = state.docFiles.first(where: { $0.fileName == "README.md" }) else {
            XCTFail("README.md should be in docFiles")
            return
        }
        let content = state.loadDocContent(doc: readmeDoc)
        XCTAssertFalse(content.isEmpty)
        XCTAssertTrue(content.contains("MacPorts") || content.contains("#"))
    }

    func testWriteConfigFileDirectSuccess() async {
        let state = AppState(autoRefreshOnInit: false)
        let tempTarget = (NSTemporaryDirectory() as NSString).appendingPathComponent("test_write_\(UUID().uuidString).conf")
        defer { try? FileManager.default.removeItem(atPath: tempTarget) }

        await state.writeConfigFile(content: "user = test\ngroup = staff", targetPath: tempTarget)
        let readBack = try? String(contentsOfFile: tempTarget, encoding: .utf8)
        XCTAssertEqual(readBack, "user = test\ngroup = staff")
    }

    func testWriteConfigFileFallsBackToSudoCpOnWriteError() async {
        let state = AppState(autoRefreshOnInit: false)
        // A destination where user has no write permission
        let unwritableTarget = "/opt/local/etc/non_existent_dir_\(UUID().uuidString)/www.conf"

        await state.writeConfigFile(content: "user = adijaya\ngroup = staff", targetPath: unwritableTarget)
        // CommandRunner should have recorded a sudo -n /bin/cp attempt
        let ranCp = state.commandRunner.terminalLines.contains { line in
            line.contains("sudo -n /bin/cp") && line.contains(unwritableTarget)
        }
        XCTAssertTrue(ranCp, "Expected sudo -n /bin/cp command to be invoked when direct write fails")
    }

    func testVHostAndStoragePermissionHelpers() async {
        let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("vhost_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let state = AppState(autoRefreshOnInit: false, nginxServersPath: tempDir)
        let sampleVHost = VHostItem(
            id: "sample.conf",
            fileName: "sample.conf",
            filePath: "\(tempDir)/sample.conf",
            listenPort: "8088",
            serverName: "sample.test",
            rootPath: "/Users/adijaya/Projects/sample/public",
            fastcgiPass: "127.0.0.1:9000",
            sslEnabled: false
        )

        // Fix storage permissions creates correct chmod command
        await state.fixStoragePermissions(for: sampleVHost)
        let ranChmod = state.commandRunner.terminalLines.contains { line in
            line.contains("chmod -R u+rwX") && line.contains("/Users/adijaya/Projects/sample/storage")
        }
        XCTAssertTrue(ranChmod, "Expected fixStoragePermissions to invoke chmod on storage and bootstrap/cache")

        // Write a test vhost file and verify deleteVHost removes it
        let testFile = "\(tempDir)/sample.conf"
        try? "server { listen 8088; }".write(toFile: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile))

        await state.deleteVHost(fileName: "sample.conf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile), "deleteVHost should remove the conf file")
    }

    func testQuickTuningLoad() {
        let state = AppState(autoRefreshOnInit: false)
        let tuning = state.loadQuickTuning(version: "8.3")
        XCTAssertFalse(tuning.memoryLimit.isEmpty)
        XCTAssertFalse(tuning.uploadMaxFilesize.isEmpty)
        XCTAssertFalse(tuning.postMaxSize.isEmpty)
        XCTAssertFalse(tuning.maxExecutionTime.isEmpty)
        XCTAssertFalse(tuning.nginxClientMaxBodySize.isEmpty)
    }

    func testPHPUninstallAndEcosystemCommands() async {
        let state = AppState(autoRefreshOnInit: false)
        await state.uninstallPHPVersion("8.2")
        let ranUninstall = state.commandRunner.terminalLines.contains { line in
            line.contains("port -N uninstall --follow-dependents php82")
        }
        XCTAssertTrue(ranUninstall, "Expected uninstallPHPVersion to call port -N uninstall --follow-dependents")

        let ranLeaves = state.commandRunner.terminalLines.contains { line in
            line.contains("port -N uninstall leaves")
        }
        XCTAssertTrue(ranLeaves, "Expected uninstallPHPVersion to clean leaves")
    }

    func testSetupDnsmasqUsesOsascriptAdminCommand() async {
        let state = AppState(autoRefreshOnInit: false)
        await state.setupDnsmasq()
        let ranOsascript = state.commandRunner.terminalLines.contains { line in
            line.contains("osascript") && line.contains("/etc/resolver/test")
        }
        XCTAssertTrue(ranOsascript, "Expected setupDnsmasq to use osascript for /etc/resolver/test")
    }

    // MARK: - Task 7 Views & Actions Tests

    func testDatabaseEngineInstallAndLifecycle() async {
        let state = AppState(autoRefreshOnInit: false)
        await state.installDatabaseEngine(portName: "mariadb-11.4-server")
        let ranInstall = state.commandRunner.terminalLines.contains { line in
            line.contains("port install mariadb-11.4-server") && line.contains("port load mariadb-11.4-server")
        }
        XCTAssertTrue(ranInstall, "Expected installDatabaseEngine to install and load the database port")
    }

    func testDatabaseCreateDropDumpImportCommands() async {
        let state = AppState(autoRefreshOnInit: false)
        await state.createDatabase(name: "test_new_db")
        let ranCreate = state.commandRunner.terminalLines.contains { line in
            line.contains("CREATE DATABASE IF NOT EXISTS `test_new_db`")
        }
        XCTAssertTrue(ranCreate, "Expected createDatabase to invoke CREATE DATABASE statement")

        await state.dropDatabase(name: "test_new_db")
        let ranDrop = state.commandRunner.terminalLines.contains { line in
            line.contains("DROP DATABASE IF EXISTS `test_new_db`")
        }
        XCTAssertTrue(ranDrop, "Expected dropDatabase to invoke DROP DATABASE statement")

        await state.dumpDatabase(name: "test_db", outputPath: "/tmp/test.sql")
        let ranDump = state.commandRunner.terminalLines.contains { line in
            line.contains("mysqldump") && line.contains("test_db") && line.contains("/tmp/test.sql")
        }
        XCTAssertTrue(ranDump, "Expected dumpDatabase to invoke mysqldump")

        await state.importDatabase(name: "test_db", inputPath: "/tmp/test.sql")
        let ranImport = state.commandRunner.terminalLines.contains { line in
            line.contains("mysql") && line.contains("test_db") && line.contains("/tmp/test.sql")
        }
        XCTAssertTrue(ranImport, "Expected importDatabase to invoke mysql with input redirection")
    }

    func testPackageLifecycleActionsAndPortSelect() async {
        let state = AppState(autoRefreshOnInit: false)

        await state.installPackage(name: "htop")
        let ranInstall = state.commandRunner.terminalLines.contains { line in
            line.contains("port install htop")
        }
        XCTAssertTrue(ranInstall, "Expected installPackage to call port install htop")

        await state.activatePackage(name: "php83", version: "@8.3.36_0")
        let ranActivate = state.commandRunner.terminalLines.contains { line in
            line.contains("port activate php83 @8.3.36_0")
        }
        XCTAssertTrue(ranActivate, "Expected activatePackage to include port name and @version")

        await state.deactivatePackage(name: "php83", version: "8.3.36_0")
        let ranDeactivate = state.commandRunner.terminalLines.contains { line in
            line.contains("port deactivate php83 @8.3.36_0")
        }
        XCTAssertTrue(ranDeactivate, "Expected deactivatePackage to format version with @ prefix")

        await state.uninstallPackage(name: "curl", version: "@8.7.1_0")
        let ranUninstall = state.commandRunner.terminalLines.contains { line in
            line.contains("port -N uninstall curl @8.7.1_0")
        }
        XCTAssertTrue(ranUninstall, "Expected uninstallPackage to call port -N uninstall with version")

        await state.upgradePackage(name: "nginx")
        let ranUpgrade = state.commandRunner.terminalLines.contains { line in
            line.contains("port upgrade nginx")
        }
        XCTAssertTrue(ranUpgrade, "Expected upgradePackage to call port upgrade")
    }

    func testMarkdownStylerRenderingAndAttributes() {
        let sampleMarkdown = """
        # Heading 1
        This is a **bold text** and *italic*.

        ```bash
        sudo port install mariadb
        ```

        - Item 1
        - Item 2

        1. First step
        2. Second step

        > [!NOTE]
        > Important context note for developer &rarr; details.

        > [!WARNING]
        > Caution when stopping services.
        """

        let styled = MarkdownStyler.style(sampleMarkdown)
        XCTAssertTrue(styled.length > 0, "Styled markdown string should not be empty")
        XCTAssertTrue(styled.string.contains("Heading 1"))
        XCTAssertTrue(styled.string.contains("Item 1"))
        XCTAssertTrue(styled.string.contains("1. First step"))
        XCTAssertTrue(styled.string.contains("2. Second step"))
        XCTAssertTrue(styled.string.contains("📘 NOTE"))
        XCTAssertTrue(styled.string.contains("Important context note for developer → details."))
        XCTAssertTrue(styled.string.contains("🛑 WARNING"))
        XCTAssertTrue(styled.string.contains("sudo port install mariadb"))

        let tableMarkdown = """
        | Service | Port |
        | :--- | :--- |
        | Nginx | 80 |
        """
        let styledTable = MarkdownStyler.style(tableMarkdown)
        XCTAssertTrue(styledTable.string.contains("Service"))
        XCTAssertTrue(styledTable.string.contains("Port"))
        XCTAssertTrue(styledTable.string.contains("Nginx"))
        XCTAssertTrue(styledTable.string.contains("80"))

        var foundTableBlock = false
        styledTable.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: styledTable.length)) { value, _, stop in
            if let p = value as? NSParagraphStyle, !p.textBlocks.isEmpty {
                foundTableBlock = true
                stop.pointee = true
            }
        }
        XCTAssertTrue(foundTableBlock, "Expected native NSTextTableBlock in styled table")

        // Multi-line wrapped table with links and breaks
        let complexTableMarkdown = """
        | Col A | Col B |
        | :--- | :--- |
        | [Link A](http://example.com) | Line 1<br>Line 2 with very long descriptive sentence that exceeds width |
        """
        let styledComplexTable = MarkdownStyler.style(complexTableMarkdown)
        XCTAssertTrue(styledComplexTable.string.contains("Link A"))
        XCTAssertTrue(styledComplexTable.string.contains("Line 1"))
        XCTAssertTrue(styledComplexTable.string.contains("Line 2"))

        // Verify DocsScrollView enables scrolling for long document
        let sv = DocsScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        sv.documentView = textView
        textView.textStorage?.setAttributedString(styled)
        sv.layout()
        XCTAssertTrue(sv.verticalScroller != nil)
    }

    func testLogViewTabsAndPaths() {
        let tabs = LogTypeTab.allCases
        XCTAssertEqual(tabs.count, 4)
        XCTAssertEqual(tabs[0], .nginxError)
        XCTAssertEqual(tabs[1], .nginxAccess)
        XCTAssertEqual(tabs[2], .phpFpm)
        XCTAssertEqual(tabs[3], .mariaDB)

        for tab in tabs {
            XCTAssertFalse(tab.rawValue.isEmpty)
            XCTAssertFalse(tab.icon.isEmpty)
        }
    }

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
}
