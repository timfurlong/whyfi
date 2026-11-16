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
                stat(value: reading.band.rawValue, unit: "ch \(reading.channel)", label: "Band")
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
            Text(live ? "Signal" : "Median signal").font(.caption).foregroundStyle(.secondary)
        }
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
