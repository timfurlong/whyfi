import SwiftUI

/// The numbers across the top of a run: what the Wi-Fi is doing now while recording, or the
/// run's medians afterwards.
struct NumbersRow: View {
    let run: LoadedRun
    let live: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            signal
            stat(value: linkRate.map { String(format: "%.0f", $0) }, unit: "Mbps", label: live ? "Link rate" : "Median link rate")
            stat(value: download.map(Format.mbps), unit: "Mbps", label: live ? "Last download" : "Median download")
            if let reading = run.readings.last {
                bandStat
                if let bssid = reading.bssid {
                    stat(value: Format.shortBSSID(bssid), unit: nil, label: "Access point")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var rssi: Int? {
        live ? run.readings.last?.rssi : median(run.readings.map(\.rssi))
    }

    private var linkRate: Double? {
        live ? run.readings.last?.txRate : median(run.readings.map(\.txRate))
    }

    private var download: Double? {
        live ? run.speedTests.last?.downloadMbps : median(run.speedTests.map(\.downloadMbps))
    }

    private var signal: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rssi {
                let quality = SignalQuality(dBm: rssi)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(rssi)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("dBm").font(.callout).foregroundStyle(.secondary)
                    Text(quality.label).font(.callout.weight(.semibold))
                }
                .foregroundStyle(quality.color)
            } else {
                Text("No Wi-Fi").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            if mainBand == .ghz2_4 {
                Text(live ? "Signal, on 2.4 GHz" : "Median signal, mostly 2.4 GHz").font(.caption).foregroundStyle(.orange)
            } else {
                Text(live ? "Signal" : "Median signal").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: BandSummary? { LoadedRun.bandSummary(run.readings) }

    /// The band now while recording, or the band the run spent the most time on afterwards.
    private var mainBand: WiFiBand? {
        live ? run.readings.last?.band : summary?.band
    }

    private var bandStat: some View {
        let summary = summary
        let band = mainBand ?? .unknown
        let channel = live ? run.readings.last?.channel : summary?.channel
        let switched = summary?.switchCount ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(band.rawValue).font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(band == .ghz2_4 ? Color.orange : Color.primary)
                if let channel { Text("ch \(channel)").font(.caption).foregroundStyle(.secondary) }
            }
            Text(switched > 0 ? "Band · switched \(switched)×" : "Band").font(.caption).foregroundStyle(.secondary)
        }
        .help(band == .ghz2_4 ? "2.4 GHz reaches farther but is much slower than 5 GHz at the same signal strength." : "")
    }

    private func stat(value: String?, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "–").font(.title3.weight(.semibold)).monospacedDigit()
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func median<T: Comparable>(_ values: [T]) -> T? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }
}
