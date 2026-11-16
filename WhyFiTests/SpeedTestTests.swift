import Foundation
import Testing
@testable import WhyFi

private let t0 = Date(timeIntervalSince1970: 1_794_862_934)

private func fixture() throws -> Data {
    let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/networkquality.json")
    return try Data(contentsOf: url)
}

/// A temporary executable shell script, so tests can stand in for networkQuality.
private func makeScript(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "whyfi-fake-nq-\(UUID().uuidString).sh")
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private func isRunning(_ scriptName: String) -> Bool {
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/pgrep")
    p.arguments = ["-f", scriptName]
    p.standardOutput = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

@Test func parsesFixture() throws {
    let r = try SpeedTestResult.parse(try fixture(), start: t0, end: t0 + 9)
    #expect(abs(r.downloadMbps - 241.93) < 0.01)
    #expect(r.responsivenessRPM == 971)
    #expect(r.start == t0 && r.end == t0 + 9)
}

@Test func parseRejectsJSONWithoutThroughput() {
    #expect(throws: (any Error).self) { try SpeedTestResult.parse(Data("{\"base_rtt\": 20}".utf8), start: t0, end: t0) }
}

@Test func argumentsBindToWiFi() {
    #expect(NetworkQualityRunner.arguments(interface: "en0") == ["-I", "en0", "-u", "-M", "12", "-c"])
}

@Test func successfulRunParsesOutput() async throws {
    let json = String(decoding: try fixture(), as: UTF8.self)
    let script = try makeScript("#!/bin/sh\ncat <<'JSON'\n\(json)\nJSON\n")
    let result = await NetworkQualityRunner(executable: script).run(interface: "en0")
    let speed = try result.get()
    #expect(abs(speed.downloadMbps - 241.93) < 0.01)
    #expect(speed.end >= speed.start)
}

@Test func hungProcessTimesOut() async throws {
    let script = try makeScript("#!/bin/sh\nsleep 60\n")
    let runner = NetworkQualityRunner(executable: script, timeout: .seconds(1))
    #expect(await runner.run(interface: "en0") == .failure(.timedOut))
    try await Task.sleep(for: .milliseconds(200))
    #expect(!isRunning(script.lastPathComponent))
}

@Test func garbageOutputIsUnreadable() async throws {
    let script = try makeScript("#!/bin/sh\necho not json\n")
    #expect(await NetworkQualityRunner(executable: script).run(interface: "en0") == .failure(.unreadableOutput))
}

@Test func nonZeroExitIsReported() async throws {
    let script = try makeScript("#!/bin/sh\nexit 3\n")
    #expect(await NetworkQualityRunner(executable: script).run(interface: "en0") == .failure(.exited(3)))
}

@Test func failureReasonsReadWell() {
    #expect(SpeedTestError.timedOut.reason == "timed out")
    #expect(SpeedTestError.exited(1).reason == "networkQuality exited with 1")
}

@Test func cancelledRunReportsCancelledAndStopsProcess() async throws {
    let script = try makeScript("#!/bin/sh\nsleep 60\n")
    let task = Task { await NetworkQualityRunner(executable: script, timeout: .seconds(30)).run(interface: "en0") }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()
    #expect(await task.value == .failure(.cancelled))
    try await Task.sleep(for: .milliseconds(200))
    #expect(!isRunning(script.lastPathComponent))
}
