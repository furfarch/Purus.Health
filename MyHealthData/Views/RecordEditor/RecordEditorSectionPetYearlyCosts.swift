import SwiftUI
import SwiftData

struct RecordEditorSectionPetYearlyCosts: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var entries: [PetYearlyCostEntry] {
        Array(record.petYearlyCosts)
    }

    var body: some View {
        Section {
            if record.petYearlyCosts.isEmpty {
                Text("Track recurring yearly pet costs (e.g., insurance, food, vet).")
                    .foregroundStyle(.secondary)
            }

            ForEach(entries, id: \.uuid, content: { (entry: PetYearlyCostEntry) in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.category)
                            .font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            if let index = record.petYearlyCosts.firstIndex(where: { $0.uuid == entry.uuid }) {
                                let removed = record.petYearlyCosts.remove(at: index)
                                modelContext.delete(removed)
                                onChange()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    Text("Year: \(entry.year)")
                        .foregroundStyle(.secondary)

                    Text("Amount: \(entry.amount, format: .number)")
                        .foregroundStyle(.secondary)

                    if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(entry.note)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            })

            Button("Add Yearly Cost") {
                let entry = PetYearlyCostEntry(record: record)
                record.petYearlyCosts.append(entry)
                onChange()
            }
        } header: {
            Label("Yearly Costs", systemImage: "eurosign.circle")
        }
    }
}
