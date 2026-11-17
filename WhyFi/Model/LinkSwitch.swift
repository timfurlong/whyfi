import Foundation

/// A moment the Mac moved to another Wi-Fi band, or to another access point on the same band.
struct LinkSwitch: Equatable, Sendable {
    var time: Date
    /// The band after the switch.
    var band: WiFiBand
    /// False when the band stayed the same and only the access point changed.
    var bandChanged: Bool

    /// The least time between two labels on a chart that shows `span` seconds: about an eighth of
    /// the chart's width, so labels never overlap, and never under 15 s.
    static func labelGap(forSpan span: TimeInterval) -> TimeInterval {
        max(15, span / 8)
    }

    /// Which switches get a label on the chart, so labels don't pile up when the Mac flaps between
    /// bands. Band switches come first: the first one, then each one at least `minGap` after the
    /// last labeled one. An access point switch gets a label only when it's at least `minGap` from
    /// every labeled switch, so it never takes a band switch's place.
    static func labeled(_ switches: [LinkSwitch], minGap: TimeInterval = 15) -> [Bool] {
        var result = Array(repeating: false, count: switches.count)
        var labeledTimes: [Date] = []
        for (index, change) in switches.enumerated() where change.bandChanged {
            if let last = labeledTimes.last, change.time.timeIntervalSince(last) < minGap { continue }
            labeledTimes.append(change.time)
            result[index] = true
        }
        for (index, change) in switches.enumerated() where !change.bandChanged {
            if labeledTimes.contains(where: { abs($0.timeIntervalSince(change.time)) < minGap }) { continue }
            labeledTimes.append(change.time)
            result[index] = true
        }
        return result
    }
}

/// The band a run spent the most time on, and how often it changed band.
struct BandSummary: Equatable, Sendable {
    var band: WiFiBand
    /// The channel of the last reading on that band.
    var channel: Int
    var switchCount: Int
}
