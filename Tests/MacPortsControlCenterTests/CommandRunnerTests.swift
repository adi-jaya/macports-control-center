#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation
#endif

@MainActor
final class CommandRunnerTests: XCTestCase {
    func testStreamsOutputLinesAndRecordsExitCode() async {
        let runner = CommandRunner()
        let result = await runner.runShell("printf 'line1\\nline2\\n'", label: "test-echo", serialized: false)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(runner.terminalLines.contains(where: { $0.contains("line1") }))
        XCTAssertTrue(runner.terminalLines.contains(where: { $0.contains("line2") }))
    }

    func testStreamsMultiByteUTF8AcrossChunkBoundaries() async {
        let runner = CommandRunner()
        let result = await runner.runShell("printf '🚀 rocket\\n✨ sparkles\\n'", label: "utf8-test", serialized: false)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("🚀 rocket"))
        XCTAssertTrue(result.stdout.contains("✨ sparkles"))
        XCTAssertTrue(runner.terminalLines.contains(where: { $0.contains("🚀 rocket") }))
        XCTAssertTrue(runner.terminalLines.contains(where: { $0.contains("✨ sparkles") }))
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

    func testConcurrentNonSerializedMaintainsIsRunningUntilAllFinish() async {
        let runner = CommandRunner()
        async let shortTask = runner.runShell("sleep 0.05", label: "short", serialized: false)
        async let longTask = runner.runShell("sleep 0.15", label: "long", serialized: false)

        _ = await shortTask
        XCTAssertTrue(runner.isRunning, "isRunning must remain true while longTask is still executing")
        XCTAssertEqual(runner.currentCommandLabel, "long")

        _ = await longTask
        XCTAssertFalse(runner.isRunning, "isRunning must become false after all tasks finish")
        XCTAssertEqual(runner.currentCommandLabel, "")
    }

    func testCancelTerminatesAllActiveConcurrentProcesses() async {
        let runner = CommandRunner()
        let taskA = Task { await runner.runShell("sleep 10", label: "cancelA", serialized: false) }
        let taskB = Task { await runner.runShell("sleep 10", label: "cancelB", serialized: false) }
        try? await Task.sleep(nanoseconds: 50_000_000)

        runner.cancelCurrentProcess()
        let resA = await taskA.value
        let resB = await taskB.value
        XCTAssertNotEqual(resA.exitCode, 0)
        XCTAssertNotEqual(resB.exitCode, 0)
        XCTAssertFalse(runner.isRunning)
    }

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
}
