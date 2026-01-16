import SwiftUI
import SwiftData

struct RecordEditorSectionPetYearlyCosts: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var sortedIndices: [Int] {
        record.petYearlyCosts.indices.sorted { a, b in
            let lhs = record.petYearlyCosts[a]
            let rhs = record.petYearlyCosts[b]
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            if record.petYearlyCosts.isEmpty {
                Text("Track recurring yearly pet costs (e.g., insurance, food, vet).")
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedIndices, id: \.self) { idx in
                let binding = Binding<PetYearlyCostEntry>(
                    get: { record.petYearlyCosts[idx] },
                    set: { record.petYearlyCosts[idx] = $0 }
                )

                HStack {
                    TextField(
                        "Category",
                        text: Binding(
                            get: { binding.wrappedValue.category },
                            set: { record.petYearlyCosts[idx].category = $0; onChange() }
                        )
                    )

                    Spacer()

                    Button(role: .destructive) {
                        let removed = record.petYearlyCosts.remove(at: idx)
                        modelContext.delete(removed)
                        onChange()
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                Stepper(
                    value: Binding(
                        get: { record.petYearlyCosts[idx].year },
                        set: { record.petYearlyCosts[idx].year = $0; onChange() }
                    ),
                    in: 1990...2100
                ) {
                    Text("Year: \(record.petYearlyCosts[idx].year)")
                }

                HStack {
                    Text("Amount")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField(
                        "0.00",
                        value: Binding(
                            get: { record.petYearlyCosts[idx].amount },
                            set: { record.petYearlyCosts[idx].amount = $0; onChange() }
                        ),
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }

                TextField(
                    "Note",
                    text: Binding(
                        get: { record.petYearlyCosts[idx].note },
                        set: { record.petYearlyCosts[idx].note = $0; onChange() }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }

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
