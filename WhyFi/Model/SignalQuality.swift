/// The word shown next to a signal reading.
enum SignalQuality: CaseIterable, Sendable {
    case excellent, good, ok, weak, poor, bad

    init(dBm: Int) {
        switch dBm {
        case (-55)...: self = .excellent
        case (-65)...: self = .good
        case (-70)...: self = .ok
        case (-75)...: self = .weak
        case (-80)...: self = .poor
        default: self = .bad
        }
    }

    var label: String {
        switch self {
        case .excellent: "excellent"
        case .good: "good"
        case .ok: "OK"
        case .weak: "weak"
        case .poor: "poor"
        case .bad: "bad"
        }
    }

    /// The chart band (and color) this word belongs to.
    var band: SignalBand {
        switch self {
        case .excellent, .good: .good
        case .ok, .weak: .ok
        case .poor, .bad: .poor
        }
    }
}

/// The three colored bands behind the signal chart.
enum SignalBand: Sendable {
    case good, ok, poor

    /// Readings at or above this many dBm are in the good band.
    static let goodFloor = -65
    /// Readings at or above this many dBm (and below `goodFloor`) are in the OK band.
    static let okFloor = -75
}
