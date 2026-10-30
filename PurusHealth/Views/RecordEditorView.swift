import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecordEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: MedicalRecord

    @State private var isEditing: Bool
    @State private var saveErrorMessage: String?
    @State private var showCloudSettings: Bool = false

    // MARK: - Permissions
    @State private var effectivePermission: CloudKitSharePermissionService.EffectivePermission = .unknown

    private var isSharedReadOnly: Bool {
        effectivePermission == .readOnly
    }

    private var isWaitingForShareAttachment: Bool {
        // Treat unknown permission with a share as waiting state
        if let shareName = record.cloudShareRecordName, !shareName.isEmpty, effectivePermission == .unknown { return true }
        return false
    }

    init(record: MedicalRecord, startEditing: Bool = false) {
        self._record = .init(wrappedValue: record)
        self._isEditing = State(initialValue: startEditing)
    }

    var body: some View {
        Form {
            if isEditing {
                editorForm.disabled(isSharedReadOnly)
            } else {
                viewerFormList
            }
        }
        .navigationTitle(record.displayName)
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await refreshSharePermission() }
        .onReceive(NotificationCenter.default.publisher(for: NotificationNames.didImportRecords)) { _ in
            Task { await refreshSharePermission() }
        }
        .onChange(of: record.cloudShareRecordName) { _, _ in Task { await refreshSharePermission() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isSharedReadOnly {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            saveAndFinishEditing()
                        } else {
                            isEditing = true
                        }
                    }
                    .help(isWaitingForShareAttachment ? "Waiting for share acceptance" : "")
                }
            }

            #if os(iOS) || targetEnvironment(macCatalyst)
            ToolbarItem(placement: .navigationBarLeading) {
                if isEditing {
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Cloud & Sharing") {
                            showCloudSettings = true
                        }
                        .disabled(isSharedReadOnly)
                        .help(isWaitingForShareAttachment ? "Waiting for share acceptance" : "")

                        if effectivePermission == .readWrite {
                            Button("Manage Sharing") {
                                showCloudSettings = true
                            }
                        }
                    }
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                if isEditing {
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Cloud & Sharing") {
                            showCloudSettings = true
                        }
                        .disabled(isSharedReadOnly)
                        .help(isWaitingForShareAttachment ? "Waiting for share acceptance" : "")

                        if effectivePermission == .readWrite {
                            Button("Manage Sharing") {
                                showCloudSettings = true
                            }
                        }
                    }
                }
            }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                if isSharedReadOnly {
                    Text("READ ONLY")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                        .accessibilityLabel("Read-only shared record")
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
        .sheet(isPresented: $showCloudSettings) {
            NavigationStack { CloudRecordSettingsView() }
        }
    }

    // MARK: - Viewer (FinAI style: one collapsible line per part with a short summary)

    private func dateText(_ d: Date?) -> String { d.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—" }

    /// "3 entries · latest 12.03.2026" or "No entries"
    private func entriesSummary(_ dates: [Date?]) -> String {
        if dates.isEmpty { return "No entries" }
        let n = "\(dates.count) entr\(dates.count == 1 ? "y" : "ies")"
        if let last = dates.compactMap({ $0 }).max() { return "\(n) · latest \(last.formatted(date: .numeric, time: .omitted))" }
        return n
    }

    private func entriesFold(_ title: String, columns: [String], dates: [Date?], rows: [[String]]) -> some View {
        Fold(title: title, summary: entriesSummary(dates)) {
            RecordViewerSectionEntries(title: title, columns: columns, rows: rows)
        }
    }

    private func joined(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var personalSummary: String {
        let born = record.personalBirthdate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        if record.isPet { return joined([record.petBreed, born, record.ownerName]) }
        return joined([born, record.personalHealthInsurance])
    }

    private var emergencySummary: String {
        let contacts = record.emergencyContacts
        if let first = contacts.first {
            return joined([first.name, first.phone]) + (contacts.count > 1 ? " · +\(contacts.count - 1) more" : "")
        }
        let s = joined([record.emergencyName, record.emergencyNumber])
        return s.isEmpty ? "None added" : s
    }

    private var doctorsSummary: String {
        let d = record.humanDoctors
        if d.isEmpty { return "No doctors added" }
        return "\(d.count) doctor\(d.count == 1 ? "" : "s") · " + d.prefix(2).map { $0.name }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var costsSummary: String {
        let year = Calendar.current.component(.year, from: Date())
        let total = record.petYearlyCosts.filter { $0.year == year }.reduce(0) { $0 + $1.amount }
        return "\(year): " + total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    @ViewBuilder
    private var viewerFormList: some View {
        Section {
            Fold(title: "Personal", summary: personalSummary, open: true) { RecordViewerSectionPersonal(record: record) }
            Fold(title: "Emergency", summary: emergencySummary, open: true) { RecordViewerSectionEmergency(record: record) }
            if record.isPet {
                Fold(title: "Veterinarian", summary: record.vetClinicName.isEmpty ? "None added" : record.vetClinicName) { RecordViewerSectionPetVet(record: record) }
            } else {
                Fold(title: "Doctors", summary: doctorsSummary) { RecordViewerSectionDoctors(record: record) }
            }
        }

        Section {
            if record.isPet {
                let w = record.weights.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                entriesFold("Weight", columns: ["Date", "kg", "Comment"], dates: w.map(\.date),
                            rows: w.map { [dateText($0.date), String(format: "%.1f", $0.weightKg ?? 0), $0.comment] })
            } else {
                let b = record.blood.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                entriesFold("Blood", columns: ["Date", "Name", "Comment"], dates: b.map(\.date),
                            rows: b.map { [dateText($0.date), $0.name, $0.comment] })
            }

            let m = record.drugs.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            entriesFold("Medications", columns: ["Date", "Name & Dosage", "Comment"], dates: m.map(\.date),
                        rows: m.map { [dateText($0.date), $0.nameAndDosage, $0.comment] })

            let v = record.vaccinations.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            entriesFold("Vaccinations", columns: ["Date", "Name", "Place", "Comment"], dates: v.map(\.date),
                        rows: v.map { [dateText($0.date), $0.name, $0.place, $0.comment] })

            if !record.isPet {
                let a = record.allergy.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                entriesFold("Allergies", columns: ["Date", "Name", "Comment"], dates: a.map(\.date),
                            rows: a.map { [dateText($0.date), $0.name, $0.comment] })
            }

            let i = record.illness.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            entriesFold("Illnesses", columns: ["Name", "Date", "Comment"], dates: i.map(\.date),
                        rows: i.map { [$0.name, dateText($0.date), $0.informationOrComment] })

            let d = record.medicaldocument.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            entriesFold("Documents", columns: ["Name", "Date", "Note"], dates: d.map(\.date),
                        rows: d.map { [$0.name, dateText($0.date), $0.note] })

            let h = record.medicalhistory.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            entriesFold("History", columns: ["Name", "Date", "Contact", "Comment"], dates: h.map(\.date),
                        rows: h.map { [$0.name, dateText($0.date), $0.contact, $0.informationOrComment] })

            let r = record.risks.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            entriesFold("Risks", columns: ["Date", "Name", "Comment"], dates: r.map(\.date),
                        rows: r.map { [dateText($0.date), $0.name, $0.descriptionOrComment] })
        }

        Section {
            if record.isPet {
                Fold(title: "Costs", summary: costsSummary) { RecordViewerSectionPetYearlyCosts(record: record) }
            }
            Fold(title: "Record details", summary: joined([record.locationStatus.accessibilityLabel, "updated " + record.updatedAt.formatted(date: .abbreviated, time: .omitted)])) {
                RecordViewerSectionDetails(record: record)
            }
        }
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
        if isSharedReadOnly {
            // Do not allow local mutations to be persisted for read-only shares
            saveErrorMessage = "You don't have permission to edit this shared record."
            return
        }
        record.updatedAt = Date()
        do {
            try modelContext.save()
            // Automatically sync cloud-enabled records after save
            if record.isCloudEnabled {
                Task {
                    do {
                        try await CloudSyncService.shared.syncIfNeeded(record: record)
                    } catch {
                        // Log error but don't fail the save operation
                        ShareDebugStore.shared.appendLog("RecordEditorView: auto-sync failed after save: \(error)")
                    }
                }
            }
        } catch {
            saveErrorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveAndFinishEditing() {
        touchAndSave()
        isEditing = false
    }

    @MainActor
    private func refreshSharePermission() async {
        let perm = await CloudKitSharePermissionService.shared.permission(for: record)
        effectivePermission = perm
    }
}

#Preview {
    NavigationStack {
        RecordEditorView(record: MedicalRecord(), startEditing: true)
    }
    .modelContainer(for: MedicalRecord.self, inMemory: true)
}

