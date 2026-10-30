import SwiftUI

struct RecordViewerSectionEntries: View {
    let title: String
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("No entries")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        ForEach(columns, id: \.self) { col in
                            Text(col)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    // Rows
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value.isEmpty ? "—" : value)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)

                        Divider()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
