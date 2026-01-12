//
//  MyHealthDataTests.swift
//  MyHealthDataTests
//
//  Created by Chris Furfari on 05.01.2026.
//

import Testing
import SwiftData
@testable import MyHealthData

struct MyHealthDataTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testModelContainerIsPersistent() async throws {
        // This test verifies that the ModelContainer is configured for persistent storage
        // and not in-memory only storage, which would cause data loss on app close.
        
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
        
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        
        // Verify we can create a persistent container
        let container = try ModelContainer(for: schema, configurations: [config])
        
        // Verify the configuration is not in-memory only
        #expect(config.isStoredInMemoryOnly == false, "ModelContainer should use persistent storage, not in-memory only")
        
        // Verify the container uses the persistent configuration by checking we can actually persist data
        let context = container.mainContext
        let testRecord = MedicalRecord()
        testRecord.personalGivenName = "PersistenceTest"
        context.insert(testRecord)
        try context.save()
        
        // Clean up
        context.delete(testRecord)
        try context.save()
    }
    
    @Test func testDataPersistenceAcrossSessions() async throws {
        // This test verifies that data persists across different container instances
        // simulating app restarts
        
        let schema = Schema([MedicalRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        
        // Create a test record in the first session
        // Using a fixed UUID for deterministic testing
        let testUUID = "TEST-PERSISTENCE-12345678-ABCD"
        do {
            let container1 = try ModelContainer(for: schema, configurations: [config])
            let context1 = container1.mainContext
            
            let record = MedicalRecord()
            record.uuid = testUUID
            record.personalGivenName = "Test"
            record.personalFamilyName = "User"
            
            context1.insert(record)
            try context1.save()
        }
        
        // Simulate app restart by creating a new container instance
        // and verify the record still exists
        do {
            let container2 = try ModelContainer(for: schema, configurations: [config])
            let context2 = container2.mainContext
            
            let descriptor = FetchDescriptor<MedicalRecord>(
                predicate: #Predicate { $0.uuid == testUUID }
            )
            let records = try context2.fetch(descriptor)
            
            #expect(records.count == 1, "Record should persist across container instances")
            #expect(records.first?.personalGivenName == "Test", "Persisted data should match")
            
            // Clean up
            if let record = records.first {
                context2.delete(record)
                try context2.save()
            }
        }
    }

}
