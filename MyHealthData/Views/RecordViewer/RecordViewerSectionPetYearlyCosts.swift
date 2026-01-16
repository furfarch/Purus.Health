import SwiftUI

struct RecordViewerSectionPetYearlyCosts: View {
    let record: MedicalRecord

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var entriesForCurrentYear: [PetYearlyCostEntry] {
        record.petYearlyCosts
            .filter { $0.year == currentYear }
            .sorted { $0.date > $1.date }
    }

    private var currentYearTotal: Double {
        entriesForCurrentYear.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Total \(currentYear)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentYearTotal, format: .currency(code: Locale.current.currency?.identifier ?? "CHF"))
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)

            Divider()

            if entriesForCurrentYear.isEmpty {
                RecordViewerRow(title: "Costs", value: "No entries for \(currentYear)")
            } else {
                RecordViewerSectionEntries(
                    title: "Costs",
                    columns: ["Date", "Title", "Amount", "Note"],
                    rows: entriesForCurrentYear.map { entry in
                        [
                            entry.date.formatted(date: .abbreviated, time: .omitted),
                            entry.title,
                            String(format: "%.2f", entry.amount),
                            entry.note
                        ]
                    }
                )
            }
        }
    }
}
