import SwiftUI
import SwiftData

struct ExportSettingsView: View {
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var exportRecord: MedicalRecord?

    var body: some View {
        List {
            Section {
                Text("Exports are created per record and are not encrypted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Records") {
                if records.isEmpty {
                    Text("No records yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        Button {
                            exportRecord = record
                        } label: {
                            Text(displayName(for: record))
                        }
                    }
                }
            }
        }
        .navigationTitle("Export")
        .sheet(item: $exportRecord, onDismiss: { exportRecord = nil }) { record in
            ExportRecordSheet(record: record)
        }
    }

    private func displayName(for record: MedicalRecord) -> String {
        if record.isPet {
            let name = record.personalName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Pet" : name
        } else {
            let family = record.personalFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let given = record.personalGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let nick = record.personalNickName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nick.isEmpty { return nick }
            if family.isEmpty && given.isEmpty { return "Person" }
            return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

#Preview {
    NavigationStack {
        ExportSettingsView()
    }
    .modelContainer(for: MedicalRecord.self, inMemory: true)
}
