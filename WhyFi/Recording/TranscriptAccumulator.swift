// Adapted from AppleSpeechTranscriptAccumulator in Muesli
// (https://github.com/Muesli-HQ/muesli, native/MuesliNative/Sources/MuesliNativeApp/AppleSpeechAnalyzerBackend.swift).
//
// MIT License. Copyright (c) 2026 Pranav Hari.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions: The above copyright notice
// and this permission notice shall be included in all copies or substantial portions of the
// Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

/// A finished piece of transcript, in seconds from the start of the audio.
struct TranscriptSegment: Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

/// Turns SpeechTranscriber's stream of results into finished segments plus the words still in
/// progress. A result replaces any earlier unfinished result whose time range it overlaps.
struct TranscriptAccumulator: Sendable {
    private var volatiles: [TranscriptSegment] = []

    /// The words still being recognized, in time order.
    var volatileText: String {
        volatiles.sorted { $0.start < $1.start }.map(\.text).joined(separator: " ")
    }

    /// Takes one result and returns the segments that just became final.
    mutating func receive(text: String, isFinal: Bool, start: Double, end: Double) -> [TranscriptSegment] {
        let safeStart = start.isFinite ? max(0, start) : 0
        let safeEnd = end.isFinite ? max(safeStart, end) : safeStart
        volatiles.removeAll { Self.overlaps($0.start, $0.end, safeStart, safeEnd) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let segment = TranscriptSegment(start: safeStart, end: safeEnd, text: trimmed)
        if isFinal { return [segment] }
        volatiles.append(segment)
        return []
    }

    private static func overlaps(_ start: Double, _ end: Double, _ otherStart: Double, _ otherEnd: Double) -> Bool {
        if start == end || otherStart == otherEnd { return start == otherStart }
        return start < otherEnd && otherStart < end
    }
}
