import AppKit
import SwiftUI

/// The sidebar: every run, newest first.
struct RunListView: View {
    @Bindable var model: AppModel
    @State private var renaming: RunSummary?
    @State private var newName = ""
    @State private var deleting: RunSummary?

    var body: some View {
        List(selection: $model.selection) {
            Section("Runs") {
                ForEach(model.store.runs) { run in
                    row(run).tag(run.folder)
                        .contextMenu {
                            Button("Rename…") { newName = run.info.name; renaming = run }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([run.folder]) }
                            Divider()
                            Button("Delete…", role: .destructive) { deleting = run }
                                .disabled(run.folder == model.recorder.folder && model.recorder.isRecording)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("Rename run", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let run = renaming { try? model.store.rename(run, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Move this run to the Trash?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let run = deleting {
                    try? model.store.delete(run)
                    if model.selection == run.folder { model.selection = model.store.runs.first?.folder }
                }
                deleting = nil
            }
        } message: {
            Text("Its readings, transcript and audio go to the Trash, where you can still get them back.")
        }
    }

    private func row(_ run: RunSummary) -> some View {
        let recording = model.recorder.isRecording && run.folder == model.recorder.folder
        return VStack(alignment: .leading, spacing: 2) {
            Text(run.info.name).fontWeight(.semibold).lineLimit(1)
            HStack(spacing: 4) {
                Text(Format.runStart(run.info.startedAt))
                if recording {
                    Text("·")
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                    Text("Recording")
                } else if model.store.isInterrupted(run) {
                    Text("· Interrupted")
                } else if let end = run.info.endedAt {
                    Text("· \(Format.duration(end.timeIntervalSince(run.info.startedAt)))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
