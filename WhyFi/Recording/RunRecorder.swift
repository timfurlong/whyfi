import Foundation
import Observation

/// Records a run: Wi-Fi once a second, speed tests one after another, and the narration,
/// all written to the run's folder as they happen.
@MainActor @Observable
final class RunRecorder {
    private(set) var isRecording = false
    /// True from the moment Stop is pressed until the run is closed, so a second Stop does nothing.
    private(set) var isStopping = false
    private(set) var folder: URL?
    private(set) var startedAt: Date?
    /// Readings while connected. A disconnection shows as a gap between readings.
    private(set) var readings: [SignalReading] = []
    private(set) var events: [TimelineRow] = []
    private(set) var speedTests: [SpeedTestResult] = []
    private(set) var speedTestRunning = false
    private(set) var lastSpeedError: String?
    private(set) var sentences: [Sentence] = []
    private(set) var volatileText = ""
    private(set) var micLevel: Float = 0
    private(set) var speechStatus: SpeechStatus = .off
    private(set) var wifiConnected = true
    private(set) var lastWriteError: String?

    @ObservationIgnored private let store: RunStore
    @ObservationIgnored private let signal: SignalSource
    @ObservationIgnored private let speed: SpeedTesting
    @ObservationIgnored private let speech: SpeechSource
    @ObservationIgnored private let permissions: PermissionChecking
    @ObservationIgnored private let mode: @MainActor () -> SpeedTestMode
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var info: RunInfo?
    @ObservationIgnored private var writer: TimelineWriter?
    @ObservationIgnored private var lastReading: SignalReading?
    @ObservationIgnored private var hadFirstSample = false
    @ObservationIgnored private var loops: [Task<Void, Never>] = []
    /// Reads the speech updates. Kept apart from `loops` so Stop can let it drain the
    /// sentences the analyzer finalizes while stopping.
    @ObservationIgnored private var speechConsumer: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?

    init(store: RunStore, signal: SignalSource, speed: SpeedTesting, speech: SpeechSource,
         permissions: PermissionChecking, mode: @escaping @MainActor () -> SpeedTestMode,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.signal = signal
        self.speed = speed
        self.speech = speech
        self.permissions = permissions
        self.mode = mode
        self.now = now
        self.sleep = sleep
    }

    // MARK: - Start and stop

    func start(name: String) async throws {
        guard !isRecording else { return }
        let start = now()
        let info = RunInfo(
            name: name, startedAt: start, endedAt: nil,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            macOSVersion: Self.macOSVersion, macModel: Self.macModel,
            wifiInterface: signal.interfaceName, speedTestMode: mode(), locale: "en-US",
            permissions: .init(microphone: false, speech: false, location: permissions.location == .granted))
        let folder = try store.createRun(info: info)
        writer = try TimelineWriter(folder: folder)
        self.info = info
        self.folder = folder
        startedAt = start
        readings = []
        events = []
        speedTests = []
        sentences = []
        volatileText = ""
        lastSpeedError = nil
        lastReading = nil
        hadFirstSample = false
        wifiConnected = true
        isRecording = true
        store.recordingFolder = folder
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated], reason: "Recording a WhyFi run")

        logEvent("run_started")
        if permissions.location == .denied { logEvent("location_denied") }

        loops = [
            Task { [weak self] in await self?.signalLoop() },
            Task { [weak self] in await self?.speedLoop() },
        ]
        await startSpeech(folder: folder)
    }

    func stop() async {
        guard isRecording, !isStopping, folder != nil else { return }
        isStopping = true
        defer { isStopping = false }
        for loop in loops { loop.cancel() }
        loops = []
        await speech.stop()
        await speechConsumer?.value
        speechConsumer = nil
        logEvent("run_stopped")
        writer?.close()
        writer = nil
        saveInfo { $0.endedAt = now() }
        store.recordingFolder = nil
        store.reload()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        isRecording = false
        speechStatus = .off
        micLevel = 0
        speedTestRunning = false
    }

    // MARK: - Signal

    /// Takes one Wi-Fi reading. The signal loop calls this once a second.
    func tick() {
        guard isRecording else { return }
        let time = now()
        let reading = signal.read(at: time)
        switch (lastReading, reading) {
        case (nil, nil):
            if !hadFirstSample { logEvent("wifi_disconnected", at: time) }
        case (.some, nil):
            logEvent("wifi_disconnected", at: time)
        case (nil, .some):
            if hadFirstSample { logEvent("wifi_reconnected", at: time) }
        case let (.some(old), .some(new)):
            if let a = old.bssid, let b = new.bssid, a != b {
                logEvent("access_point_changed \(a) -> \(b)", at: time)
            }
            if old.band != new.band {
                logEvent("band_changed \(old.band.rawValue) -> \(new.band.rawValue)", at: time)
            }
        }
        hadFirstSample = true
        lastReading = reading
        wifiConnected = reading != nil
        if let reading {
            if reading.bssid != nil, let info, !info.permissions.location {
                // Location was allowed after the run started (macOS only shows the BSSID then).
                saveInfo { $0.permissions.location = true }
            }
            readings.append(reading)
            write(.signal(reading, elapsed: elapsed(at: time)))
        }
    }

    private func signalLoop() async {
        while !Task.isCancelled {
            do { try await sleep(.seconds(1)) } catch { return }
            tick()
        }
    }

    // MARK: - Speed tests

    /// Runs one speed test and records it. Returns whether it succeeded.
    @discardableResult
    func runOneSpeedTest() async -> Bool {
        guard isRecording else { return false }
        guard let interface = signal.interfaceName else {
            recordSpeedFailure("no Wi-Fi interface")
            return false
        }
        speedTestRunning = true
        let result = await speed.run(interface: interface)
        speedTestRunning = false
        guard isRecording else { return false }
        switch result {
        case .success(let test):
            let during = readings.filter { $0.time >= test.start && $0.time <= test.end }
            let rssi = during.isEmpty ? nil : Int((Double(during.map(\.rssi).reduce(0, +)) / Double(during.count)).rounded())
            let tx = during.isEmpty ? nil : (during.map(\.txRate).reduce(0, +) / Double(during.count)).rounded()
            speedTests.append(test)
            lastSpeedError = nil
            write(TimelineRow(time: test.start, elapsed: elapsed(at: test.start), kind: .speed,
                              rssi: rssi, txRate: tx, downloadMbps: test.downloadMbps,
                              responsivenessRPM: test.responsivenessRPM, endTime: test.end))
            return true
        case .failure(.cancelled):
            return false
        case .failure(let error):
            recordSpeedFailure(error.reason)
            return false
        }
    }

    func pauseAfterSpeedTest(succeeded: Bool) -> Duration? {
        guard let pause = mode().pauseAfterTest else { return nil }
        return succeeded ? pause : .seconds(10)
    }

    private func recordSpeedFailure(_ reason: String) {
        lastSpeedError = reason
        logEvent("speed_test_failed: \(reason)")
    }

    private func speedLoop() async {
        var wait: Duration = .seconds(1)
        while !Task.isCancelled {
            do { try await sleep(wait) } catch { return }
            guard mode() != .off else { wait = .seconds(1); continue }
            let ok = await runOneSpeedTest()
            wait = pauseAfterSpeedTest(succeeded: ok) ?? .seconds(1)
        }
    }

    // MARK: - Speech

    private func startSpeech(folder: URL) async {
        speechStatus = .preparing(0)
        do {
            let updates = try await speech.start(folder: folder) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .preparing = self.speechStatus else { return }
                    self.speechStatus = .preparing(fraction)
                }
            }
            // The microphone prompt or the model download can take a while. If the run was
            // stopped meanwhile, stop the speech that just started instead of leaving it on.
            guard isRecording, self.folder == folder else {
                await speech.stop()
                return
            }
            setPermissions(microphone: true, speech: true)
            speechConsumer = Task { [weak self] in
                for await update in updates {
                    self?.handle(update)
                }
            }
        } catch {
            guard isRecording, self.folder == folder else { return }
            let reason = (error as? SpeechSourceError)?.reason ?? error.localizedDescription
            setPermissions(microphone: (error as? SpeechSourceError) != .microphoneDenied, speech: false)
            speechStatus = .unavailable(reason)
            logEvent("speech_unavailable: \(reason)")
        }
    }

    func handle(_ update: SpeechUpdate) {
        guard isRecording else { return }
        switch update {
        case .preparing(let progress):
            speechStatus = .preparing(progress)
        case .listening:
            speechStatus = .listening
        case .volatile(let text):
            volatileText = text
        case .final(let sentence):
            sentences.append(sentence)
            write(TimelineRow(time: sentence.start, elapsed: elapsed(at: sentence.start), kind: .speech,
                              text: sentence.text, endTime: sentence.end))
        case .level(let level):
            micLevel = level
        case .failed(let reason):
            speechStatus = .unavailable(reason)
            logEvent("speech_unavailable: \(reason)")
        }
    }

    private func setPermissions(microphone: Bool, speech: Bool) {
        saveInfo {
            $0.permissions.microphone = microphone
            $0.permissions.speech = speech
        }
    }

    /// Changes and saves `run.json`, keeping any rename made in the sidebar meanwhile.
    private func saveInfo(_ change: (inout RunInfo) -> Void) {
        guard var info, let folder else { return }
        if let renamed = store.runs.first(where: { $0.folder == folder })?.info.name { info.name = renamed }
        change(&info)
        self.info = info
        try? store.save(info, in: folder)
    }

    // MARK: - Writing

    private func logEvent(_ text: String, at time: Date? = nil) {
        let time = time ?? now()
        let row = TimelineRow.event(text, at: time, elapsed: elapsed(at: time))
        events.append(row)
        write(row)
    }

    private func write(_ row: TimelineRow) {
        do {
            try writer?.append(row)
        } catch {
            lastWriteError = error.localizedDescription
        }
    }

    private func elapsed(at time: Date) -> Double {
        time.timeIntervalSince(startedAt ?? time)
    }

    // MARK: - About this Mac

    nonisolated static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    nonisolated static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
