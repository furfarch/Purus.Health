import SwiftUI
import SwiftData

struct RecordListView: View {
    @Environment(\.modelContext) private var modelContext
    // Wide screen (iPhone Duo unfolded, iPad): two columns, list left, record or settings right.
    // Narrow screen (folded, iPhone): one column as before.
    // The Duo reports a compact width even unfolded, so the real width decides too (two columns from 560 points; the Duo unfolded in landscape gives the app 594).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var screenWidth: CGFloat = 0
    private var isWide: Bool { horizontalSizeClass == .regular || screenWidth >= 560 }

    enum Detail: Hashable {
        case record(String)   // MedicalRecord.uuid (stable; the model id changes when a new record is saved)
        case settings
    }
    @State private var detail: Detail? = nil
    @State private var detailStartEditing: Bool = false
    @Query private var allRecords: [MedicalRecord]
    
    private var records: [MedicalRecord] {
        allRecords.sorted { $0.sortKey < $1.sortKey }
    }

    @State private var activeRecord: MedicalRecord? = nil
    @State private var showEditor: Bool = false
    @State private var startEditing: Bool = false
    @State private var showAbout: Bool = false
    @State private var showSettings: Bool = false
    @State private var saveErrorMessage: String?
    @State private var isRefreshing: Bool = false

    var body: some View {
        Group {
            if isWide {
                // fixed two columns (the system split view shows the list only as an overlay on the Duo)
                HStack(spacing: 0) {
                    NavigationStack {
                        recordList
                    }
                    .frame(width: min(320, max(240, screenWidth * 0.36)))
                    Divider()
                    detailView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                NavigationStack {
                    recordList
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .task {
            await CloudKitMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID).ensurePrivateDBSubscription()
            await ensureSharedDBSubscription(containerIdentifier: AppConfig.CloudKit.containerID)
        }
        .sheet(item: $activeRecord, onDismiss: { activeRecord = nil; startEditing = false }) { record in
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
        .overlay {
            if isRefreshing {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Syncing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    /// Right column on wide screens.
    @ViewBuilder
    private var detailView: some View {
        switch detail {
        case .record(let id):
            if let record = records.first(where: { $0.uuid == id }) {
                NavigationStack {
                    RecordEditorView(record: record, startEditing: detailStartEditing)
                }
                .id(id)
            } else {
                ContentUnavailableView("Select a record", systemImage: "person.text.rectangle")
            }
        case .settings:
            SettingsView(showsClose: false)
        case nil:
            ContentUnavailableView("Select a record", systemImage: "person.text.rectangle")
        }
    }

    private var recordList: some View {
            List {
                listContent
            }
            .refreshable {
                isRefreshing = true
                await refreshFromCloud()
                isRefreshing = false
            }
            .navigationTitle("Purus Health")
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
                        if isWide { detail = .settings } else { showSettings = true }
                    } label: {
                        Image(systemName: "gearshape")
                    }
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
                // macOS: use automatic placements so toolbar items render in the mac toolbar
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

        // Wide screen: open the new record on the right, in edit mode. Narrow: sheet as before.
        if isWide {
            detailStartEditing = true
            detail = .record(record.uuid)
            return
        }
        // Ensure the `startEditing` state is set before presenting the sheet so the editor opens in edit mode.
        startEditing = true
        activeRecord = record
    }

    private func deleteRecords(at offsets: IndexSet) {
        Task { @MainActor in
            for index in offsets.sorted(by: >) {
                let record = records[index]

                // If this record participates in CloudKit (owner or shared), delete from CloudKit first.
                // Not in home server mode: iCloud is paused there and the iCloud copy stays untouched.
                if !HomeServerSettings.isEnabled,
                   record.isCloudEnabled || record.isSharingEnabled || record.cloudShareRecordName != nil || record.cloudRecordName != nil {
                    do {
                        try await CloudSyncService.shared.deleteSyncRecord(forLocalRecord: record)
                        SharedImportSuppression.suppress(record.uuid)
                        // Notify other components to refresh shared state
                        NotificationCenter.default.post(name: NotificationNames.didChangeSharedRecords, object: nil)
                        record.isMarkedForDeletion = true
                        record.updatedAt = Date()
                        try? modelContext.save()
                    } catch {
                        // Surface error but continue with local deletion to keep UI responsive
                        saveErrorMessage = "Cloud delete failed: \(error.localizedDescription)"
                    }
                }

                // Local deletion
                modelContext.delete(record)
            }
            do { try modelContext.save() }
            catch { saveErrorMessage = "Delete failed: \(error.localizedDescription)" }
        }
    }



    @ViewBuilder
    private var listContent: some View {
        if records.isEmpty {
            Text("No records yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(records, id: \.persistentModelID) { record in
                if isWide {
                    // opens the record in the right column
                    Button {
                        detailStartEditing = false
                        detail = .record(record.uuid)
                    } label: {
                        rowLabel(record)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(detail == .record(record.uuid) ? Color.accentColor.opacity(0.15) : nil)
                } else {
                    NavigationLink {
                        RecordEditorView(record: record, startEditing: false)
                    } label: {
                        rowLabel(record)
                    }
                }
            }
            .onDelete(perform: deleteRecords)
        }
    }

    private func rowLabel(_ record: MedicalRecord) -> some View {
                    HStack {
                        Image(systemName: record.isPet ? "cat" : "person")

                        VStack(alignment: .leading) {
                            Text(record.displayName).font(.headline)
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
    }

    @MainActor
    private func refreshFromCloud() async {
        if HomeServerSettings.isEnabled {
            await HomeServerSyncService.shared.sync()
            return
        }

        let wantsCloudRefresh = allRecords.contains(where: { $0.isCloudEnabled || $0.locationStatus == .shared })
        guard wantsCloudRefresh else { return }

        // Push local changes for cloud-enabled records first
        let cloudEnabledRecords = allRecords.filter { $0.isCloudEnabled }
        for record in cloudEnabledRecords {
            do {
                try await CloudSyncService.shared.syncIfNeeded(record: record)
            } catch {
                ShareDebugStore.shared.appendLog("RecordListView: refresh upload sync failed for \(record.uuid): \(error)")
            }
        }

        // Ensure subscriptions exist so future changes arrive
        await CloudKitMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID).ensurePrivateDBSubscription()
        await ensureSharedDBSubscription(containerIdentifier: AppConfig.CloudKit.containerID)

        // Download changes from private zone using async API for determinism
        let privateFetcher = CloudKitMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
        do {
            _ = try await privateFetcher.fetchAllAsync()
        } catch {
            ShareDebugStore.shared.appendLog("RecordListView: private fetch failed: \(error)")
        }

        do {
            let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
            _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
        } catch {
            ShareDebugStore.shared.appendLog("RecordListView: refresh shared fetch failed: \(error)")
        }

        // Nudge UI to update immediately (particularly for deletions)
        modelContext.processPendingChanges()
        NotificationCenter.default.post(name: NotificationNames.didImportRecords, object: nil)
    }
}

#Preview {
    RecordListView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}

