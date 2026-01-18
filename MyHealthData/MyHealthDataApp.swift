//
//  MyHealthDataApp.swift
//  MyHealthData
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

@main
struct MyHealthDataApp: App {
    private let modelContainer: ModelContainer
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

        self.cloudFetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData")

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            print("[MyHealthDataApp] Failed to create persistent ModelContainer: \(error)")
            let memoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            self.modelContainer = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }

        // Ensure the fetcher has the model context so imports can run
        self.cloudFetcher.setModelContext(self.modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, modelContainer.mainContext)
                .task {
                    // Best-effort: trigger import of any pending cloud/shared changes on launch
                    cloudFetcher.fetchChanges()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { newPhase, _ in
            if newPhase == .active {
                // Ensure fetcher has context and attempt to import incremental changes
                cloudFetcher.setModelContext(modelContainer.mainContext)
                cloudFetcher.fetchChanges()

                // Also attempt to fetch accepted/shared records across shared zones
                Task {
                    let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData", modelContext: modelContainer.mainContext)
                    do {
                        _ = try await sharedFetcher.fetchAllSharedAcrossZonesAsync()
                    } catch {
                        // Log to ShareDebugStore so the export includes any failure details
                        ShareDebugStore.shared.appendLog("MyHealthDataApp: active shared fetch failed: \(error)")
                    }
                }
            }
        }
    }
}
