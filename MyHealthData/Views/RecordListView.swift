import SwiftUI
import SwiftData

struct RecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var activeRecord: MedicalRecord? = nil
    @State private var showEditor: Bool = false
    @State private var startEditing: Bool = false
    @State private var showAbout: Bool = false
    @State private var showSettings: Bool = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                listContent
            }
            .navigationTitle("MyHealthData")
            .toolbar {
                #if os(iOS) || targetEnvironment(macCatalyst)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                // Enables the standard iOS delete UI (and also works for iPad-on-Mac where swipe can be awkward).
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            addRecord(isPet: false)
                        } label: {
                            Label("Human", systemImage: "person")
                        }

                        Button {
                            addRecord(isPet: true)
                        } label: {
                            Label("Pet", systemImage: "cat")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #else
                // macOS build (if you ever add a real macOS target later).
                ToolbarItem(placement: .automatic) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem {
                    Menu {
                        Button {
                            addRecord(isPet: false)
                        } label: {
                            Label("Human", systemImage: "person")
                        }

                        Button {
                            addRecord(isPet: true)
                        } label: {
                            Label("Pet", systemImage: "cat")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #endif
            }
            .sheet(item: $activeRecord, onDismiss: { activeRecord = nil }) { record in
                NavigationStack {
                    RecordEditorView(record: record, startEditing: startEditing)
                }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Save Error", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Unknown error")
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if records.isEmpty {
            VStack(alignment: .center) {
                Text("No records yet")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(records, id: \.persistentModelID) { record in
                row(for: record)
            }
            .onDelete(perform: deleteRecords)
        }
    }

    private func row(for record: MedicalRecord) -> some View {
        HStack {
            Image(systemName: record.isPet ? "cat" : "person")

            VStack(alignment: .leading) {
                Text(displayName(for: record)).font(.headline)
                Text(record.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: record.locationStatus.systemImageName)
                .foregroundStyle(record.locationStatus.color)
                .accessibilityLabel(record.locationStatus.accessibilityLabel)
                .accessibilityIdentifier("recordLocationStatusIcon")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeRecord = record
            startEditing = false
            showEditor = true
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteRecords(with: [record])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func addRecord(isPet: Bool) {
        let record = MedicalRecord()
        record.isPet = isPet
        record.updatedAt = Date()
        if isPet {
            record.personalName = ""
        } else {
            record.personalNickName = ""
        }

        modelContext.insert(record)
        // Persist immediately so the query observes the change.
        Task { @MainActor in
            do { try modelContext.save() }
            catch { saveErrorMessage = "Save failed: \(error.localizedDescription)" }
        }

        activeRecord = record
        startEditing = true
        showEditor = true
    }

    private func deleteRecords(at offsets: IndexSet) {
        Task { @MainActor in
            for index in offsets.sorted(by: >) {
                let record = records[index]
                await deleteRecord(record)
            }
            do { try modelContext.save() }
            catch { saveErrorMessage = "Delete failed: \(error.localizedDescription)" }
        }
    }

    private func deleteRecords(with recordsToDelete: [MedicalRecord]) {
        Task { @MainActor in
            for record in recordsToDelete {
                await deleteRecord(record)
            }
            do { try modelContext.save() }
            catch { saveErrorMessage = "Delete failed: \(error.localizedDescription)" }
        }
    }

    @MainActor
    private func deleteRecord(_ record: MedicalRecord) async {
        if record.isCloudEnabled {
            do {
                try await CloudSyncService.shared.deleteCloudRecord(for: record)
            } catch {
                saveErrorMessage = "Cloud delete failed: \(error.localizedDescription)"
            }
        }
        modelContext.delete(record)
    }

    private func displayName(for record: MedicalRecord) -> String {
        if record.isPet {
            let name = record.personalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
            return "Pet"
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
    RecordListView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
