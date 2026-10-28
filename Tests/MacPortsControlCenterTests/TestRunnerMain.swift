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
        await cmdTests.testStreamsMultiByteUTF8AcrossChunkBoundaries()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testSerializedQueueRunsCommandsSequentially()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testCancelCurrentProcessTerminatesLongRunningTask()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testConcurrentNonSerializedMaintainsIsRunningUntilAllFinish()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testCancelTerminatesAllActiveConcurrentProcesses()
        cmdTests.tearDown()

        print("All CommandRunnerTests passed successfully (6/6 tests)")

        print("Running ConfigFileServiceTests...")
        let configTests = ConfigFileServiceTests()
        configTests.setUp()
        configTests.testParseAndUpdateIgnoresCommentedDirectives()
        configTests.tearDown()

        configTests.setUp()
        configTests.testConfigureFPMWwwConfSetsUserAndUniquePort()
        configTests.tearDown()

        configTests.setUp()
        do {
            try configTests.testParseLaravelEnvHandlesQuotesAndComments()
        } catch {
            fatalError("testParseLaravelEnvHandlesQuotesAndComments failed: \(error)")
        }
        configTests.tearDown()

        configTests.setUp()
        configTests.testIsNginxTestOutputValidHandlesNonRootPidWarningAndRejectsSyntaxErrors()
        configTests.tearDown()

        configTests.setUp()
        do {
            try await configTests.testSaveVHostRollsBackWhenValidatorFails()
        } catch {
            fatalError("testSaveVHostRollsBackWhenValidatorFails failed: \(error)")
        }
        configTests.tearDown()

        configTests.setUp()
        do {
            try configTests.testGenerateAndParseLaravelVHost()
        } catch {
            fatalError("testGenerateAndParseLaravelVHost failed: \(error)")
        }
        configTests.tearDown()

        configTests.setUp()
        do {
            try configTests.testGenerateAndParseSPAVHostWithSSL()
        } catch {
            fatalError("testGenerateAndParseSPAVHostWithSSL failed: \(error)")
        }
        configTests.tearDown()

        configTests.setUp()
        configTests.testParseRealHostConfigsIfPresent()
        configTests.tearDown()

        print("All ConfigFileServiceTests passed successfully (8/8 tests)")

        print("Running DoctorAndDatabaseTests...")
        let doctorDbTests = DoctorAndDatabaseTests()
        doctorDbTests.setUp()
        doctorDbTests.testParseShowDatabasesFiltersHeaderAndSystemSchemas()
        doctorDbTests.tearDown()

        doctorDbTests.setUp()
        doctorDbTests.testBuildDumpAndImportCommandsUseSocketAndSafeQuoting()
        doctorDbTests.tearDown()

        doctorDbTests.setUp()
        doctorDbTests.testDoctorServiceEvaluatesAllFiveGuardrailChecksAndBuildsAutoFixScript()
        doctorDbTests.tearDown()

        doctorDbTests.setUp()
        doctorDbTests.testDoctorServiceOsascriptCommandAndStoragePermissionsCommand()
        doctorDbTests.tearDown()

        doctorDbTests.setUp()
        doctorDbTests.testDoctorServiceEdgeCasesAllHealthyAndSocketLogic()
        doctorDbTests.tearDown()

        doctorDbTests.setUp()
        doctorDbTests.testDatabaseServiceSpecialCharactersAndEmptyOutputs()
        doctorDbTests.tearDown()

        print("All DoctorAndDatabaseTests passed successfully (6/6 tests)")

        print("Running AppStateTests...")
        let appStateTests = AppStateTests()
        appStateTests.setUp()
        appStateTests.testCommandPaletteFilteringMatchesQuery()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testCommandPaletteFilteringEmptyReturnsAll()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testDocumentationFilesListLoadsRepositoryMarkdownFiles()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testNavigationSectionsEnumerationAndIdentification()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testInitialStateProperties()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testLoadDocContentLoadsValidMarkdown()
        appStateTests.tearDown()

        print("All AppStateTests passed successfully (6/6 tests)")
    }
}
#endif
