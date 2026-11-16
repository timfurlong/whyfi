import Foundation

/// A finished download speed test.
struct SpeedTestResult: Equatable, Sendable {
    var start: Date
    var end: Date
    var downloadMbps: Double
    /// networkQuality's responsiveness under load, in round trips per minute.
    var responsivenessRPM: Int

    private struct Output: Decodable {
        var dl_throughput: Double
        var dl_responsiveness: Double?
    }

    /// Reads the JSON that `networkQuality -c` prints.
    static func parse(_ json: Data, start: Date, end: Date) throws -> SpeedTestResult {
        let out = try JSONDecoder().decode(Output.self, from: json)
        return SpeedTestResult(start: start, end: end, downloadMbps: out.dl_throughput / 1_000_000,
                               responsivenessRPM: Int((out.dl_responsiveness ?? 0).rounded()))
    }
}

enum SpeedTestError: Error, Equatable, Sendable {
    case timedOut
    /// The run stopped while the test was running.
    case cancelled
    case exited(Int32)
    case unreadableOutput
    case launchFailed(String)

    /// Goes in the `speed_test_failed: <reason>` event.
    var reason: String {
        switch self {
        case .timedOut: "timed out"
        case .cancelled: "cancelled"
        case .exited(let status): "networkQuality exited with \(status)"
        case .unreadableOutput: "networkQuality printed something unreadable"
        case .launchFailed(let message): "couldn't start networkQuality: \(message)"
        }
    }
}
