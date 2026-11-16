import Foundation
@testable import WhyFi

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: Double) { now = now.addingTimeInterval(seconds) }
}

/// Hands out scripted readings, stamped with the time they're read at.
final class FakeSignal: SignalSource, @unchecked Sendable {
    var interfaceName: String? = "en0"
    var script: [SignalReading?] = []

    func read(at time: Date) -> SignalReading? {
        guard !script.isEmpty, var r = script.removeFirst() else { return nil }
        r.time = time
        return r
    }

    static func reading(_ rssi: Int, bssid: String? = "aa", band: WiFiBand = .ghz5) -> SignalReading {
        SignalReading(time: .distantPast, rssi: rssi, noise: -95, txRate: 400, channel: 149, band: band, widthMHz: 80, bssid: bssid)
    }
}

final class FakeSpeed: SpeedTesting, @unchecked Sendable {
    var results: [Result<SpeedTestResult, SpeedTestError>] = []
    var interfaces: [String] = []

    func run(interface: String) async -> Result<SpeedTestResult, SpeedTestError> {
        interfaces.append(interface)
        return results.isEmpty ? .failure(.unreadableOutput) : results.removeFirst()
    }
}

final class FakeSpeech: SpeechSource, @unchecked Sendable {
    var startError: (any Error)?
    /// When set, `start` waits until `releaseStart()` is called, like a microphone prompt.
    var holdStart = false
    private(set) var waitingInStart = false
    private var release: CheckedContinuation<Void, Never>?
    /// Yielded as a final sentence when `stop()` runs, like the analyzer finalizing.
    var finalOnStop: Sentence?
    private var continuation: AsyncStream<SpeechUpdate>.Continuation?
    private(set) var sessionsStarted = 0
    private(set) var sessionsStopped = 0
    var started: Bool { sessionsStarted > 0 }
    var stopped: Bool { sessionsStopped > 0 }

    func start(folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> AsyncStream<SpeechUpdate> {
        if holdStart {
            await withCheckedContinuation { c in release = c; waitingInStart = true }
        }
        if let startError { throw startError }
        sessionsStarted += 1
        let (stream, continuation) = AsyncStream<SpeechUpdate>.makeStream()
        self.continuation = continuation
        return stream
    }

    func releaseStart() { release?.resume(); release = nil }

    func stop() async {
        guard let continuation else { return }
        // A real stop takes a moment (finalizing, converting the audio).
        try? await Task.sleep(for: .milliseconds(50))
        if let finalOnStop { continuation.yield(.final(finalOnStop)) }
        continuation.finish()
        self.continuation = nil
        sessionsStopped += 1
    }
}

struct FakePermissions: PermissionChecking {
    var location: LocationAccess = .granted
}

/// A sleep that never returns until its task is cancelled, so the recorder's loops stay
/// parked and tests drive `tick()` and `runOneSpeedTest()` themselves.
let parkedSleep: @Sendable (Duration) async throws -> Void = { _ in
    try await Task.sleep(for: .seconds(3600))
}
