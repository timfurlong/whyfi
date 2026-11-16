import AVFoundation
import CoreWLAN
import Foundation
import Testing
@testable import WhyFi

@Test func convertsCAFToM4A() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "whyfi-audio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let caf = folder.appending(path: "audio.caf")
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
    do {
        let file = try AVAudioFile(forWriting: caf, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let samples = try #require(buffer.int16ChannelData?[0])
        for i in 0..<16_000 { samples[i] = Int16(sin(Double(i) * 2 * .pi * 440 / 16_000) * 8_000) }
        try file.write(from: buffer)
    }

    let m4a = try await AudioFinalizer.convertToM4A(caf)

    #expect(m4a == folder.appending(path: "audio.m4a"))
    #expect(!FileManager.default.fileExists(atPath: caf.path))
    let duration = try await AVURLAsset(url: m4a).load(.duration).seconds
    #expect(abs(duration - 1) < 0.1)
}

@Test func wifiBandsAndWidthsMap() {
    #expect(WiFiMonitor.band(.band2GHz) == .ghz2_4)
    #expect(WiFiMonitor.band(.band5GHz) == .ghz5)
    #expect(WiFiMonitor.band(.band6GHz) == .ghz6)
    #expect(WiFiMonitor.width(.width20MHz) == 20)
    #expect(WiFiMonitor.width(.width80MHz) == 80)
    #expect(WiFiMonitor.width(.width160MHz) == 160)
}
