import Foundation

protocol SpeedTesting: Sendable {
    func run(interface: String) async -> Result<SpeedTestResult, SpeedTestError>
}

/// Runs Apple's `networkQuality` bound to one interface, so a laptop docked on Ethernet
/// still tests its Wi-Fi.
struct NetworkQualityRunner: SpeedTesting {
    let executable: URL
    /// networkQuality can hang with no output (seen with an interface that doesn't exist),
    /// so every test gets a hard limit.
    let timeout: Duration

    init(executable: URL = URL(filePath: "/usr/bin/networkQuality"), timeout: Duration = .seconds(30)) {
        self.executable = executable
        self.timeout = timeout
    }

    /// Download only, at most 12 s, JSON output.
    static func arguments(interface: String) -> [String] {
        ["-I", interface, "-u", "-M", "12", "-c"]
    }

    func run(interface: String) async -> Result<SpeedTestResult, SpeedTestError> {
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(interface: interface)
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let exits = AsyncStream<Int32> { continuation in
            process.terminationHandler = { p in
                continuation.yield(p.terminationStatus)
                continuation.finish()
            }
        }

        let start = Date()
        do {
            try process.run()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
        let output = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }

        let status: Int32? = await withTaskGroup(of: Int32?.self) { group in
            group.addTask {
                for await status in exits { return status }
                return nil
            }
            group.addTask { [timeout] in
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let end = Date()

        guard let status else {
            await Self.stop(process)
            return .failure(Task.isCancelled ? .cancelled : .timedOut)
        }
        guard status == 0 else { return .failure(.exited(status)) }
        guard let result = try? SpeedTestResult.parse(await output.value, start: start, end: end) else {
            return .failure(.unreadableOutput)
        }
        return .success(result)
    }

    /// SIGTERM, then SIGKILL if it's still around two seconds later.
    private static func stop(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
