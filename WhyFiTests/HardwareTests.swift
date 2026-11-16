import Foundation
import Testing
@testable import WhyFi

/// Tests that need this Mac's Wi-Fi and Apple's speech model. Run them with
/// `TEST_RUNNER_WHYFI_HARDWARE_TESTS=1 scripts/test`.
private let hardware = ProcessInfo.processInfo.environment["WHYFI_HARDWARE_TESTS"] == "1"

@Test(.enabled(if: hardware))
func wifiMonitorReadsThisMac() throws {
    let monitor = WiFiMonitor()
    #expect(monitor.interfaceName != nil)
    let reading = try #require(monitor.read(at: Date()))
    #expect((-100)...(-20) ~= reading.rssi)
    #expect(reading.channel > 0)
}

@Test(.enabled(if: hardware), .timeLimit(.minutes(5)))
func transcribesSpokenFile() async throws {
    let aiff = FileManager.default.temporaryDirectory.appending(path: "whyfi-say-\(UUID().uuidString).aiff")
    let say = Process()
    say.executableURL = URL(filePath: "/usr/bin/say")
    say.arguments = ["-o", aiff.path, "Standing right next to the dryer."]
    try say.run()
    say.waitUntilExit()
    #expect(say.terminationStatus == 0)

    let segments = try await SpeechRecorder.transcribe(file: aiff)

    let text = segments.map(\.text).joined(separator: " ").lowercased()
    #expect(text.contains("dryer"))
    #expect(segments.allSatisfy { $0.end >= $0.start })
}
