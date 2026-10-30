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

        tests.setUp()
        tests.testReadInstalledPortsSQLiteStripsQuotesAndDistinguishesActiveState()
        tests.tearDown()

        tests.setUp()
        do {
            try tests.testReadPortSelectGroupsFilesystemPlacesNoneLastAndHandlesMissingCurrent()
        } catch {
            fatalError("testReadPortSelectGroupsFilesystemPlacesNoneLastAndHandlesMissingCurrent failed: \(error)")
        }
        tests.tearDown()

        tests.setUp()
        do {
            try tests.testSearchPortsNativeIndexHandlesNestedTclBracesAndFallsBackOnGlob()
        } catch {
            fatalError("testSearchPortsNativeIndexHandlesNestedTclBracesAndFallsBackOnGlob failed: \(error)")
        }
        tests.tearDown()

        print("All MacPortsServiceTests passed successfully (8/8 tests)")

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

        cmdTests.setUp()
        cmdTests.testStreamCollectorCursorScanAndSplitDisabledMode()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testQuietModeSkipsTerminalLinesAndIsRunningState()
        cmdTests.tearDown()

        cmdTests.setUp()
        await cmdTests.testCoalescedStreamingPreservesAllLinesImmediatelyUponReturn()
        cmdTests.tearDown()

        cmdTests.setUp()
        cmdTests.testStreamCollectorFinishSplitsMultiLineRemainingData()
        cmdTests.tearDown()

        print("All CommandRunnerTests passed successfully (10/10 tests)")

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

        appStateTests.setUp()
        await appStateTests.testWriteConfigFileDirectSuccess()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testWriteConfigFileFallsBackToSudoCpOnWriteError()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testVHostAndStoragePermissionHelpers()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testQuickTuningLoad()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testPHPUninstallAndEcosystemCommands()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testSetupDnsmasqUsesOsascriptAdminCommand()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testDatabaseEngineInstallAndLifecycle()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testDatabaseCreateDropDumpImportCommands()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testPackageLifecycleActionsAndPortSelect()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testMarkdownStylerRenderingAndAttributes()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testLogViewTabsAndPaths()
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testPaletteCommandsUseDeterministicStableIDs()
        appStateTests.tearDown()

        appStateTests.setUp()
        await appStateTests.testAutoExpandDrawerOnMutationAndQuietPollingIsolation()
        appStateTests.tearDown()

        appStateTests.setUp()
        do {
            try appStateTests.testLogFileTailerAdvancesToCleanNewlineBoundaryOnLargeUTF8File()
        } catch {
            fatalError("testLogFileTailerAdvancesToCleanNewlineBoundaryOnLargeUTF8File failed: \(error)")
        }
        appStateTests.tearDown()

        appStateTests.setUp()
        appStateTests.testMarkdownStylerCacheHitAndClear()
        appStateTests.tearDown()

        print("All AppStateTests passed successfully (21/21 tests)")
    }
}
#endif
