import Foundation

public final class TunnelService {
    private var activeProcesses: [String: Process] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - Binary Detection
    public static func findBinaryPath() -> String? {
        let candidates = [
            "/opt/local/bin/cloudflared",
            "\(NSHomeDirectory())/.local/bin/cloudflared",
            "/usr/local/bin/cloudflared"
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Fallback to which cloudflared
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["cloudflared"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            return nil
        }
        return nil
    }

    public static func isCloudflaredInstalled() -> Bool {
        return findBinaryPath() != nil
    }

    public func findBinaryPath() -> String? {
        return Self.findBinaryPath()
    }

    public func isCloudflaredInstalled() -> Bool {
        return Self.isCloudflaredInstalled()
    }

    // MARK: - URL Parsing
    public static func extractTunnelURL(from log: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "https://[a-zA-Z0-9-]+\\.trycloudflare\\.com") else {
            return nil
        }
        let nsRange = NSRange(log.startIndex..<log.endIndex, in: log)
        guard let match = regex.firstMatch(in: log, options: [], range: nsRange),
              let range = Range(match.range, in: log) else {
            return nil
        }
        return String(log[range])
    }

    // MARK: - Process Arguments Builder
    public static func buildProcessArguments(port: String, isSSL: Bool = false, hostHeader: String? = nil) -> [String] {
        let scheme = isSSL ? "https" : "http"
        var args = [
            "tunnel",
            "--url", "\(scheme)://127.0.0.1:\(port)",
            "--no-autoupdate"
        ]
        if isSSL {
            args.append("--no-tls-verify")
        }
        if let hostHeader = hostHeader, !hostHeader.isEmpty {
            args.append(contentsOf: ["--http-host-header", hostHeader])
        }
        return args
    }

    // MARK: - Process Supervision
    @discardableResult
    public func startTunnel(
        port: String,
        label: String,
        isVHost: Bool = false,
        isSSL: Bool = false,
        hostHeader: String? = nil,
        onUrlDiscovered: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Process? {
        guard let binaryPath = Self.findBinaryPath() else {
            onError("cloudflared binary not found in /opt/local/bin, ~/.local/bin, or PATH.")
            return nil
        }

        let tunnelId = "\(port)_\(label.replacingOccurrences(of: " ", with: "_"))"

        // Stop existing process for this tunnelId if any
        stopTunnel(tunnelId: tunnelId)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = Self.buildProcessArguments(port: port, isSSL: isSSL, hostHeader: hostHeader)

        let errorPipe = Pipe()
        process.standardError = errorPipe

        var urlFound = false
        let handlerLock = NSLock()

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            handlerLock.lock()
            defer { handlerLock.unlock() }

            if !urlFound, let url = Self.extractTunnelURL(from: output) {
                urlFound = true
                DispatchQueue.main.async {
                    onUrlDiscovered(url)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self?.lock.lock()
            self?.activeProcesses.removeValue(forKey: tunnelId)
            self?.lock.unlock()

            DispatchQueue.main.async {
                onExit(proc.terminationStatus)
            }
        }

        lock.lock()
        activeProcesses[tunnelId] = process
        lock.unlock()

        do {
            try process.run()
            return process
        } catch {
            lock.lock()
            activeProcesses.removeValue(forKey: tunnelId)
            lock.unlock()
            errorPipe.fileHandleForReading.readabilityHandler = nil
            onError(error.localizedDescription)
            return nil
        }
    }

    public func stopTunnel(tunnelId: String) {
        lock.lock()
        let process = activeProcesses.removeValue(forKey: tunnelId)
        lock.unlock()

        if let process = process, process.isRunning {
            process.terminate()
        }
    }

    public func stopAllTunnels() {
        lock.lock()
        let processes = Array(activeProcesses.values)
        activeProcesses.removeAll()
        lock.unlock()

        for process in processes {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    public func isTunnelRunning(tunnelId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeProcesses[tunnelId]?.isRunning == true
    }
}
