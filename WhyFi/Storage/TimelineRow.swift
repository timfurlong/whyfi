import Foundation

/// What a row in `timeline.csv` records.
enum TimelineKind: String, Sendable {
    /// The once-a-second Wi-Fi reading.
    case signal
    /// A finished download speed test.
    case speed
    /// A finished sentence of narration.
    case speech
    /// Something that happened: the run started or stopped, Wi-Fi dropped, a test failed.
    case event
}

/// One row of `timeline.csv`. Which fields are filled depends on `kind`.
struct TimelineRow: Equatable, Sendable {
    /// When it happened. For a speed test or a sentence, when it started.
    var time: Date
    /// Seconds since the run started.
    var elapsed: Double
    var kind: TimelineKind
    var rssi: Int?
    var noise: Int?
    var txRate: Double?
    var channel: Int?
    var band: String?
    var widthMHz: Int?
    var bssid: String?
    var downloadMbps: Double?
    var responsivenessRPM: Int?
    var text: String?
    /// When a speed test or a sentence ended.
    var endTime: Date?

    init(time: Date, elapsed: Double, kind: TimelineKind, rssi: Int? = nil, noise: Int? = nil,
         txRate: Double? = nil, channel: Int? = nil, band: String? = nil, widthMHz: Int? = nil,
         bssid: String? = nil, downloadMbps: Double? = nil, responsivenessRPM: Int? = nil,
         text: String? = nil, endTime: Date? = nil) {
        self.time = time
        self.elapsed = elapsed
        self.kind = kind
        self.rssi = rssi
        self.noise = noise
        self.txRate = txRate
        self.channel = channel
        self.band = band
        self.widthMHz = widthMHz
        self.bssid = bssid
        self.downloadMbps = downloadMbps
        self.responsivenessRPM = responsivenessRPM
        self.text = text
        self.endTime = endTime
    }

    static func signal(_ r: SignalReading, elapsed: Double) -> TimelineRow {
        TimelineRow(time: r.time, elapsed: elapsed, kind: .signal, rssi: r.rssi, noise: r.noise,
                    txRate: r.txRate, channel: r.channel, band: r.band.rawValue,
                    widthMHz: r.widthMHz, bssid: r.bssid)
    }

    static func event(_ text: String, at time: Date, elapsed: Double) -> TimelineRow {
        TimelineRow(time: time, elapsed: elapsed, kind: .event, text: text)
    }
}
