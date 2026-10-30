import Foundation
import SQLite3

#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}

public func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    guard a == b else {
        fatalError("Assertion failed: (\"\(a)\") is not equal to (\"\(b)\") - \(msg) at \(file):\(line)")
    }
}

public func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    guard a != b else {
        fatalError("Assertion failed: (\"\(a)\") is equal to (\"\(b)\") - \(msg) at \(file):\(line)")
    }
}

public func XCTAssertTrue(_ cond: Bool, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    guard cond else {
        fatalError("Assertion failed: expected true - \(msg) at \(file):\(line)")
    }
}

public func XCTAssertFalse(_ cond: Bool, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    guard !cond else {
        fatalError("Assertion failed: expected false - \(msg) at \(file):\(line)")
    }
}

public func XCTAssertNotNil<T>(_ val: T?, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    guard val != nil else {
        fatalError("Assertion failed: expected non-nil - \(msg) at \(file):\(line)")
    }
}

public func XCTAssertNil<T>(_ val: T?, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    guard val == nil else {
        fatalError("Assertion failed: expected nil - \(msg) at \(file):\(line)")
    }
}

public func XCTFail(_ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    fatalError("Test failed: \(msg) at \(file):\(line)")
}
#endif

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
        None of the specified ports are installed.
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

    func testParseOutdatedPorts() {
        let sample = """
        The following installed ports are outdated:
        curl                           8.22.0_0 < 8.23.0_0
        php83                          8.3.35_0 < 8.3.36_0
        """
        let outdated = MacPortsService.parseOutdatedPorts(sample)
        XCTAssertEqual(outdated, Set(["curl", "php83"]))

        let empty = MacPortsService.parseOutdatedPorts("No installed ports are outdated.\n")
        XCTAssertTrue(empty.isEmpty)
    }

    func testSupportedPHPExtensionSubportsAndBuiltInCoreModules() {
        XCTAssertEqual(MacPortsService.supportedPHPExtensionSubports.count, 20)
        XCTAssertTrue(MacPortsService.supportedPHPExtensionSubports.contains("mysql"))
        XCTAssertTrue(MacPortsService.supportedPHPExtensionSubports.contains("sodium"))
        XCTAssertEqual(MacPortsService.builtInPHPCoreModules.count, 8)
        XCTAssertTrue(MacPortsService.builtInPHPCoreModules.contains("bcmath"))
        XCTAssertTrue(MacPortsService.builtInPHPCoreModules.contains("phar"))
    }

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

        let emptyTargetsResult = MacPortsService.searchPortsNativeIndex(
            query: "php",
            indexPaths: [],
            installed: [:],
            outdated: []
        )
        XCTAssertNil(emptyTargetsResult, "Empty targets must return nil to trigger CLI fallback")
    }
}
