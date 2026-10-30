import SwiftUI

struct RecordViewerRow: View {
    let title: String
    let value: String

    var body: some View {
        // FinAI style: label left, value right
        LabeledContent(title) {
            Text(value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .padding(.vertical, 6)
    }
}

struct RecordViewerDateRow: View {
    let title: String
    let value: Date?

    var body: some View {
        RecordViewerRow(
            title: title,
            value: value.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
        )
    }
}
