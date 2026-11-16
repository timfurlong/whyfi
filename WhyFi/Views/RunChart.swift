import Charts
import SwiftUI

/// Signal over time on good/OK/poor bands, with narration pins, and download speed underneath.
struct RunChart: View {
    let run: LoadedRun
    let domain: ClosedRange<Date>
    @Binding var selectedTime: Date?

    private static let signalFloor = -95
    private static let signalCeiling = -20
    private static let axisWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            readout
            signalChart.frame(minHeight: 220)
            speedChart.frame(height: 90)
        }
    }

    // MARK: - Signal

    private var signalChart: some View {
        let segments = LoadedRun.segments(run.readings)
        let markers = run.events.filter { ($0.text ?? "").hasPrefix("access_point_changed") || ($0.text ?? "").hasPrefix("band_changed") }
        return Chart {
            bands
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment, id: \.time) { r in
                    LineMark(x: .value("Time", r.time), y: .value("Signal", min(max(r.rssi, Self.signalFloor), Self.signalCeiling)),
                             series: .value("Segment", index))
                        .foregroundStyle(Palette.signal)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(markers, id: \.time) { event in
                RuleMark(x: .value("Time", event.time))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(Array(run.sentences.enumerated()), id: \.element.id) { index, sentence in
                RuleMark(x: .value("Said", sentence.start))
                    .foregroundStyle(Palette.narration.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 0) { Pin(number: index + 1) }
            }
            if let selectedTime {
                RuleMark(x: .value("Selected", selectedTime))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: Self.signalFloor...Self.signalCeiling)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-20, -40, -55, -65, -75, -90]) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)").frame(width: Self.axisWidth, alignment: .trailing)
                }
            }
        }
        .chartXSelection(value: $selectedTime)
        .overlay(alignment: .topTrailing) { chartTitle("Signal (dBm)") }
        .padding(.top, 24)
    }

    @ChartContentBuilder
    private var bands: some ChartContent {
        RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound),
                      yStart: .value("Low", SignalBand.goodFloor), yEnd: .value("High", Self.signalCeiling))
            .foregroundStyle(SignalBand.good.color.opacity(0.10))
        RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound),
                      yStart: .value("Low", SignalBand.okFloor), yEnd: .value("High", SignalBand.goodFloor))
            .foregroundStyle(SignalBand.ok.color.opacity(0.12))
        RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound),
                      yStart: .value("Low", Self.signalFloor), yEnd: .value("High", SignalBand.okFloor))
            .foregroundStyle(SignalBand.poor.color.opacity(0.10))
    }

    // MARK: - Speed

    private var speedChart: some View {
        let top = max(100, (run.speedTests.map(\.downloadMbps).max() ?? 0) * 1.15)
        return Chart {
            ForEach(run.speedTests, id: \.start) { test in
                BarMark(xStart: .value("Start", test.start), xEnd: .value("End", test.end),
                        y: .value("Download", test.downloadMbps))
                    .foregroundStyle(Palette.speed.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            if let selectedTime {
                RuleMark(x: .value("Selected", selectedTime)).foregroundStyle(Color.primary.opacity(0.5))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)").frame(width: Self.axisWidth, alignment: .trailing)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: Self.axisStepMinutes(for: domain.upperBound.timeIntervalSince(domain.lowerBound)))) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartXSelection(value: $selectedTime)
        .overlay(alignment: .topTrailing) { chartTitle("Download (Mbps)") }
    }

    /// Minutes between time labels: about six labels, never two for the same minute.
    nonisolated static func axisStepMinutes(for seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60 / 6).rounded(.up)))
    }

    private func chartTitle(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
            .padding(4)
    }

    // MARK: - Readout

    /// What was happening at the hovered or selected moment.
    private var readout: some View {
        HStack(spacing: 10) {
            if let time = selectedTime {
                Text(Format.clock(time)).fontWeight(.semibold).monospacedDigit()
                if let r = nearestReading(to: time) {
                    Text("\(r.rssi) dBm").foregroundStyle(SignalQuality(dBm: r.rssi).color).monospacedDigit()
                    Text("\(Int(r.txRate)) Mbps link").monospacedDigit()
                } else {
                    Text("No Wi-Fi").foregroundStyle(.secondary)
                }
                if let test = nearestTest(to: time) {
                    Text("\(Format.mbps(test.downloadMbps)) Mbps download").foregroundStyle(Palette.speed).monospacedDigit()
                }
            } else {
                Text("Hover over the chart, or click a sentence.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .frame(height: 20)
        .padding(.leading, Self.axisWidth + 8)
    }

    private func nearestReading(to time: Date) -> SignalReading? {
        guard let r = run.readings.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }),
              abs(r.time.timeIntervalSince(time)) <= 3 else { return nil }
        return r
    }

    private func nearestTest(to time: Date) -> SpeedTestResult? {
        run.speedTests.first { $0.start <= time && time <= $0.end }
            ?? run.speedTests.min { abs($0.end.timeIntervalSince(time)) < abs($1.end.timeIntervalSince(time)) }
                .flatMap { abs($0.end.timeIntervalSince(time)) <= 20 ? $0 : nil }
    }
}

/// The numbered orange circle that marks a sentence.
struct Pin: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Palette.narration, in: Circle())
    }
}
