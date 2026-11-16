import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            RunListView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            detail
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.showingNewRun) {
            NewRunSheet(onRecord: { name in Task { await model.startRun(named: name) } },
                        onCancel: { model.showingNewRun = false })
        }
        .alert("Couldn't start the run", isPresented: Binding(get: { model.startError != nil }, set: { if !$0 { model.startError = nil } })) {
            Button("OK") { model.startError = nil }
        } message: {
            Text(model.startError ?? "")
        }
        .onChange(of: model.recorder.folder) { _, folder in
            if let folder { model.selection = folder }
        }
        .frame(minWidth: 1080, minHeight: 600)
    }

    @ViewBuilder
    private var detail: some View {
        if model.store.runs.isEmpty {
            ContentUnavailableView {
                VStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("No runs yet")
                }
            } description: {
                Text("Start a run, then carry your Mac around and say where you are. WhyFi lines up what you said with the Wi-Fi signal and speed, so you can see what made it drop.")
            } actions: {
                Button("New Run") { model.newRun() }.buttonStyle(.borderedProminent)
            }
        } else if let folder = model.selection, let run = model.loadedRun(for: folder) {
            let live = model.recorder.isRecording && folder == model.recorder.folder
            RunDetailView(run: run, recorder: live ? model.recorder : nil)
                .id(folder)
        } else {
            ContentUnavailableView("Select a run", systemImage: "sidebar.left")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.recorder.isRecording {
                RecordingStatus(recorder: model.recorder)
                Button {
                    Task { await model.stopRun() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
                .help("Stop recording (⌘.)")
            } else {
                Button {
                    model.newRun()
                } label: {
                    Label("New Run", systemImage: "record.circle")
                }
                .help("Start recording a run (⌘N)")
            }
        }
        ToolbarItem(placement: .automatic) {
            SpeedTestMenu()
        }
    }
}

/// Elapsed time and the microphone meter. A view of its own so the many mic-level updates
/// redraw only this, not the whole window.
struct RecordingStatus: View {
    let recorder: RunRecorder

    var body: some View {
        HStack(spacing: 10) {
            if let started = recorder.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.duration(context.date.timeIntervalSince(started)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            MicLevel(level: recorder.micLevel, active: recorder.speechStatus == .listening)
        }
    }
}

/// Five bars that light up with the microphone level.
struct MicLevel: View {
    let level: Float
    let active: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(active && level > Float(i) / 5 ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: CGFloat(5 + i * 3))
            }
        }
        .frame(height: 18)
        .help(active ? "Microphone level" : "Not listening")
        .accessibilityLabel("Microphone level")
    }
}
