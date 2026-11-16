/// How often a run tests download speed.
enum SpeedTestMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case backToBack = "back_to_back"
    case every30Seconds = "every_30_seconds"
    case off

    var id: String { rawValue }

    /// How long to wait after a test finishes before starting the next. `nil` means no tests.
    var pauseAfterTest: Duration? {
        switch self {
        case .backToBack: .seconds(1)
        case .every30Seconds: .seconds(30)
        case .off: nil
        }
    }

    var title: String {
        switch self {
        case .backToBack: "Back to back"
        case .every30Seconds: "Every 30 seconds"
        case .off: "Off"
        }
    }
}
