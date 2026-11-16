import Foundation
import Testing
@testable import WhyFi

private let denver = TimeZone(identifier: "America/Denver")!
/// 2026-11-16 14:02:14.250 in Denver (MST, -07:00).
private let t0 = Date(timeIntervalSince1970: 1_794_862_934.25)

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "whyfi-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func headerMatchesSpec() {
    #expect(TimelineCSV.header == "time,elapsed_s,kind,rssi_dbm,noise_dbm,tx_rate_mbps,channel,band,width_mhz,bssid,download_mbps,responsiveness_rpm,text,end_time")
}

@Test func signalRowFormat() {
    let r = SignalReading(time: t0, rssi: -68, noise: -95, txRate: 351, channel: 149, band: .ghz5, widthMHz: 80, bssid: "02:5a:11:3c:7e:d4")
    #expect(TimelineCSV.line(for: .signal(r, elapsed: 74.25), timeZone: denver)
        == "2026-11-16T14:02:14.250-07:00,74.250,signal,-68,-95,351.0,149,5 GHz,80,02:5a:11:3c:7e:d4,,,,")
}

@Test func speedRowFormat() {
    let row = TimelineRow(time: t0, elapsed: 3, kind: .speed, rssi: -65, txRate: 400, downloadMbps: 241.93, responsivenessRPM: 971, endTime: t0.addingTimeInterval(9))
    #expect(TimelineCSV.line(for: row, timeZone: denver)
        == "2026-11-16T14:02:14.250-07:00,3.000,speed,-65,,400.0,,,,,241.9,971,,2026-11-16T14:02:23.250-07:00")
}

@Test func speechTextIsQuotedAndRoundTrips() throws {
    let row = TimelineRow(time: t0, elapsed: 1, kind: .speech, text: "Okay, he said \"dryer\"", endTime: t0.addingTimeInterval(2.5))
    let line = TimelineCSV.line(for: row, timeZone: denver)
    #expect(line.contains("\"Okay, he said \"\"dryer\"\"\""))
    #expect(try TimelineCSV.parse(line: line) == row)
}

@Test func signalRowRoundTrips() throws {
    let r = SignalReading(time: t0, rssi: -71, noise: -92, txRate: 144.5, channel: 6, band: .ghz2_4, widthMHz: 20, bssid: nil)
    let row = TimelineRow.signal(r, elapsed: 12.5)
    #expect(try TimelineCSV.parse(line: TimelineCSV.line(for: row)) == row)
}

@Test func newlinesInTextBecomeSpaces() throws {
    let row = TimelineRow(time: t0, elapsed: 0, kind: .event, text: "line one\nline two")
    #expect(try TimelineCSV.parse(line: TimelineCSV.line(for: row)).text == "line one line two")
}

@Test func readSortsLateSpeechRowsByTime() throws {
    let folder = try tempFolder()
    let writer = try TimelineWriter(folder: folder)
    let r = SignalReading(time: t0.addingTimeInterval(5), rssi: -60, noise: -95, txRate: 866, channel: 149, band: .ghz5, widthMHz: 80)
    try writer.append(.signal(r, elapsed: 5))
    try writer.append(TimelineRow(time: t0.addingTimeInterval(2), elapsed: 2, kind: .speech, text: "Hello", endTime: t0.addingTimeInterval(3)))
    writer.close()
    let rows = try TimelineCSV.read(fileAt: folder.appending(path: "timeline.csv"))
    #expect(rows.map(\.kind) == [.speech, .signal])
}

@Test func writerAppendsTranscriptLine() throws {
    let folder = try tempFolder()
    let writer = try TimelineWriter(folder: folder, timeZone: denver)
    try writer.append(TimelineRow(time: t0, elapsed: 0, kind: .speech, text: "Standing next to the dryer.", endTime: t0.addingTimeInterval(2)))
    writer.close()
    let transcript = try String(contentsOf: folder.appending(path: "transcript.txt"), encoding: .utf8)
    #expect(transcript == "[14:02:14] Standing next to the dryer.\n")
}

@Test func writerReopensWithoutSecondHeader() throws {
    let folder = try tempFolder()
    let event = TimelineRow.event("run_started", at: t0, elapsed: 0)
    let first = try TimelineWriter(folder: folder)
    try first.append(event)
    first.close()
    let second = try TimelineWriter(folder: folder)
    try second.append(event)
    second.close()
    let csv = try String(contentsOf: folder.appending(path: "timeline.csv"), encoding: .utf8)
    #expect(csv.components(separatedBy: "\n").filter { $0 == TimelineCSV.header }.count == 1)
    #expect(try TimelineCSV.read(fileAt: folder.appending(path: "timeline.csv")).count == 2)
}

@Test func readSkipsATornLastLine() throws {
    let folder = try tempFolder()
    let writer = try TimelineWriter(folder: folder)
    try writer.append(.event("run_started", at: t0, elapsed: 0))
    writer.close()
    let url = folder.appending(path: "timeline.csv")
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("2026-11-16T14:02:15.250-07:00,1.000,sig".utf8))
    try handle.close()
    #expect(try TimelineCSV.read(fileAt: url).map(\.text) == ["run_started"])
}
