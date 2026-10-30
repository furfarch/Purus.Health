import SwiftUI
import SwiftData

struct RecordEditorSectionWeight: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    // Text as typed, so the field is not reformatted ("7" -> "7.0") mid-edit.
    @State private var weightCache: [String: String] = [:]

    init(modelContext: ModelContext, record: MedicalRecord, onChange: @escaping () -> Void) {
        self.modelContext = modelContext
        self._record = Bindable(wrappedValue: record)
        self.onChange = onChange
    }

    private var sortedWeights: [WeightEntry] {
        record.weights.sorted { (lhs: WeightEntry, rhs: WeightEntry) in
            (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    var body: some View {
        Section {
            ForEach(sortedWeights, id: \.uuid) { entry in
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { entry.date ?? Date() },
                        set: { entry.date = $0; onChange() }
                    ),
                    displayedComponents: .date
                )

                HStack {
                    TextField(
                        "Weight (kg)",
                        text: Binding(
                            get: {
                                if let cached = weightCache[entry.uuid] { return cached }
                                guard let v = entry.weightKg else { return "" }
                                return floor(v) == v ? String(format: "%.0f", v) : String(v)
                            },
                            set: {
                                weightCache[entry.uuid] = $0
                                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    entry.weightKg = nil
                                } else if let v = Double(trimmed.replacingOccurrences(of: ",", with: ".").filter { $0 != "'" && $0 != " " }) {
                                    entry.weightKg = v
                                } else {
                                    return // unparsable: keep the previous value
                                }
                                onChange()
                            }
                        )
                    )
                    .keyboardType(.decimalPad)

                    Spacer()

                    Button(role: .destructive) {
                        if let index = record.weights.firstIndex(where: { $0.uuid == entry.uuid }) {
                            let removed = record.weights.remove(at: index)
                            modelContext.delete(removed)
                            weightCache[entry.uuid] = nil
                            onChange()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                TextField(
                    "Comment",
                    text: Binding(
                        get: { entry.comment },
                        set: { entry.comment = $0; onChange() }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }

            Button("Add Weight Entry") {
                let entry = WeightEntry(record: record)
                record.weights.append(entry)
                onChange()
            }
        } header: {
            Label("Weight", systemImage: "scalemass")
        }
    }
}
