import Foundation

/// A run's data in the shapes the window draws, whether it's being recorded or read back.
struct LoadedRun: Sendable {
    var info: RunInfo
    var readings: [SignalReading]
    var speedTests: [SpeedTestResult]
    var sentences: [Sentence]
    var events: [TimelineRow]

    /// The sentence started nearest `time`, if one started within 15 s of it.
    func nearestSentence(to time: Date) -> Sentence? {
        sentences.min { abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time)) }
            .flatMap { abs($0.start.timeIntervalSince(time)) <= 15 ? $0 : nil }
    }

    /// Readings split wherever more than 3 s passed between two of them (Wi-Fi was off),
    /// so the chart draws a gap instead of a line across it.
    static func segments(_ readings: [SignalReading]) -> [[SignalReading]] {
        var result: [[SignalReading]] = []
        for reading in readings {
            if let last = result.last?.last, reading.time.timeIntervalSince(last.time) <= 3 {
                result[result.count - 1].append(reading)
            } else {
                result.append([reading])
            }
        }
        return result
    }
}

enum RunLoader {
    static func load(_ run: RunSummary) throws -> LoadedRun {
        let url = run.folder.appending(path: "timeline.csv")
        let rows = FileManager.default.fileExists(atPath: url.path) ? try TimelineCSV.read(fileAt: url) : []
        var loaded = LoadedRun(info: run.info, readings: [], speedTests: [], sentences: [], events: [])
        for row in rows {
            switch row.kind {
            case .signal:
                guard let rssi = row.rssi else { continue }
                loaded.readings.append(SignalReading(
                    time: row.time, rssi: rssi, noise: row.noise ?? 0, txRate: row.txRate ?? 0,
                    channel: row.channel ?? 0, band: row.band.flatMap(WiFiBand.init(rawValue:)) ?? .unknown,
                    widthMHz: row.widthMHz ?? 0, bssid: row.bssid))
            case .speed:
                guard let mbps = row.downloadMbps else { continue }
                loaded.speedTests.append(SpeedTestResult(
                    start: row.time, end: row.endTime ?? row.time, downloadMbps: mbps,
                    responsivenessRPM: row.responsivenessRPM ?? 0))
            case .speech:
                guard let text = row.text else { continue }
                loaded.sentences.append(Sentence(start: row.time, end: row.endTime ?? row.time, text: text))
            case .event:
                loaded.events.append(row)
            }
        }
        return loaded
    }
}
