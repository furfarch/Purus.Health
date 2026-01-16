import SwiftUI
import SwiftData

struct RecordEditorSectionPetYearlyCosts: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var sortedIndices: [Int] {
        record.petYearlyCosts.indices.sorted { a, b in
            let lhs = record.petYearlyCosts[a]
            let rhs = record.petYearlyCosts[b]
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            return lhs.date > rhs.date
        }
    }

    private var currentYearTotal: Double {
        record.petYearlyCosts
            .filter { $0.year == currentYear }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Section {
            if record.petYearlyCosts.isEmpty {
                Text("Add cost entries by date (e.g., Vet Check Up, 01.01.2026, 100). The app sums these for the year.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Total \(currentYear)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(currentYearTotal, format: .currency(code: Locale.current.currency?.identifier ?? "CHF"))
                        .fontWeight(.semibold)
                }
            }

            ForEach(sortedIndices, id: \.self) { idx in
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { record.petYearlyCosts[idx].date },
                        set: { record.petYearlyCosts[idx].date = $0; onChange() }
                    ),
                    displayedComponents: .date
                )

                HStack {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { record.petYearlyCosts[idx].title },
                            set: { record.petYearlyCosts[idx].title = $0; onChange() }
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

                if idx != sortedIndices.last {
                    Divider()
                }
            }

            Button("Add Cost Entry") {
                let entry = PetYearlyCostEntry(record: record)
                record.petYearlyCosts.append(entry)
                onChange()
            }
        } header: {
            Label("Costs", systemImage: "eurosign.circle")
        }
    }
}
