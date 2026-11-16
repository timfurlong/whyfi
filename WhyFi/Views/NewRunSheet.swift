import SwiftUI

/// Names a run before recording starts.
struct NewRunSheet: View {
    let onRecord: (String) -> Void
    let onCancel: () -> Void
    @State private var name = "Run " + Date().formatted(.dateTime.month(.abbreviated).day().hour().minute())

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New run").font(.title2.weight(.semibold))
            Text("Name it after what you're testing, like \"Router on shelf\". Then walk around and say where you are and what you're doing.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(record)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(action: record) {
                    Label("Record", systemImage: "record.circle")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func record() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onRecord(trimmed)
    }
}
