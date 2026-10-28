#if !canImport(XCTest)
import Foundation

@main
struct TestRunnerMain {
    @MainActor
    static func main() async {
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

        print("Running CommandRunnerTests...")
        let cmdTests = CommandRunnerTests()
        cmdTests.setUp()
        await cmdTests.testStreamsOutputLinesAndRecordsExitCode()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testSerializedQueueRunsCommandsSequentially()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testCancelCurrentProcessTerminatesLongRunningTask()
        cmdTests.tearDown()

        print("All CommandRunnerTests passed successfully (3/3 tests)")
    }
}
#endif
