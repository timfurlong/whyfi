import SwiftUI

/// One run: banners while recording, the numbers, the chart and the transcript.
struct RunDetailView: View {
    let run: LoadedRun
    /// Set while this run is the one being recorded.
    let recorder: RunRecorder?
    @State private var selectedTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let recorder {
                StatusBanners(recorder: recorder).padding(.top, 10)
            }
            NumbersRow(run: run, live: recorder != nil)
            Divider()
            HStack(spacing: 0) {
                chart
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minWidth: 420, maxWidth: .infinity)
                Divider()
                TranscriptView(sentences: run.sentences,
                               highlighted: selectedTime.flatMap { run.nearestSentence(to: $0)?.id },
                               volatileText: recorder.map(\.volatileText),
                               selectedTime: $selectedTime)
                    .frame(width: 300)
            }
        }
        .navigationTitle(run.info.name)
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private var chart: some View {
        if recorder != nil {
            // Redraw every second so the time axis keeps moving even between readings.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RunChart(run: run, domain: domain(endingAt: context.date), selectedTime: $selectedTime)
            }
        } else {
            RunChart(run: run, domain: domain(endingAt: run.info.endedAt ?? lastTime), selectedTime: $selectedTime)
        }
    }

    private var lastTime: Date {
        [run.readings.last?.time, run.speedTests.last?.end, run.sentences.last?.end, run.events.last?.time]
            .compactMap { $0 }.max() ?? run.info.startedAt
    }

    private func domain(endingAt end: Date) -> ClosedRange<Date> {
        let start = run.info.startedAt
        return start...max(end, start.addingTimeInterval(60))
    }

    private var subtitle: String {
        let start = Format.runStart(run.info.startedAt)
        if recorder != nil { return "\(start) · Recording" }
        guard let end = run.info.endedAt else { return "\(start) · Interrupted" }
        return "\(start) · \(Format.duration(end.timeIntervalSince(run.info.startedAt)))"
    }
}
