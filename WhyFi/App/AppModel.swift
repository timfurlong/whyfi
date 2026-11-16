import Foundation
import Observation

/// Owns the runs on disk, the recorder and the window's selection.
@MainActor @Observable
final class AppModel {
    static let speedTestModeKey = "speedTestMode"

    let store: RunStore
    let recorder: RunRecorder
    let location: LocationPermission
    var selection: URL?
    var showingNewRun = false
    var startError: String?
    @ObservationIgnored private let cache = RunCache()

    init() {
        let store = RunStore()
        let location = LocationPermission()
        self.store = store
        self.location = location
        recorder = RunRecorder(store: store, signal: WiFiMonitor(), speed: NetworkQualityRunner(),
                               speech: SpeechRecorder(), permissions: location,
                               mode: { AppModel.speedTestMode })
        selection = store.runs.first?.folder
    }

    static var speedTestMode: SpeedTestMode {
        UserDefaults.standard.string(forKey: speedTestModeKey).flatMap(SpeedTestMode.init(rawValue:)) ?? .backToBack
    }

    /// Opens the New Run sheet. The first time, this is also when macOS asks for Location.
    func newRun() {
        guard !recorder.isRecording else { return }
        location.request()
        showingNewRun = true
    }

    /// Starts recording. The new run is selected as soon as its folder exists (the window
    /// watches `recorder.folder`), while the microphone and speech model get ready.
    func startRun(named name: String) async {
        showingNewRun = false
        do {
            try await recorder.start(name: name)
        } catch {
            startError = error.localizedDescription
        }
    }

    func stopRun() async {
        await recorder.stop()
        store.reload()
    }

    /// The live recording if `folder` is being recorded, else the run read back from disk.
    func loadedRun(for folder: URL) -> LoadedRun? {
        guard let run = store.runs.first(where: { $0.folder == folder }) else { return nil }
        if recorder.isRecording, folder == recorder.folder {
            return LoadedRun(info: run.info, readings: recorder.readings, speedTests: recorder.speedTests,
                             sentences: recorder.sentences, events: recorder.events)
        }
        return cache.run(for: run)
    }
}
