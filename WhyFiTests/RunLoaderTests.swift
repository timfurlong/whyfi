import Foundation
import Testing
@testable import WhyFi

private let t0 = Date(timeIntervalSince1970: 1_794_865_260)

@MainActor @Test func rebuildsRunFromFolder() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "whyfi-load-\(UUID().uuidString)")
    let store = RunStore(root: root, trash: { try FileManager.default.removeItem(at: $0) })
    let info = RunInfo(name: "Fixture", startedAt: t0, endedAt: t0 + 60, appVersion: "0.1.0",
                       macOSVersion: "26.6.2", macModel: "Mac15,9", wifiInterface: "en0",
                       speedTestMode: .backToBack, locale: "en-US",
                       permissions: .init(microphone: true, speech: true, location: true))
    let folder = try store.createRun(info: info)
    let writer = try TimelineWriter(folder: folder)
    func reading(_ s: Double, _ rssi: Int) -> SignalReading {
        SignalReading(time: t0 + s, rssi: rssi, noise: -95, txRate: 400, channel: 149, band: .ghz5, widthMHz: 80, bssid: "aa")
    }
    try writer.append(.signal(reading(1, -60), elapsed: 1))
    try writer.append(.event("wifi_disconnected", at: t0 + 2, elapsed: 2))
    try writer.append(.signal(reading(5, -70), elapsed: 5))
    try writer.append(.signal(reading(6, -71), elapsed: 6))
    try writer.append(TimelineRow(time: t0 + 3, elapsed: 3, kind: .speed, rssi: -62, txRate: 400,
                                  downloadMbps: 88.4, responsivenessRPM: 500, endTime: t0 + 12))
    try writer.append(TimelineRow(time: t0 + 4, elapsed: 4, kind: .speech, text: "By the dryer.", endTime: t0 + 5.5))
    writer.close()

    let run = try RunLoader.load(try #require(store.runs.first))

    #expect(run.info == info)
    #expect(run.readings.map(\.rssi) == [-60, -70, -71])
    #expect(run.readings.first?.band == .ghz5 && run.readings.first?.bssid == "aa")
    #expect(run.speedTests == [SpeedTestResult(start: t0 + 3, end: t0 + 12, downloadMbps: 88.4, responsivenessRPM: 500)])
    #expect(run.sentences.map(\.text) == ["By the dryer."])
    #expect(run.sentences.first?.start == t0 + 4 && run.sentences.first?.end == t0 + 5.5)
    #expect(run.events.compactMap(\.text) == ["wifi_disconnected"])
}

@Test func readingsSplitIntoSegmentsAtGaps() {
    func r(_ s: Double) -> SignalReading {
        SignalReading(time: t0 + s, rssi: -60, noise: -95, txRate: 400, channel: 149, band: .ghz5, widthMHz: 80)
    }
    let segments = LoadedRun.segments([r(0), r(1), r(2), r(9), r(10)])
    #expect(segments.map { $0.map(\.time) } == [[t0, t0 + 1, t0 + 2], [t0 + 9, t0 + 10]])
}

@Test(arguments: [(90.0, 1), (360.0, 1), (1200.0, 4), (3600.0, 10)])
func timeAxisStepsKeepLabelsUnique(seconds: Double, minutes: Int) {
    #expect(RunChart.axisStepMinutes(for: seconds) == minutes)
}
