import Foundation

/// Appends rows to a run's `timeline.csv`, and sentences to its `transcript.txt`, as they
/// happen, so a crash loses nothing that was already recorded.
final class TimelineWriter {
    private let timeline: FileHandle
    private let transcript: FileHandle
    private let clock: DateFormatter
    private let timeZone: TimeZone

    init(folder: URL, timeZone: TimeZone = .current) throws {
        let timelineURL = folder.appending(path: "timeline.csv")
        let transcriptURL = folder.appending(path: "transcript.txt")
        let fm = FileManager.default
        let isNew = (try? timelineURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 == 0
        if !fm.fileExists(atPath: timelineURL.path) { fm.createFile(atPath: timelineURL.path, contents: nil) }
        if !fm.fileExists(atPath: transcriptURL.path) { fm.createFile(atPath: transcriptURL.path, contents: nil) }
        timeline = try FileHandle(forWritingTo: timelineURL)
        transcript = try FileHandle(forWritingTo: transcriptURL)
        try timeline.seekToEnd()
        try transcript.seekToEnd()
        clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "HH:mm:ss"
        self.timeZone = timeZone
        if isNew { try timeline.write(contentsOf: Data((TimelineCSV.header + "\n").utf8)) }
    }

    func append(_ row: TimelineRow) throws {
        try timeline.write(contentsOf: Data((TimelineCSV.line(for: row, timeZone: timeZone) + "\n").utf8))
        if row.kind == .speech, let text = row.text {
            try transcript.write(contentsOf: Data("[\(clock.string(from: row.time))] \(text)\n".utf8))
        }
    }

    func close() {
        try? timeline.close()
        try? transcript.close()
    }
}
