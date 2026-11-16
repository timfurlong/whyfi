import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Listens to the microphone, writes the audio to the run's folder, and transcribes it live
/// with Apple's SpeechAnalyzer. The approach (feeding an `AsyncStream<AnalyzerInput>` and
/// accumulating results by time range) follows Muesli's live captions.
///
/// Recording starts as soon as the microphone is allowed. Getting the speech model ready can
/// take ten seconds or more on the first run after launch, so the audio from that time is
/// queued and transcribed once the model is ready, and kept on disk even if it never is.
final class SpeechRecorder: SpeechSource, @unchecked Sendable {
    private let lock = NSLock()
    private var session: Session?

    /// The format audio is recorded in, and fed to the transcriber in when it accepts it.
    private static let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                       channels: 1, interleaved: true)!

    /// A recorded buffer handed from the audio thread to the transcriber. Each buffer is
    /// freshly allocated and never touched again by the audio thread once sent.
    private struct Recorded: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    /// Everything one recording needs, shared with the audio thread.
    private final class Session: @unchecked Sendable {
        let engine: AVAudioEngine
        let converter: AVAudioConverter
        let caf: URL
        let buffers: AsyncStream<Recorded>.Continuation
        let updates: AsyncStream<SpeechUpdate>.Continuation
        var transcription: Task<Void, Never>?

        private let fileLock = NSLock()
        private var file: AVAudioFile?
        private var _anchor: Date?

        /// Wall-clock time of the first audio buffer; sentence times are offsets from it.
        var anchor: Date? { fileLock.withLock { _anchor } }

        init(engine: AVAudioEngine, converter: AVAudioConverter, caf: URL, file: AVAudioFile,
             buffers: AsyncStream<Recorded>.Continuation, updates: AsyncStream<SpeechUpdate>.Continuation) {
            self.engine = engine
            self.converter = converter
            self.caf = caf
            self.file = file
            self.buffers = buffers
            self.updates = updates
        }

        /// Called on the audio thread with each converted buffer.
        func record(_ buffer: AVAudioPCMBuffer, startedAt: Date) {
            fileLock.withLock {
                if _anchor == nil { _anchor = startedAt }
                try? file?.write(from: buffer)
            }
            buffers.yield(Recorded(buffer: buffer))
        }

        func closeFile() { fileLock.withLock { file = nil } }
    }

    func start(folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> AsyncStream<SpeechUpdate> {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw SpeechSourceError.microphoneDenied }

        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: Self.recordingFormat) else {
            throw SpeechSourceError.unavailable("No microphone input is available")
        }
        let caf = folder.appending(path: "audio.caf")
        let file = try AVAudioFile(forWriting: caf, settings: Self.recordingFormat.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        let (updates, updatesContinuation) = AsyncStream<SpeechUpdate>.makeStream()
        let (buffers, buffersContinuation) = AsyncStream<Recorded>.makeStream()
        let session = Session(engine: engine, converter: converter, caf: caf, file: file,
                              buffers: buffersContinuation, updates: updatesContinuation)

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            Self.process(buffer, in: session)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw SpeechSourceError.unavailable("Couldn't start the microphone: \(error.localizedDescription)")
        }
        lock.withLock { self.session = session }

        updatesContinuation.yield(.preparing(progress: 0))
        session.transcription = Task {
            await Self.transcribe(buffers, in: session, progress: progress)
        }
        return updates
    }

    func stop() async {
        guard let session = lock.withLock({ () -> Session? in
            defer { self.session = nil }
            return self.session
        }) else { return }
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.buffers.finish()
        // Lets the transcriber finish the queued audio and finalize the last sentence.
        await session.transcription?.value
        session.closeFile()
        session.updates.finish()
        _ = try? await AudioFinalizer.convertToM4A(session.caf)
    }

    /// Gets the model ready, then transcribes every buffer recorded so far and from then on.
    private static func transcribe(_ buffers: AsyncStream<Recorded>, in session: Session,
                                   progress: @escaping @Sendable (Double) -> Void) async {
        let updates = session.updates
        do {
            let locale = try await SpeechModel.prepare(locale: Locale(identifier: "en-US")) { fraction in
                progress(fraction)
                updates.yield(.preparing(progress: fraction))
            }
            let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            let analyzer = SpeechAnalyzer(modules: [transcriber],
                                          options: .init(priority: .userInitiated, modelRetention: .lingering))
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber], considering: recordingFormat) ?? recordingFormat
            try await analyzer.prepareToAnalyze(in: format)
            let converter = format == recordingFormat ? nil : AVAudioConverter(from: recordingFormat, to: format)

            let (inputs, inputsContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            let analysis = Task { try await analyzer.analyzeSequence(inputs) }
            let results = Task {
                var accumulator = TranscriptAccumulator()
                for try await result in transcriber.results {
                    let finished = accumulator.receive(
                        text: String(result.text.characters), isFinal: result.isFinal,
                        start: CMTimeGetSeconds(result.range.start),
                        end: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)))
                    let anchor = session.anchor ?? Date()
                    for segment in finished {
                        updates.yield(.final(Sentence(
                            start: anchor.addingTimeInterval(segment.start),
                            end: anchor.addingTimeInterval(segment.end), text: segment.text)))
                    }
                    updates.yield(.volatile(accumulator.volatileText))
                }
            }
            updates.yield(.listening)

            for await recorded in buffers {
                if let converter {
                    guard let converted = convert(recorded.buffer, with: converter, to: format) else { continue }
                    inputsContinuation.yield(AnalyzerInput(buffer: converted))
                } else {
                    inputsContinuation.yield(AnalyzerInput(buffer: recorded.buffer))
                }
            }
            inputsContinuation.finish()
            _ = try await analysis.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await results.value
        } catch {
            let reason = (error as? SpeechSourceError)?.reason ?? error.localizedDescription
            updates.yield(.failed("Transcription stopped: \(reason)"))
            // Keep draining so the audio thread never backs up; the audio is still saved.
            for await _ in buffers {}
        }
    }

    /// Runs on the audio thread for every microphone buffer.
    private static func process(_ buffer: AVAudioPCMBuffer, in session: Session) {
        let startedAt = Date().addingTimeInterval(-Double(buffer.frameLength) / buffer.format.sampleRate)
        guard let converted = convert(buffer, with: session.converter, to: recordingFormat) else { return }
        session.record(converted, startedAt: startedAt)
        session.updates.yield(.level(level(of: buffer)))
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return nil }
        return converted
    }

    /// RMS level mapped from -50...0 dBFS to 0...1.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 50) / 50, 0), 1)
    }

    // MARK: - Files (used by tests, and handy for re-transcribing)

    /// Transcribes an audio file with the same model and settings as live recording.
    static func transcribe(file url: URL) async throws -> [TranscriptSegment] {
        let locale = try await SpeechModel.prepare(locale: Locale(identifier: "en-US")) { _ in }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: .init(priority: .userInitiated, modelRetention: .lingering))
        let audio = try AVAudioFile(forReading: url)
        async let collected: [TranscriptSegment] = {
            var accumulator = TranscriptAccumulator()
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                segments += accumulator.receive(
                    text: String(result.text.characters), isFinal: result.isFinal,
                    start: CMTimeGetSeconds(result.range.start),
                    end: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)))
            }
            return segments
        }()
        if let last = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected
    }
}
