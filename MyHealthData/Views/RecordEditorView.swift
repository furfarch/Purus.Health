import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecordEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: MedicalRecord

    @State private var isEditing: Bool
    @State private var saveErrorMessage: String?

    init(record: MedicalRecord, startEditing: Bool = false) {
        self._record = .init(wrappedValue: record)
        self._isEditing = State(initialValue: startEditing)
    }

    var body: some View {
        Form {
            if isEditing {
                editorForm
            } else {
                viewerForm
            }
        }
        .navigationTitle(record.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveAndFinishEditing()
                    } else {
                        isEditing = true
                    }
                }
            }
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Viewer (ordered as requested)

    @ViewBuilder
    private var viewerForm: some View {
        // A) Personal
        Section { RecordViewerSectionPersonal(record: record) }

        // B) Emergency
        Section { RecordViewerSectionEmergency(record: record) }

        // C) Vet / Doctor
        if record.isPet {
            Section { RecordViewerSectionPetVet(record: record) }
        } else {
            Section { RecordViewerSectionDoctors(record: record) }
        }

        // D) Weight for Pets only
        if record.isPet {
            Section {
                RecordViewerSectionEntries(
                    title: "Weight",
                    columns: ["Date", "kg", "Comment"],
                    rows: record.weights
                        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                        .map { entry in
                            [
                                entry.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                                String(format: "%.1f", entry.weightKg ?? 0),
                                entry.comment
                            ]
                        }
                )
            }
        }

        // E) Blood
        Section {
            RecordViewerSectionEntries(
                title: "Blood",
                columns: ["Date", "Name", "Comment"],
                rows: record.blood
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.name,
                        $0.comment
                    ] }
            )
        }

        // F) Medications
        Section {
            RecordViewerSectionEntries(
                title: "Medications",
                columns: ["Date", "Name & Dosage", "Comment"],
                rows: record.drugs
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.nameAndDosage,
                        $0.comment
                    ] }
            )
        }

        // G) Vaccinations
        Section {
            RecordViewerSectionEntries(
                title: "Vaccinations",
                columns: ["Date", "Name", "Place", "Comment"],
                rows: record.vaccinations
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.name,
                        $0.place,
                        $0.comment
                    ] }
            )
        }

        // H) Allergies
        Section {
            RecordViewerSectionEntries(
                title: "Allergies",
                columns: ["Date", "Name", "Comment"],
                rows: record.allergy
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.name,
                        $0.comment
                    ] }
            )
        }

        // I) Illnesses
        Section {
            RecordViewerSectionEntries(
                title: "Illnesses",
                columns: ["Name", "Date", "Comment"],
                rows: record.illness
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.name,
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.informationOrComment
                    ] }
            )
        }

        // J) Documents
        Section {
            RecordViewerSectionEntries(
                title: "Documents",
                columns: ["Name", "Date", "Note"],
                rows: record.medicaldocument
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.name,
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.note
                    ] }
            )
        }

        // K) History
        Section {
            RecordViewerSectionEntries(
                title: "History",
                columns: ["Name", "Date", "Contact", "Comment"],
                rows: record.medicalhistory
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.name,
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.contact,
                        $0.informationOrComment
                    ] }
            )
        }

        // L) Risks
        Section {
            RecordViewerSectionEntries(
                title: "Risks",
                columns: ["Date", "Name", "Comment"],
                rows: record.risks
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { [
                        $0.date.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—",
                        $0.name,
                        $0.descriptionOrComment
                    ] }
            )
        }

        // M) Costs for pet only
        if record.isPet {
            Section { RecordViewerSectionPetYearlyCosts(record: record) }
        }

        // N) Record details
        Section { RecordViewerSectionDetails(record: record) }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorForm: some View {
        RecordEditorSectionPersonal(record: record) { touchAndSave() }
        RecordEditorSectionEmergency(modelContext: modelContext, record: record) { touchAndSave() }

        if record.isPet {
            RecordEditorSectionPetVet(record: record) { touchAndSave() }
            RecordEditorSectionWeight(modelContext: modelContext, record: record) { touchAndSave() }
        } else {
            RecordEditorSectionDoctors(modelContext: modelContext, record: record) { touchAndSave() }
        }

        RecordEditorSectionBlood(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionDrugs(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionVaccinations(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionAllergies(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionIllnesses(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionMedicalDocuments(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionMedicalHistory(modelContext: modelContext, record: record) { touchAndSave() }
        RecordEditorSectionRisks(modelContext: modelContext, record: record) { touchAndSave() }

        if record.isPet {
            RecordEditorSectionPetYearlyCosts(modelContext: modelContext, record: record) { touchAndSave() }
        }
    }

    // MARK: - Persistence

    @MainActor
    private func touchAndSave() {
        record.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveAndFinishEditing() {
        touchAndSave()
        isEditing = false
    }
}

#Preview {
    NavigationStack {
        RecordEditorView(record: MedicalRecord(), startEditing: true)
    }
    .modelContainer(for: MedicalRecord.self, inMemory: true)
}
