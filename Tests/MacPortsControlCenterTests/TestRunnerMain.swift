#if !canImport(XCTest)
import Foundation

@main
struct TestRunnerMain {
    static func main() {
        print("Running MacPortsServiceTests...")
        let tests = MacPortsServiceTests()
        tests.setUp()
        tests.testParsePortSelectSummaryExtractsAllGroups()
        tests.tearDown()

        tests.setUp()
        tests.testParseInstalledAndSearchOutputHandlesMultiVersionPorts()
        tests.tearDown()

        tests.setUp()
        tests.testDiscoverLaunchDaemonsMatchesRealMacPortsPsOutput()
        tests.tearDown()

        tests.setUp()
        tests.testParseOutdatedPorts()
        tests.tearDown()

        tests.setUp()
        tests.testSupportedPHPExtensionSubportsAndBuiltInCoreModules()
        tests.tearDown()

        print("All MacPortsServiceTests passed successfully (5/5 tests)")
    }
}
#endif
