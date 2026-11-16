import AppKit
import SwiftUI

@main
struct WhyFiApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("WhyFi", id: "main") {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Run") { model.newRun() }
                    .keyboardShortcut("n")
                    .disabled(model.recorder.isRecording)
                Button("Stop Recording") { Task { await model.stopRun() } }
                    .keyboardShortcut(".")
                    .disabled(!model.recorder.isRecording)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension AppModel {
    /// One model for the window and the app delegate.
    static let shared = AppModel()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quitting mid-run stops the run cleanly first, so it isn't left interrupted.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let model = AppModel.shared
            guard model.recorder.isRecording else { return .terminateNow }
            Task { @MainActor in
                await model.stopRun()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
