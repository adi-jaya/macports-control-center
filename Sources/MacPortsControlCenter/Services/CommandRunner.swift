import Foundation

// MARK: - Stream Collector
final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var allBytes = Data()
    private var byteBuffer = Data()

    func appendData(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }

        allBytes.append(data)
        byteBuffer.append(data)

        var lines: [String] = []
        let newlineByte = UInt8(ascii: "\n")
        let crByte = UInt8(ascii: "\r")

        while let newlineIndex = byteBuffer.firstIndex(of: newlineByte) {
            var lineData = byteBuffer[..<newlineIndex]
            if let lastByte = lineData.last, lastByte == crByte {
                lineData = lineData.dropLast()
            }
            lines.append(String(decoding: lineData, as: UTF8.self))
            byteBuffer = Data(byteBuffer[(newlineIndex + 1)...])
        }

        return lines
    }

    func finish(remainingData: Data?) -> (output: String, finalLines: [String]) {
        lock.lock()
        defer { lock.unlock() }

        if let data = remainingData, !data.isEmpty {
            allBytes.append(data)
            byteBuffer.append(data)
        }

        var lines: [String] = []
        if !byteBuffer.isEmpty {
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
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentCommandLabel: String = ""

    private var activeProcesses: [UUID: (process: Process, label: String)] = [:]
    private var queueTail: Task<Void, Never>? = nil
    private let maxTerminalLines = 5000

    public init() {}

    public func clearLog() {
        terminalLines.removeAll()
    }

    public func cancelCurrentProcess() {
        for (_, entry) in activeProcesses {
            if entry.process.isRunning {
                entry.process.terminate()
            }
        }
    }

    public func runShell(_ command: String, label: String, serialized: Bool = true) async -> CommandResult {
        return await run(
            executable: "/bin/zsh",
            arguments: ["-c", command],
            label: label,
            serialized: serialized
        )
    }

    public func run(
        executable: String,
        arguments: [String],
        label: String,
        serialized: Bool = true,
        onLine: ((String) -> Void)? = nil
    ) async -> CommandResult {
        if !serialized {
            return await execute(executable: executable, arguments: arguments, label: label, onLine: onLine)
        }

        let prev = queueTail
        let task = Task<CommandResult, Never> { [prev] in
            if let prev = prev {
                _ = await prev.value
            }
            return await self.execute(executable: executable, arguments: arguments, label: label, onLine: onLine)
        }
        queueTail = Task {
            _ = await task.value
        }
        return await task.value
    }

    private func appendLine(_ line: String, onLine: ((String) -> Void)?) {
        terminalLines.append(line)
        if terminalLines.count > maxTerminalLines {
            terminalLines.removeFirst(terminalLines.count - maxTerminalLines)
        }
        onLine?(line)
    }

    private func execute(
        executable: String,
        arguments: [String],
        label: String,
        onLine: ((String) -> Void)?
    ) async -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let runID = UUID()
        activeProcesses[runID] = (process, label)
        isRunning = true
        currentCommandLabel = label

        defer {
            activeProcesses.removeValue(forKey: runID)
            if let remaining = activeProcesses.values.first {
                currentCommandLabel = remaining.label
                isRunning = true
            } else {
                currentCommandLabel = ""
                isRunning = false
            }
        }

        let cmdDisplay: String
        if executable == "/bin/zsh" && arguments.count >= 2 && arguments[0] == "-c" {
            cmdDisplay = "$ \(arguments[1])"
        } else {
            let argsStr = arguments.joined(separator: " ")
            cmdDisplay = argsStr.isEmpty ? "$ \(executable)" : "$ \(executable) \(argsStr)"
        }
        appendLine(cmdDisplay, onLine: onLine)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSHomeDirectory())/.local/bin"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        let stdoutCollector = StreamCollector()
        let stderrCollector = StreamCollector()

        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let lines = stdoutCollector.appendData(data)
            if !lines.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    for line in lines {
                        self?.appendLine(line, onLine: onLine)
                    }
                }
            }
        }

        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let lines = stderrCollector.appendData(data)
            if !lines.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    for line in lines {
                        self?.appendLine(line, onLine: onLine)
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            let errMsg = error.localizedDescription
            appendLine("Error: \(errMsg)", onLine: onLine)
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

        let (stdoutString, finalStdoutLines) = stdoutCollector.finish(remainingData: remainingStdout)
        let (stderrString, finalStderrLines) = stderrCollector.finish(remainingData: remainingStderr)

        for line in finalStdoutLines {
            appendLine(line, onLine: onLine)
        }
        for line in finalStderrLines {
            appendLine(line, onLine: onLine)
        }

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdoutString,
            stderr: stderrString
        )
    }
}
