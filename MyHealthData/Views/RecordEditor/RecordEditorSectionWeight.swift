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
            ForEach(Array(record.weights.indices), id: \.self) { idx in
                // Bindings for the specific weight entry fields
                let dateBinding = Binding(
                    get: { record.weights[idx].date ?? Date() },
                    set: { record.weights[idx].date = $0 }
                )

                let weightKgBinding = Binding(
                    get: { record.weights[idx].weightKg },
                    set: { record.weights[idx].weightKg = $0 }
                )

                let commentBinding = Binding(
                    get: { record.weights[idx].comment },
                    set: { record.weights[idx].comment = $0 }
                )

                DatePicker("Date", selection: dateBinding, displayedComponents: .date)

                HStack {
                    TextField("Weight (kg)", value: weightKgBinding, format: .number)
                    Spacer()
                    Button(role: .destructive) {
                        record.weights.remove(at: idx)
                        onChange()
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                TextField("Comment", text: commentBinding, axis: .vertical)
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
