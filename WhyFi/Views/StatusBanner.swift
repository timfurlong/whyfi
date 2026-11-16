import AppKit
import SwiftUI

/// Problems and progress while recording, shown above the numbers.
struct StatusBanners: View {
    let recorder: RunRecorder

    var body: some View {
        VStack(spacing: 6) {
            switch recorder.speechStatus {
            case .preparing(let progress):
                banner(icon: "mic", tint: .blue,
                       text: "Getting the microphone and Apple's speech model ready. Wi-Fi is already being recorded.") {
                    if progress > 0 { ProgressView(value: progress).frame(width: 120) }
                }
            case .unavailable(let reason):
                banner(icon: "mic.slash", tint: .orange,
                       text: "Not transcribing: \(reason). Wi-Fi is still being recorded.") {
                    if reason == SpeechSourceError.microphoneDenied.reason {
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }
                }
            case .off, .listening:
                EmptyView()
            }
            if !recorder.wifiConnected {
                banner(icon: "wifi.slash", tint: .red, text: "Wi-Fi is off or disconnected. WhyFi keeps recording and marks the gap.") { EmptyView() }
            }
            if let error = recorder.lastSpeedError {
                banner(icon: "speedometer", tint: .orange, text: "Last speed test failed: \(error). Trying again shortly.") { EmptyView() }
            }
            if let error = recorder.lastWriteError {
                banner(icon: "exclamationmark.triangle", tint: .red, text: "Couldn't save to the run's folder: \(error)") { EmptyView() }
            }
        }
        .padding(.horizontal, 16)
    }

    private func banner<Accessory: View>(icon: String, tint: Color, text: String,
                                         @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.25)))
    }
}
