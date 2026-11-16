import SwiftUI

struct SettingsView: View {
    @AppStorage(AppModel.speedTestModeKey) private var mode: SpeedTestMode = .backToBack

    var body: some View {
        Form {
            Picker("Speed tests", selection: $mode) {
                ForEach(SpeedTestMode.allCases) { Text($0.title).tag($0) }
            }
            Text("Back to back gives the most detail but downloads about 1.5 GB a minute. If your internet plan has a data cap, test every 30 seconds or turn speed tests off. Signal is recorded either way.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}

/// The speed test setting as a toolbar menu.
struct SpeedTestMenu: View {
    @AppStorage(AppModel.speedTestModeKey) private var mode: SpeedTestMode = .backToBack

    var body: some View {
        Picker("Speed tests", selection: $mode) {
            ForEach(SpeedTestMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .help("How often to test download speed")
    }
}
