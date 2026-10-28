import Foundation

// MARK: - Stream Collector
final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var remainder = ""

    func appendData(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        output += text
        let combined = remainder + text
        let parts = combined.components(separatedBy: "\n")
        if parts.count > 1 {
            var lines: [String] = []
            for i in 0..<(parts.count - 1) {
                var l = parts[i]
                if l.hasSuffix("\r") { l.removeLast() }
                lines.append(l)
            }
            remainder = parts.last ?? ""
            return lines
        } else {
            remainder = combined
            return []
        }
    }

    func finish(remainingData: Data?) -> (output: String, finalLines: [String]) {
        lock.lock()
        defer { lock.unlock() }
        if let data = remainingData, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            output += text
            remainder += text
        }
        var lines: [String] = []
        if !remainder.isEmpty {
            let parts = remainder.components(separatedBy: "\n")
            for part in parts {
                var l = part
                if l.hasSuffix("\r") { l.removeLast() }
                if !l.isEmpty {
                    lines.append(l)
                }
            }
            remainder = ""
        }
        return (output, lines)
    }
}

// MARK: - Command Result
public struct CommandResult: Equatable {
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

    private var currentProcess: Process?
    private var queueTail: Task<Void, Never>? = nil

    public init() {}

    public func clearLog() {
        terminalLines.removeAll()
    }

    public func cancelCurrentProcess() {
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
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
        onLine?(line)
    }

    private func execute(
        executable: String,
        arguments: [String],
        label: String,
        onLine: ((String) -> Void)?
    ) async -> CommandResult {
        isRunning = true
        currentCommandLabel = label
        defer {
            isRunning = false
            currentCommandLabel = ""
            currentProcess = nil
        }

        let cmdDisplay: String
        if executable == "/bin/zsh" && arguments.count >= 2 && arguments[0] == "-c" {
            cmdDisplay = "$ \(arguments[1])"
        } else {
            let argsStr = arguments.joined(separator: " ")
            cmdDisplay = argsStr.isEmpty ? "$ \(executable)" : "$ \(executable) \(argsStr)"
        }
        appendLine(cmdDisplay, onLine: onLine)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

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

        currentProcess = process

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
