import Foundation

/// The Wi-Fi band the Mac is connected on.
enum WiFiBand: String, Codable, Sendable {
    case ghz2_4 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"
    case unknown = "?"
}

/// One reading of the Wi-Fi link, taken once a second while a run records.
struct SignalReading: Equatable, Sendable {
    var time: Date
    /// Received signal strength, in dBm.
    var rssi: Int
    /// Background noise, in dBm.
    var noise: Int
    /// The link's current transmit rate, in Mbps.
    var txRate: Double
    var channel: Int
    var band: WiFiBand
    var widthMHz: Int
    /// The access point's BSSID. macOS only reveals it to apps with Location access.
    var bssid: String?
}
