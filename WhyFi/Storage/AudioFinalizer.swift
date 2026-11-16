import AVFoundation

/// Turns the `audio.caf` written while recording into a smaller `audio.m4a`. CAF is used
/// while recording because it stays readable if the app dies mid-write.
enum AudioFinalizer {
    enum Failure: Error {
        case noExportSession
    }

    static func convertToM4A(_ caf: URL) async throws -> URL {
        let m4a = caf.deletingLastPathComponent().appending(path: "audio.m4a")
        try? FileManager.default.removeItem(at: m4a)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: caf), presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.noExportSession
        }
        try await session.export(to: m4a, as: .m4a)
        try FileManager.default.removeItem(at: caf)
        return m4a
    }
}
