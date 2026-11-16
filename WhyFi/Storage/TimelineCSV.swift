import Foundation

/// Reads and writes the rows of `timeline.csv`.
enum TimelineCSV {
    static let header = "time,elapsed_s,kind,rssi_dbm,noise_dbm,tx_rate_mbps,channel,band,width_mhz,bssid,download_mbps,responsiveness_rpm,text,end_time"

    enum ParseError: Error, Equatable {
        case wrongFieldCount(Int)
        case badValue(column: String, value: String)
    }

    static func line(for row: TimelineRow, timeZone: TimeZone = .current) -> String {
        let fields: [String] = [
            formatDate(row.time, timeZone),
            String(format: "%.3f", row.elapsed),
            row.kind.rawValue,
            row.rssi.map(String.init) ?? "",
            row.noise.map(String.init) ?? "",
            row.txRate.map { String(format: "%.1f", $0) } ?? "",
            row.channel.map(String.init) ?? "",
            row.band ?? "",
            row.widthMHz.map(String.init) ?? "",
            row.bssid ?? "",
            row.downloadMbps.map { String(format: "%.1f", $0) } ?? "",
            row.responsivenessRPM.map(String.init) ?? "",
            row.text ?? "",
            row.endTime.map { formatDate($0, timeZone) } ?? "",
        ]
        return fields.map(quoted).joined(separator: ",")
    }

    static func parse(line: String) throws -> TimelineRow {
        let f = splitFields(line)
        guard f.count == 14 else { throw ParseError.wrongFieldCount(f.count) }
        func int(_ i: Int, _ column: String) throws -> Int? {
            if f[i].isEmpty { return nil }
            guard let v = Int(f[i]) else { throw ParseError.badValue(column: column, value: f[i]) }
            return v
        }
        func double(_ i: Int, _ column: String) throws -> Double? {
            if f[i].isEmpty { return nil }
            guard let v = Double(f[i]) else { throw ParseError.badValue(column: column, value: f[i]) }
            return v
        }
        func date(_ i: Int, _ column: String) throws -> Date? {
            if f[i].isEmpty { return nil }
            guard let v = parseDate(f[i]) else { throw ParseError.badValue(column: column, value: f[i]) }
            return v
        }
        func string(_ i: Int) -> String? { f[i].isEmpty ? nil : f[i] }

        guard let time = try date(0, "time") else { throw ParseError.badValue(column: "time", value: "") }
        guard let elapsed = try double(1, "elapsed_s") else { throw ParseError.badValue(column: "elapsed_s", value: "") }
        guard let kind = TimelineKind(rawValue: f[2]) else { throw ParseError.badValue(column: "kind", value: f[2]) }
        return TimelineRow(
            time: time, elapsed: elapsed, kind: kind,
            rssi: try int(3, "rssi_dbm"), noise: try int(4, "noise_dbm"),
            txRate: try double(5, "tx_rate_mbps"), channel: try int(6, "channel"),
            band: string(7), widthMHz: try int(8, "width_mhz"), bssid: string(9),
            downloadMbps: try double(10, "download_mbps"),
            responsivenessRPM: try int(11, "responsiveness_rpm"),
            text: string(12), endTime: try date(13, "end_time"))
    }

    /// Every row in the file, sorted by `time`. Sentences reach the file a moment after
    /// they're spoken, so the file itself isn't in time order. A line that doesn't parse
    /// (half-written when the Mac lost power, say) is skipped rather than losing the run.
    static func read(fileAt url: URL) throws -> [TimelineRow] {
        let content = try String(decoding: Data(contentsOf: url), as: UTF8.self)
        let rows = content.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0 != header && !$0.isEmpty }
            .compactMap { try? parse(line: $0) }
        return rows.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }

    // MARK: - Helpers

    // ISO8601DateFormatter is thread-safe, and making one per row was most of the cost of
    // reading a run back.
    nonisolated(unsafe) private static let parser = makeFormatter(.current)
    nonisolated(unsafe) private static let localFormatter = makeFormatter(.current)

    private static func makeFormatter(_ timeZone: TimeZone) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = timeZone
        return f
    }

    private static func formatDate(_ date: Date, _ timeZone: TimeZone) -> String {
        (timeZone == .current ? localFormatter : makeFormatter(timeZone)).string(from: date)
    }

    private static func parseDate(_ s: String) -> Date? {
        parser.date(from: s)
    }

    /// RFC 4180 quoting. Newlines become spaces so every row stays on one line.
    private static func quoted(_ field: String) -> String {
        let flat = field.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard flat.contains(",") || flat.contains("\"") else { return flat }
        return "\"" + flat.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func splitFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = line.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        fields.append(current)
        return fields
    }
}
