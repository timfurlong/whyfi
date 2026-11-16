import Foundation
import Testing
@testable import WhyFi

private let denver = TimeZone(identifier: "America/Denver")!
/// 2026-11-16 14:41:00 in Denver.
private let start = Date(timeIntervalSince1970: 1_794_865_260)

private func info(_ name: String, startedAt: Date = start, endedAt: Date? = nil) -> RunInfo {
    RunInfo(name: name, startedAt: startedAt, endedAt: endedAt, appVersion: "0.1.0",
            macOSVersion: "26.6.2", macModel: "Mac15,9", wifiInterface: "en0",
            speedTestMode: .backToBack, locale: "en-US",
            permissions: .init(microphone: true, speech: true, location: false))
}

@MainActor
private func makeStore() throws -> (RunStore, URL, Trashed) {
    let root = FileManager.default.temporaryDirectory.appending(path: "whyfi-runs-\(UUID().uuidString)")
    let trashed = Trashed()
    let store = RunStore(root: root, timeZone: denver, trash: { trashed.urls.append($0); try FileManager.default.removeItem(at: $0) })
    return (store, root, trashed)
}

private final class Trashed: @unchecked Sendable { var urls: [URL] = [] }

@MainActor @Test func createRunMakesFolderAndRunJSON() throws {
    let (store, root, _) = try makeStore()
    let folder = try store.createRun(info: info("Router on shelf"))
    #expect(folder == root.appending(path: "2026-11-16 1441 Router on shelf"))
    let json = try String(contentsOf: folder.appending(path: "run.json"), encoding: .utf8)
    #expect(json.contains("\"speed_test_mode\" : \"back_to_back\""))
    #expect(json.contains("\"started_at\" : \"2026-11-16T21:41:00Z\""))
    #expect(store.runs.map(\.info) == [info("Router on shelf")])
}

@MainActor @Test func unsafeNameIsSanitized() throws {
    let (store, root, _) = try makeStore()
    let folder = try store.createRun(info: info(" a/b:c "))
    #expect(folder == root.appending(path: "2026-11-16 1441 a-b-c"))
}

@MainActor @Test func nameClashGetsSuffix() throws {
    let (store, _, _) = try makeStore()
    _ = try store.createRun(info: info("Bed"))
    let second = try store.createRun(info: info("Bed"))
    let third = try store.createRun(info: info("Bed"))
    #expect(second.lastPathComponent == "2026-11-16 1441 Bed 2")
    #expect(third.lastPathComponent == "2026-11-16 1441 Bed 3")
}

@MainActor @Test func runsAreNewestFirst() throws {
    let (store, _, _) = try makeStore()
    _ = try store.createRun(info: info("Older", startedAt: start))
    _ = try store.createRun(info: info("Newer", startedAt: start.addingTimeInterval(600)))
    #expect(store.runs.map(\.info.name) == ["Newer", "Older"])
}

@MainActor @Test func reloadSkipsFoldersWithoutRunJSON() throws {
    let (store, root, _) = try makeStore()
    _ = try store.createRun(info: info("Real"))
    try FileManager.default.createDirectory(at: root.appending(path: "junk"), withIntermediateDirectories: true)
    store.reload()
    #expect(store.runs.map(\.info.name) == ["Real"])
}

@MainActor @Test func missingEndIsInterruptedUnlessRecording() throws {
    let (store, _, _) = try makeStore()
    let open = try store.createRun(info: info("Open"))
    _ = try store.createRun(info: info("Done", endedAt: start.addingTimeInterval(60)))
    let openRun = try #require(store.runs.first { $0.info.name == "Open" })
    let doneRun = try #require(store.runs.first { $0.info.name == "Done" })
    #expect(store.isInterrupted(openRun))
    #expect(!store.isInterrupted(doneRun))
    store.recordingFolder = open
    #expect(!store.isInterrupted(openRun))
}

@MainActor @Test func renameKeepsFolder() throws {
    let (store, _, _) = try makeStore()
    let folder = try store.createRun(info: info("Old name"))
    try store.rename(try #require(store.runs.first), to: "New name")
    #expect(store.runs.first?.folder == folder)
    #expect(store.runs.first?.info.name == "New name")
    store.reload()
    #expect(store.runs.first?.info.name == "New name")
}

@MainActor @Test func deleteMovesToTrash() throws {
    let (store, _, trashed) = try makeStore()
    let folder = try store.createRun(info: info("Gone"))
    try store.delete(try #require(store.runs.first))
    #expect(trashed.urls == [folder])
    #expect(store.runs.isEmpty)
}

@Test func speedTestModeValues() {
    #expect(SpeedTestMode.backToBack.rawValue == "back_to_back")
    #expect(SpeedTestMode.every30Seconds.rawValue == "every_30_seconds")
    #expect(SpeedTestMode.backToBack.pauseAfterTest == .seconds(1))
    #expect(SpeedTestMode.every30Seconds.pauseAfterTest == .seconds(30))
    #expect(SpeedTestMode.off.pauseAfterTest == nil)
}
