import Foundation

/// The contents of a run's `run.json`.
struct RunInfo: Codable, Equatable, Sendable {
    struct Permissions: Codable, Equatable, Sendable {
        var microphone: Bool
        var speech: Bool
        var location: Bool
    }

    var name: String
    var startedAt: Date
    /// `nil` while recording, or forever if the app quit or crashed mid-run.
    var endedAt: Date?
    var appVersion: String
    var macOSVersion: String
    var macModel: String
    var wifiInterface: String?
    var speedTestMode: SpeedTestMode
    var locale: String
    var permissions: Permissions

    // Spelled out because the snake-case strategies turn `macOSVersion` into `mac_os_version`
    // on the way out but `macOsVersion` on the way back in.
    enum CodingKeys: String, CodingKey {
        case name, locale, permissions
        case startedAt = "started_at", endedAt = "ended_at", appVersion = "app_version"
        case macOSVersion = "macos_version", macModel = "mac_model", wifiInterface = "wifi_interface"
        case speedTestMode = "speed_test_mode"
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
