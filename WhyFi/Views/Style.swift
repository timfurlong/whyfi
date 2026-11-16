import SwiftUI

extension SignalBand {
    var color: Color {
        switch self {
        case .good: .green
        case .ok: .orange
        case .poor: .red
        }
    }
}

extension SignalQuality {
    var color: Color { band.color }
}

enum Palette {
    static let signal = Color.blue
    static let speed = Color.teal
    static let narration = Color.orange
}

enum Format {
    /// "6:12", or "1:02:03" past an hour.
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "2:44:08 PM"
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    /// "Today 2:41 PM", "Yesterday 9:05 AM", or "Nov 12, 2:41 PM".
    static func runStart(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + ", " + time
    }

    static func mbps(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    /// The last two octets of a BSSID, enough to tell access points apart: "c3:9e".
    static func shortBSSID(_ bssid: String) -> String {
        bssid.split(separator: ":").suffix(2).joined(separator: ":")
    }
}
