import SwiftUI

struct RecordViewerSectionPetYearlyCosts: View {
    let record: MedicalRecord

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var yearPickerYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        let years = Set(record.petYearlyCosts.map { $0.year } + [current])
        return Array(years).sorted(by: >)
    }

    private var entriesForSelectedYear: [PetYearlyCostEntry] {
        let filtered = record.petYearlyCosts.filter { $0.year == selectedYear }
        return filtered.sorted { (lhs: PetYearlyCostEntry, rhs: PetYearlyCostEntry) in
            lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }

    private var selectedYearTotal: Double {
        entriesForSelectedYear.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Year")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Year", selection: $selectedYear) {
                    ForEach(yearPickerYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedYearTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            if entriesForSelectedYear.isEmpty {
                Text("No costs for \(selectedYear).")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            } else {
                RecordViewerSectionEntries(
                    title: "Yearly Costs",
                    columns: ["Category", "Amount", "Note"],
                    rows: entriesForSelectedYear.map { entry in
                        [
                            entry.category,
                            String(format: "%.2f", entry.amount),
                            entry.note
                        ]
                    }
                )
            }
        }
        .onAppear {
            selectedYear = Calendar.current.component(.year, from: Date())
        }
    }
}
