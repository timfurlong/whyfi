import Foundation
import Testing
@testable import WhyFi

private let t0 = Date(timeIntervalSince1970: 1_794_865_260)

@MainActor
private struct Harness {
    let store: RunStore
    let signal = FakeSignal()
    let speed = FakeSpeed()
    let speech = FakeSpeech()
    let clock = TestClock(t0)
    let recorder: RunRecorder

    init(location: LocationAccess = .granted, mode: SpeedTestMode = .backToBack) {
        let root = FileManager.default.temporaryDirectory.appending(path: "whyfi-rec-\(UUID().uuidString)")
        store = RunStore(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let clock = self.clock
        recorder = RunRecorder(store: store, signal: signal, speed: speed, speech: speech,
                               permissions: FakePermissions(location: location), mode: { mode },
                               now: { clock.now }, sleep: parkedSleep)
    }

    func rows() throws -> [TimelineRow] {
        let folder = try #require(recorder.folder)
        return try TimelineCSV.read(fileAt: folder.appending(path: "timeline.csv"))
    }

    func events() throws -> [String] {
        try rows().filter { $0.kind == .event }.compactMap(\.text)
    }
}

@MainActor @Test func startWritesRunJSONAndStartedEvent() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Router on shelf")
    defer { Task { await h.recorder.stop() } }
    let folder = try #require(h.recorder.folder)
    let info = try RunInfo.decoder.decode(RunInfo.self, from: Data(contentsOf: folder.appending(path: "run.json")))
    #expect(info.name == "Router on shelf")
    #expect(info.startedAt == t0)
    #expect(info.endedAt == nil)
    #expect(info.wifiInterface == "en0")
    #expect(h.store.recordingFolder == folder)
    #expect(h.recorder.isRecording)
    #expect(try h.events() == ["run_started"])
}

@MainActor @Test func tickWritesSignalRowsAndDisconnectEvents() async throws {
    let h = Harness()
    h.signal.script = [FakeSignal.reading(-60), nil, FakeSignal.reading(-61)]
    try await h.recorder.start(name: "Walk")
    for _ in 0..<3 { h.clock.advance(1); h.recorder.tick() }
    let rows = try h.rows().map { "\($0.kind.rawValue) \($0.rssi.map(String.init) ?? $0.text ?? "")" }
    #expect(rows == ["event run_started", "signal -60", "event wifi_disconnected", "event wifi_reconnected", "signal -61"])
    #expect(h.recorder.readings.map(\.rssi) == [-60, -61])
    #expect(h.recorder.wifiConnected)
    await h.recorder.stop()
}

@MainActor @Test func roamAndBandChangeAreEvents() async throws {
    let h = Harness()
    h.signal.script = [FakeSignal.reading(-60, bssid: "aa"), FakeSignal.reading(-62, bssid: "bb"),
                       FakeSignal.reading(-70, bssid: "bb", band: .ghz2_4)]
    try await h.recorder.start(name: "Walk")
    for _ in 0..<3 { h.clock.advance(1); h.recorder.tick() }
    #expect(try h.events() == ["run_started", "access_point_changed aa -> bb", "band_changed 5 GHz -> 2.4 GHz"])
    await h.recorder.stop()
}

@MainActor @Test func speedRowAveragesSignalDuringTest() async throws {
    let h = Harness()
    h.signal.script = [FakeSignal.reading(-60), FakeSignal.reading(-70), FakeSignal.reading(-90)]
    try await h.recorder.start(name: "Walk")
    h.clock.advance(12); h.recorder.tick()   // t0+12, inside the test
    h.clock.advance(3); h.recorder.tick()    // t0+15, inside
    h.clock.advance(10); h.recorder.tick()   // t0+25, after it
    h.speed.results = [.success(SpeedTestResult(start: t0 + 10, end: t0 + 20, downloadMbps: 88.4, responsivenessRPM: 500))]
    #expect(await h.recorder.runOneSpeedTest())
    let row = try #require(try h.rows().first { $0.kind == .speed })
    #expect(row.time == t0 + 10 && row.endTime == t0 + 20)
    #expect(row.rssi == -65 && row.txRate == 400 && row.downloadMbps == 88.4 && row.responsivenessRPM == 500)
    #expect(h.recorder.speedTests.count == 1)
    await h.recorder.stop()
}

@MainActor @Test func speedFailureIsLoggedAndRetriedAfterTenSeconds() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Walk")
    h.speed.results = [.failure(.timedOut)]
    #expect(await h.recorder.runOneSpeedTest() == false)
    #expect(try h.events().last == "speed_test_failed: timed out")
    #expect(h.recorder.lastSpeedError == "timed out")
    #expect(h.recorder.pauseAfterSpeedTest(succeeded: false) == .seconds(10))
    #expect(h.recorder.pauseAfterSpeedTest(succeeded: true) == .seconds(1))
    await h.recorder.stop()
}

@MainActor @Test func speedTestsUseSignalSourceInterface() async throws {
    let h = Harness()
    h.signal.interfaceName = "en7"
    try await h.recorder.start(name: "Walk")
    _ = await h.recorder.runOneSpeedTest()
    #expect(h.speed.interfaces == ["en7"])
    await h.recorder.stop()
}

@MainActor @Test func speechFailureKeepsRecordingWiFi() async throws {
    let h = Harness()
    h.speech.startError = SpeechSourceError.microphoneDenied
    h.signal.script = [FakeSignal.reading(-60)]
    try await h.recorder.start(name: "Walk")
    h.clock.advance(1); h.recorder.tick()
    #expect(try h.events().contains("speech_unavailable: Microphone access denied"))
    #expect(try h.rows().contains { $0.kind == .signal })
    #expect(h.recorder.speechStatus == .unavailable("Microphone access denied"))
    await h.recorder.stop()
    let info = try RunInfo.decoder.decode(RunInfo.self, from: Data(contentsOf: try #require(h.store.runs.first).folder.appending(path: "run.json")))
    #expect(info.permissions.microphone == false && info.permissions.speech == false)
}

@MainActor @Test func locationDeniedIsAnEvent() async throws {
    let h = Harness(location: .denied)
    try await h.recorder.start(name: "Walk")
    #expect(try h.events() == ["run_started", "location_denied"])
    await h.recorder.stop()
}

@MainActor @Test func locationNotYetAnsweredIsNotAnEvent() async throws {
    let h = Harness(location: .undetermined)
    try await h.recorder.start(name: "Walk")
    #expect(try h.events() == ["run_started"])
    await h.recorder.stop()
}

@MainActor @Test func bssidMarksLocationGranted() async throws {
    let h = Harness(location: .undetermined)
    h.signal.script = [FakeSignal.reading(-60, bssid: nil), FakeSignal.reading(-60, bssid: "aa")]
    try await h.recorder.start(name: "Walk")
    for _ in 0..<2 { h.clock.advance(1); h.recorder.tick() }
    await h.recorder.stop()
    let info = try RunInfo.decoder.decode(RunInfo.self, from: Data(contentsOf: try #require(h.store.runs.first).folder.appending(path: "run.json")))
    #expect(info.permissions.location)
}

@MainActor @Test func cancelledSpeedTestIsNotAFailure() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Walk")
    h.speed.results = [.failure(.cancelled)]
    #expect(await h.recorder.runOneSpeedTest() == false)
    #expect(try h.events() == ["run_started"])
    #expect(h.recorder.lastSpeedError == nil)
    await h.recorder.stop()
}

@MainActor @Test func finalSentenceWritesSpeechRowAndTranscript() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Walk")
    let sentence = Sentence(start: t0 + 4, end: t0 + 6, text: "Standing next to the dryer.")
    h.recorder.handle(.final(sentence))
    h.recorder.handle(.volatile("turning the"))
    let row = try #require(try h.rows().first { $0.kind == .speech })
    #expect(row.text == "Standing next to the dryer." && row.time == t0 + 4 && row.endTime == t0 + 6)
    #expect(h.recorder.sentences == [sentence])
    #expect(h.recorder.volatileText == "turning the")
    let transcript = try String(contentsOf: try #require(h.recorder.folder).appending(path: "transcript.txt"), encoding: .utf8)
    #expect(transcript.hasSuffix("Standing next to the dryer.\n"))
    await h.recorder.stop()
}

@MainActor @Test func stopWritesEndAndStoppedEvent() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Walk")
    let folder = try #require(h.recorder.folder)
    h.clock.advance(90)
    await h.recorder.stop()
    #expect(!h.recorder.isRecording)
    #expect(h.speech.stopped)
    #expect(h.store.recordingFolder == nil)
    let run = try #require(h.store.runs.first)
    #expect(run.info.endedAt == t0 + 90)
    #expect(!h.store.isInterrupted(run))
    let rows = try TimelineCSV.read(fileAt: folder.appending(path: "timeline.csv"))
    #expect(rows.last?.text == "run_stopped" && rows.last?.elapsed == 90)
}

@MainActor @Test func stopWhileSpeechIsStartingStopsItWhenItArrives() async throws {
    let h = Harness()
    h.speech.holdStart = true
    let starting = Task { try await h.recorder.start(name: "Walk") }
    while !h.speech.waitingInStart { await Task.yield() }
    await h.recorder.stop()
    h.speech.releaseStart()
    try await starting.value
    #expect(h.speech.sessionsStarted == 1)
    #expect(h.speech.sessionsStopped == 1)
    #expect(!h.recorder.isRecording)
}

@MainActor @Test func sentenceFinalizedAtStopIsKept() async throws {
    let h = Harness()
    h.speech.finalOnStop = Sentence(start: t0 + 4, end: t0 + 6, text: "Last thing I said.")
    try await h.recorder.start(name: "Walk")
    let folder = try #require(h.recorder.folder)
    h.clock.advance(10)
    await h.recorder.stop()
    let rows = try TimelineCSV.read(fileAt: folder.appending(path: "timeline.csv"))
    #expect(rows.contains { $0.kind == .speech && $0.text == "Last thing I said." })
    #expect(rows.last?.text == "run_stopped")
}

@MainActor @Test func renameWhileRecordingSurvivesStop() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Old name")
    try h.store.rename(try #require(h.store.runs.first), to: "New name")
    await h.recorder.stop()
    let info = try RunInfo.decoder.decode(RunInfo.self, from: Data(contentsOf: try #require(h.store.runs.first).folder.appending(path: "run.json")))
    #expect(info.name == "New name")
}

@MainActor @Test func secondStopDoesNothing() async throws {
    let h = Harness()
    try await h.recorder.start(name: "Walk")
    let folder = try #require(h.recorder.folder)
    async let first: Void = h.recorder.stop()
    async let second: Void = h.recorder.stop()
    _ = await (first, second)
    let rows = try TimelineCSV.read(fileAt: folder.appending(path: "timeline.csv"))
    #expect(rows.filter { $0.text == "run_stopped" }.count == 1)
}
