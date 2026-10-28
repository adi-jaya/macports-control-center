#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation

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
}
