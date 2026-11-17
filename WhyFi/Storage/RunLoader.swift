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

    /// Readings split wherever more than 3 s passed between two of them (Wi-Fi was off), so the
    /// chart draws a gap instead of a line across it, and wherever the band changed, so each
    /// stretch can take its band's color. A reading on an unknown band doesn't split anything.
    static func segments(_ readings: [SignalReading]) -> [[SignalReading]] {
        var result: [[SignalReading]] = []
        var segmentBand: WiFiBand?
        for reading in readings {
            let bandChanged = reading.band != .unknown && segmentBand != nil && reading.band != segmentBand
            if let last = result.last?.last, reading.time.timeIntervalSince(last.time) <= 3, !bandChanged {
                result[result.count - 1].append(reading)
            } else {
                result.append([reading])
                segmentBand = nil
            }
            if reading.band != .unknown { segmentBand = reading.band }
        }
        return result
    }

    /// Every change of band, or of access point on the same band, from one reading to the next.
    /// Readings on an unknown band and readings without a BSSID are skipped for the comparison.
    static func switches(_ readings: [SignalReading]) -> [LinkSwitch] {
        var result: [LinkSwitch] = []
        var lastBand: WiFiBand?
        var lastBSSID: String?
        for reading in readings {
            let band = reading.band == .unknown ? nil : reading.band
            if let band, let lastBand, band != lastBand {
                result.append(LinkSwitch(time: reading.time, band: band, bandChanged: true))
            } else if let bssid = reading.bssid, let lastBSSID, bssid != lastBSSID, let current = band ?? lastBand {
                result.append(LinkSwitch(time: reading.time, band: current, bandChanged: false))
            }
            if let band { lastBand = band }
            if let bssid = reading.bssid { lastBSSID = bssid }
        }
        return result
    }

    /// The band with the most readings, its channel and how many times the band changed;
    /// nil when no reading has a known band.
    static func bandSummary(_ readings: [SignalReading]) -> BandSummary? {
        let known = readings.filter { $0.band != .unknown }
        let counts = Dictionary(grouping: known, by: \.band).mapValues(\.count)
        guard let band = counts.max(by: { $0.value < $1.value })?.key,
              let channel = known.last(where: { $0.band == band })?.channel else { return nil }
        return BandSummary(band: band, channel: channel, switchCount: switches(readings).filter(\.bandChanged).count)
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
