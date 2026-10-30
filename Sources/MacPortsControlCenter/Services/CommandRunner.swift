import Foundation

// MARK: - Stream Collector
final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var allBytes = Data()
    private var byteBuffer = Data()
    private let splitLines: Bool

    init(splitLines: Bool = true) {
        self.splitLines = splitLines
    }

    func appendData(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }

        allBytes.append(data)
        guard splitLines else { return [] }

        byteBuffer.append(data)

        var lines: [String] = []
        let newlineByte = UInt8(ascii: "\n")
        let crByte = UInt8(ascii: "\r")

        var lineStart = 0
        let count = byteBuffer.count

        byteBuffer.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<count {
                if ptr[i] == newlineByte {
                    var lineEnd = i
                    if lineEnd > lineStart && ptr[lineEnd - 1] == crByte {
                        lineEnd -= 1
                    }
                    let lineData = Data(bytes: ptr + lineStart, count: lineEnd - lineStart)
                    lines.append(String(decoding: lineData, as: UTF8.self))
                    lineStart = i + 1
                }
            }
        }

        if lineStart == 0 {
            // No newlines found, keep byteBuffer as is
        } else if lineStart < count {
            byteBuffer = Data(byteBuffer[lineStart...])
        } else {
            byteBuffer = Data()
        }

        return lines
    }

    func finish(remainingData: Data? = nil) -> (output: String, finalLines: [String]) {
        lock.lock()
        defer { lock.unlock() }

        if let data = remainingData, !data.isEmpty {
            allBytes.append(data)
            if splitLines {
                byteBuffer.append(data)
            }
        }

        var lines: [String] = []
        if splitLines && !byteBuffer.isEmpty {
            var remaining = byteBuffer
            if let lastByte = remaining.last, lastByte == UInt8(ascii: "\r") {
                remaining = remaining.dropLast()
            }
            let str = String(decoding: remaining, as: UTF8.self)
            if !str.isEmpty {
                lines.append(str)
            }
            byteBuffer = Data()
        }

        let output = String(decoding: allBytes, as: UTF8.self)
        return (output, lines)
    }
}

// MARK: - Line Accumulator
final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []

    func append(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        lock.lock()
        buffer.append(contentsOf: lines)
        lock.unlock()
    }

    func drain() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let current = buffer
        buffer.removeAll(keepingCapacity: true)
        return current
    }
}

// MARK: - Command Result
public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

// MARK: - Command Runner
@MainActor
public final class CommandRunner: ObservableObject {
    @Published public private(set) var terminalLines: [String] = []
    @Published public private(set) var terminalGeneration: Int = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentCommandLabel: String = ""

    public var onMutationCommandStart: (() -> Void)? = nil

    private var activeProcesses: [UUID: (process: Process, label: String)] = [:]
    private var queueTail: Task<Void, Never>? = nil
    private var queueTailToken: UUID? = nil
    private var pendingLines: [String] = []
    private let maxTerminalLines = 5000

    public init() {}

    public func clearLog() {
        terminalLines.removeAll()
        pendingLines.removeAll()
        terminalGeneration += 1
    }

    public func cancelCurrentProcess() {
        for (_, entry) in activeProcesses {
            if entry.process.isRunning {
                entry.process.terminate()
            }
        }
    }

    public func runShell(
        _ command: String,
        label: String,
        serialized: Bool = true,
        logToTerminal: Bool = true
    ) async -> CommandResult {
        return await run(
            executable: "/bin/zsh",
            arguments: ["-c", command],
            label: label,
            serialized: serialized,
            logToTerminal: logToTerminal
        )
    }

    public func run(
        executable: String,
        arguments: [String],
        label: String,
        serialized: Bool = true,
        logToTerminal: Bool = true,
        onLine: ((String) -> Void)? = nil
    ) async -> CommandResult {
        if !serialized {
            return await execute(
                executable: executable,
                arguments: arguments,
                label: label,
                logToTerminal: logToTerminal,
                onLine: onLine
            )
        }

        let myToken = UUID()
        queueTailToken = myToken
        let prev = queueTail
        let task = Task<CommandResult, Never> { [prev] in
            if let prev = prev {
                _ = await prev.value
            }
            return await self.execute(
                executable: executable,
                arguments: arguments,
                label: label,
                logToTerminal: logToTerminal,
                onLine: onLine
            )
        }
        queueTail = Task { @MainActor [weak self] in
            _ = await task.value
            guard let self = self else { return }
            if self.queueTailToken == myToken {
                self.queueTail = nil
                self.queueTailToken = nil
            }
        }
        return await task.value
    }

    private func appendLines(_ lines: [String], logToTerminal: Bool = true, onLine: ((String) -> Void)? = nil) {
        guard !lines.isEmpty else { return }
        if logToTerminal {
            terminalLines.append(contentsOf: lines)
            if terminalLines.count > 5500 {
                terminalLines.removeFirst(terminalLines.count - maxTerminalLines)
                terminalGeneration += 1
            }
        }
        if let onLine = onLine {
            for line in lines {
                onLine(line)
            }
        }
    }

    private func execute(
        executable: String,
        arguments: [String],
        label: String,
        logToTerminal: Bool,
        onLine: ((String) -> Void)?
    ) async -> CommandResult {
        let isQuiet = !logToTerminal && onLine == nil

        if logToTerminal {
            onMutationCommandStart?()
        }

        if !isQuiet {
            let cmdDisplay: String
            if executable == "/bin/zsh" && arguments.count >= 2 && arguments[0] == "-c" {
                cmdDisplay = "$ \(arguments[1])"
            } else {
                let argsStr = arguments.joined(separator: " ")
                cmdDisplay = argsStr.isEmpty ? "$ \(executable)" : "$ \(executable) \(argsStr)"
            }
            appendLines([cmdDisplay], logToTerminal: logToTerminal, onLine: onLine)
        }

        if ProcessInfo.processInfo.environment["TEST_RUNNER"] == "1" {
            let fullCommand = arguments.joined(separator: " ")
            if executable == "/usr/bin/osascript" ||
               fullCommand.contains("/opt/local/bin/port ") ||
               fullCommand.contains("port ") ||
               fullCommand.contains("CREATE DATABASE") ||
               fullCommand.contains("DROP DATABASE") ||
               fullCommand.contains("mysqldump") ||
               fullCommand.contains("mysql ") {
                return CommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let runID = UUID()
        if logToTerminal {
            activeProcesses[runID] = (process, label)
            isRunning = true
            currentCommandLabel = label
        }

        defer {
            if logToTerminal {
                activeProcesses.removeValue(forKey: runID)
                if let remaining = activeProcesses.values.first {
                    currentCommandLabel = remaining.label
                    isRunning = true
                } else {
                    currentCommandLabel = ""
                    isRunning = false
                }
            }
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSHomeDirectory())/.local/bin"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        if isQuiet {
            let stdoutCollector = StreamCollector(splitLines: false)
            let stderrCollector = StreamCollector(splitLines: false)

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                _ = stdoutCollector.appendData(data)
            }

            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                _ = stderrCollector.appendData(data)
            }

            do {
                try process.run()
            } catch {
                let errMsg = error.localizedDescription
                return CommandResult(exitCode: 127, stdout: "", stderr: errMsg)
            }

            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil

            let remainingStdout = stdoutHandle.readDataToEndOfFile()
            let remainingStderr = stderrHandle.readDataToEndOfFile()

            let (stdoutString, _) = stdoutCollector.finish(remainingData: remainingStdout)
            let (stderrString, _) = stderrCollector.finish(remainingData: remainingStderr)

            return CommandResult(
                exitCode: process.terminationStatus,
                stdout: stdoutString,
                stderr: stderrString
            )
        }

        let stdoutCollector = StreamCollector(splitLines: true)
        let stderrCollector = StreamCollector(splitLines: true)

        let pipeQueue = DispatchQueue(label: "mpcc.pipe.\(runID)")
        let accumulator = LineAccumulator()

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            pipeQueue.async {
                let lines = stdoutCollector.appendData(data)
                if !lines.isEmpty {
                    accumulator.append(lines)
                }
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            pipeQueue.async {
                let lines = stderrCollector.appendData(data)
                if !lines.isEmpty {
                    accumulator.append(lines)
                }
            }
        }

        let flushTimer = DispatchSource.makeTimerSource(queue: .main)
        flushTimer.schedule(deadline: .now() + .milliseconds(33), repeating: .milliseconds(33))
        flushTimer.setEventHandler { [weak self] in
            let toFlush = accumulator.drain()
            if !toFlush.isEmpty {
                self?.appendLines(toFlush, logToTerminal: logToTerminal, onLine: onLine)
            }
        }
        flushTimer.resume()

        do {
            try process.run()
        } catch {
            flushTimer.cancel()
            let errMsg = error.localizedDescription
            appendLines(["Error: \(errMsg)"], logToTerminal: logToTerminal, onLine: onLine)
            return CommandResult(exitCode: 127, stdout: "", stderr: errMsg)
        }

        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        flushTimer.cancel()

        pipeQueue.sync {}

        let remainingStdout = stdoutHandle.readDataToEndOfFile()
        let remainingStderr = stderrHandle.readDataToEndOfFile()

        let (stdoutString, finalStdoutLines) = stdoutCollector.finish(remainingData: remainingStdout)
        let (stderrString, finalStderrLines) = stderrCollector.finish(remainingData: remainingStderr)

        var allRemaining = accumulator.drain()
        allRemaining.append(contentsOf: finalStdoutLines)
        allRemaining.append(contentsOf: finalStderrLines)

        if !allRemaining.isEmpty {
            appendLines(allRemaining, logToTerminal: logToTerminal, onLine: onLine)
        }

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdoutString,
            stderr: stderrString
        )
    }
}
