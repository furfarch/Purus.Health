 import SwiftUI
import SwiftData

struct RecordEditorSectionWeight: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    init(modelContext: ModelContext, record: MedicalRecord, onChange: @escaping () -> Void) {
        self.modelContext = modelContext
        self._record = Bindable(wrappedValue: record)
        self.onChange = onChange
    }

    var body: some View {
        Section {
            ForEach(record.weights.indices, id: \ .self) { idx in
                let binding = Binding(
                    get: { record.weights[idx] },
                    set: { record.weights[idx] = $0 }
                )

                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { binding.date ?? Date() },
                        set: { binding.date = $0 }
                    ),
                    displayedComponents: .date
                )

                HStack {
                    TextField("Weight (kg)", value: binding.weightKg, format: .number)
                    Spacer()
                    Button(role: .destructive) {
                        record.weights.remove(at: idx)
                        onChange()
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                TextField("Comment", text: binding.comment, axis: .vertical)
                    .lineLimit(1...3)
            }

            Button("Add Weight Entry") {
                let entry = WeightEntry()
                entry.record = record
                record.weights.append(entry)
                onChange()
            }
        } header: {
            Label("Weight", systemImage: "scalemass")
        }
    }
}
