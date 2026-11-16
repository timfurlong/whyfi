import Foundation

/// Where a run's Wi-Fi readings come from.
protocol SignalSource: Sendable {
    /// The Wi-Fi interface's BSD name (`en0`), which speed tests bind to.
    var interfaceName: String? { get }
    /// The current reading, or `nil` when Wi-Fi is off or disconnected.
    func read(at time: Date) -> SignalReading?
}

/// A finished sentence of narration, in wall-clock time.
struct Sentence: Identifiable, Equatable, Sendable {
    let id: UUID
    var start: Date
    var end: Date
    var text: String

    init(id: UUID = UUID(), start: Date, end: Date, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

enum SpeechUpdate: Sendable {
    /// Apple's speech model is downloading or getting ready.
    case preparing(progress: Double)
    case listening
    /// Words still being recognized.
    case volatile(String)
    case final(Sentence)
    /// Microphone level, 0 to 1.
    case level(Float)
    /// Transcription stopped working mid-run.
    case failed(String)
}

enum SpeechSourceError: Error, Equatable, Sendable {
    case microphoneDenied
    case unavailable(String)

    var reason: String {
        switch self {
        case .microphoneDenied: "Microphone access denied"
        case .unavailable(let reason): reason
        }
    }
}

/// Listens to the microphone, saves the audio into a run's folder and transcribes it.
protocol SpeechSource: AnyObject, Sendable {
    /// Starts listening. `progress` reports the speech model's download (0 to 1) while
    /// this is still waiting, before the update stream exists.
    func start(folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> AsyncStream<SpeechUpdate>
    func stop() async
}

enum LocationAccess: Sendable {
    case granted, denied, undetermined
}

@MainActor
protocol PermissionChecking {
    /// Whether macOS gives this app Location access, which it needs to reveal the BSSID.
    var location: LocationAccess { get }
}

enum SpeechStatus: Equatable, Sendable {
    case off
    case preparing(Double)
    case listening
    case unavailable(String)
}
