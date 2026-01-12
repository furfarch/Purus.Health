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
            WeightEntry.self
        ])

        // Force a purely local store. This avoids Core Data's CloudKit validation rules
        // from preventing the app from launching while the schema is still evolving.
        // (You can re-enable CloudKit later with a dedicated migration pass.)
        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            // If the persistent store cannot be initialized, this is a critical error.
            // Log the error and crash with a clear message rather than silently falling back
            // to in-memory storage which would cause data loss.
            print("❌ CRITICAL ERROR: Failed to initialize persistent ModelContainer")
            print("Error details: \(error)")
            print("The app cannot continue without a persistent store.")
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { newPhase, _ in
            if newPhase == .active {
                Task { @MainActor in
                    let fetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData")
                    fetcher.setModelContext(self.modelContainer.mainContext)
                    fetcher.fetchAll()
                }
            }
        }
    }
}
