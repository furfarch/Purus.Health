import SwiftUI

struct RecordViewerSectionPetYearlyCosts: View {
    let record: MedicalRecord

    private var sorted: [PetYearlyCostEntry] {
        record.petYearlyCosts.sorted { a, b in
            if a.year != b.year { return a.year > b.year }
            return a.category.localizedCaseInsensitiveCompare(b.category) == .orderedAscending
        }
    }

    var body: some View {
        let rows: [[String]] = sorted.map { entry in
            [
                String(entry.year),
                entry.category,
                String(format: "%.2f", entry.amount),
                entry.note
            ]
        }

        return RecordViewerSectionEntries(
            title: "Yearly Costs",
            columns: ["Year", "Category", "Amount", "Note"],
            rows: rows
        )
    }
}
