import Foundation
import Speech

/// Makes sure Apple's on-device speech model for a language is downloaded and reserved.
/// macOS manages the model; the first run downloads it.
enum SpeechModel {
    static func prepare(locale requested: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechSourceError.unavailable("Apple's on-device speech recognition isn't available on this Mac")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw SpeechSourceError.unavailable("Speech recognition for \(requested.identifier) isn't supported on this Mac")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        // Reserving keeps macOS from removing the model while WhyFi uses it. It fails when the
        // Mac already has its limit of reserved languages; the download below still works then.
        _ = try? await AssetInventory.reserve(locale: locale)

        if await AssetInventory.status(forModules: [transcriber]) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let download = request.progress
            let reporter = Task {
                while !Task.isCancelled && !download.isFinished {
                    progress(min(max(download.fractionCompleted, 0), 1))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { reporter.cancel() }
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechSourceError.unavailable("Apple's English speech model didn't finish downloading")
        }
        progress(1)
        return locale
    }
}
