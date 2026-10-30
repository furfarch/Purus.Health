//
//  PurusHealthApp.swift
//  Purus Health
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

@main
struct PurusHealthApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    /// nil when the store could not be opened: then only an error screen is shown and nothing syncs.
    private let modelContainer: ModelContainer?
    private let storeError: String?
    @Environment(\.scenePhase) private var scenePhase: ScenePhase

    // Keep a single fetcher instance alive for the app lifetime.
    private let cloudFetcher: CloudKitMedicalRecordFetcher

    init() {
        let schema = Schema([
            MedicalRecord.self,
            BloodEntry.self,
            DrugEntry.self,
            VaccinationEntry.self,
            AllergyEntry.self,
            IllnessEntry.self,
            RiskEntry.self,
            MedicalHistoryEntry.self,
            MedicalDocumentEntry.self,
            EmergencyContact.self,
            WeightEntry.self,
            HumanDoctorEntry.self,
            PetYearlyCostEntry.self
        ])

        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        self.cloudFetcher = CloudKitMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID)

        do {
            let container = try ModelContainer(for: schema, configurations: [localConfig])
            self.modelContainer = container
            self.storeError = nil
            // Ensure the fetcher has the model context so imports can run
            self.cloudFetcher.setModelContext(container.mainContext)
            // Home server sync (optional mode)
            HomeServerSyncService.shared.configure(container: container)
        } catch {
            // No in-memory fallback: an empty store would make the next sync delete the server data and the emergency copy.
            self.modelContainer = nil
            self.storeError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .environment(\.modelContext, modelContainer.mainContext)
                    .task {
                        // Home server mode: the home server is the main copy, iCloud sync is paused.
                        if HomeServerSettings.isEnabled {
                            await HomeServerSyncService.shared.sync()
                            return
                        }

                        // Only trigger cloud fetch if user has enabled cloud sync or has cloud-enabled records.
                        // This prevents re-importing records that were deleted locally when cloud sync is off.
                        if await shouldFetchFromCloud() {
                            cloudFetcher.fetchChanges()
                        }

                        // Only fetch shared records if there are existing shared records locally.
                        // New shares are handled by the share acceptance flow (onOpenURL).
                        if await hasSharedRecordsLocally() {
                            await fetchSharedRecordsOnLaunch()
                        }

                        // If a share was accepted recently, force a shared fetch once on launch
                        if UserDefaults.standard.bool(forKey: "pendingSharedImport") {
                            await fetchSharedRecordsOnLaunch()
                            UserDefaults.standard.set(false, forKey: "pendingSharedImport")
                        }
                        
                        // Ensure CloudKit push subscriptions exist
                        await cloudFetcher.ensurePrivateDBSubscription()
                        await ensureSharedDBSubscription()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: HomeServerSyncService.didDisable)) { _ in
                        // home server off: its records were removed, load the iCloud records (and accepted shares) again
                        Task { @MainActor in
                            do { _ = try await cloudFetcher.fetchAllAsync() } catch {
                                ShareDebugStore.shared.appendLog("PurusHealthApp: iCloud fetch after home server off failed: \(error)")
                            }
                            await fetchSharedRecordsOnLaunch()
                        }
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        // Face ID: locked whenever the app goes to the background, asked again when it is back in front
                        if newPhase == .background { AppLock.shared.lock() }
                        // app switcher / Control Center: hide the records without locking
                        if newPhase == .inactive { AppLock.shared.cover() }
                        if newPhase == .active { AppLock.shared.appBecameActive() }
                        // Sync when app becomes active to get latest changes
                        if newPhase == .active {
                            Task { @MainActor in
                                if HomeServerSettings.isEnabled {
                                    await HomeServerSyncService.shared.sync()
                                    return
                                }

                                // Only sync if user has cloud-enabled records
                                if await shouldFetchFromCloud() {
                                    cloudFetcher.fetchChanges()
                                    await syncCloudEnabledRecords()
                                }

                                // Only fetch shared records if there are existing shared records locally
                                if await hasSharedRecordsLocally() {
                                    await fetchSharedRecordsOnLaunch()
                                }

                                // If a share was accepted while app was backgrounded, fetch now
                                if UserDefaults.standard.bool(forKey: "pendingSharedImport") {
                                    await fetchSharedRecordsOnLaunch()
                                    UserDefaults.standard.set(false, forKey: "pendingSharedImport")
                                }

                                // Ensure CloudKit push subscriptions exist
                                await cloudFetcher.ensurePrivateDBSubscription()
                                await ensureSharedDBSubscription()
                            }
                        }
                    }
                    .modelContainer(modelContainer)
            } else {
                StoreErrorView(message: storeError ?? "")
            }
        }
    }
    
    /// Returns true if cloud sync should be performed.
    @MainActor
    private func shouldFetchFromCloud() async -> Bool {
        // Check global cloud setting first - if enabled, always sync
        let globalCloudEnabled = UserDefaults.standard.bool(forKey: "cloudEnabled")
        if globalCloudEnabled { return true }

        // Check if any local records are cloud-enabled
        guard let context = modelContainer?.mainContext else { return false }
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isCloudEnabled == true })
        let count = (try? context.fetchCount(fetchDescriptor)) ?? 0
        return count > 0
    }

    /// Returns true if there are shared records locally that need to be updated.
    @MainActor
    private func hasSharedRecordsLocally() async -> Bool {
        guard let context = modelContainer?.mainContext else { return false }
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isSharingEnabled == true })
        let count = (try? context.fetchCount(fetchDescriptor)) ?? 0
        return count > 0
    }

    @MainActor
    private func syncCloudEnabledRecords() async {
        guard let context = modelContainer?.mainContext else { return }
        let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.isCloudEnabled == true })
        
        guard let records = try? context.fetch(fetchDescriptor) else { return }
        
        for record in records {
            do {
                try await CloudSyncService.shared.syncIfNeeded(record: record)
            } catch {
                // Best-effort: log error but continue syncing other records
                ShareDebugStore.shared.appendLog("PurusHealthApp: failed to sync record \(record.uuid): \(error)")
            }
        }
    }
    
    @MainActor
    private func fetchSharedRecordsOnLaunch() async {
        guard let modelContainer else { return }
        do {
            let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(
                containerIdentifier: AppConfig.CloudKit.containerID,
                modelContext: modelContainer.mainContext
            )
            _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
        } catch {
            // Best-effort: log but don't fail the app
            ShareDebugStore.shared.appendLog("PurusHealthApp: failed to fetch shared records on launch: \(error)")
        }
    }
    
    @MainActor
    private func ensureSharedDBSubscription() async {
        await PurusHealth.ensureSharedDBSubscription(containerIdentifier: AppConfig.CloudKit.containerID)
    }
}

/// Shown instead of the app when the data store cannot be opened (nothing is synced or overwritten in this state).
private struct StoreErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Purus Health cannot open its data")
                .font(.headline)
            Text("Nothing was changed or synced. Restart the app; if this stays, contact support.\n\n\(message)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
