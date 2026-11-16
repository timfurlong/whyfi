import SwiftUI

/// The numbered sentences beside the chart, with the words still being heard at the bottom.
struct TranscriptView: View {
    let sentences: [Sentence]
    /// The sentence nearest the hovered or selected moment, highlighted.
    let highlighted: Sentence.ID?
    let volatileText: String?
    @Binding var selectedTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What you said")
                .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sentences.enumerated()), id: \.element.id) { index, sentence in
                            row(index: index, sentence: sentence).id(sentence.id)
                        }
                        if let volatileText, !volatileText.isEmpty {
                            Text(volatileText)
                                .italic().foregroundStyle(.tertiary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .id("volatile")
                        }
                        if sentences.isEmpty && (volatileText ?? "").isEmpty {
                            Text(volatileText == nil ? "Nothing was said in this run." : "Say where you are and what you're doing. Each sentence shows up here and as a pin on the chart.")
                                .foregroundStyle(.secondary).font(.callout)
                                .padding(12)
                        }
                    }
                }
                .onChange(of: highlighted) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id) }
                }
                .onChange(of: sentences.count) {
                    guard volatileText != nil, let last = sentences.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func row(index: Int, sentence: Sentence) -> some View {
        let selected = sentence.id == highlighted
        return Button {
            selectedTime = sentence.start
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Pin(number: index + 1).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence.text).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.clock(sentence.start)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
    }
}
