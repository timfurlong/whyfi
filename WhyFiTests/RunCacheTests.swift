import Foundation
import Testing
@testable import WhyFi

private let t0 = Date(timeIntervalSince1970: 1_794_865_260)

private func summary(name: String = "Run", ended: Date? = t0 + 60) -> RunSummary {
    RunSummary(folder: URL(filePath: "/tmp/run"), info: RunInfo(
        name: name, startedAt: t0, endedAt: ended, appVersion: "0.1.0", macOSVersion: "26.6.2",
        macModel: "Mac15,9", wifiInterface: "en0", speedTestMode: .backToBack, locale: "en-US",
        permissions: .init(microphone: true, speech: true, location: true)))
}

@MainActor @Test func cacheLoadsARunOnceUntilItsInfoChanges() {
    var loads = 0
    let cache = RunCache { run in
        loads += 1
        return LoadedRun(info: run.info, readings: [], speedTests: [], sentences: [], events: [])
    }
    _ = cache.run(for: summary())
    _ = cache.run(for: summary())
    #expect(loads == 1)
    _ = cache.run(for: summary(name: "Renamed"))
    #expect(loads == 2)
    _ = cache.run(for: summary(name: "Renamed", ended: t0 + 90))
    #expect(loads == 3)
}
