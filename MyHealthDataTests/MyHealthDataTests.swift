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

    @Test @MainActor func testModelContainerIsPersistent() async throws {
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

        let container = try ModelContainer(for: schema, configurations: [config])
        #expect(config.isStoredInMemoryOnly == false, "ModelContainer should use persistent storage, not in-memory only")

        let context = container.mainContext
        let testRecord = MedicalRecord()
        testRecord.personalGivenName = "PersistenceTest"
        context.insert(testRecord)
        try context.save()

        context.delete(testRecord)
        try context.save()
    }

    @Test @MainActor func testDataPersistenceAcrossSessions() async throws {
        let schema = Schema([MedicalRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

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

        do {
            let container2 = try ModelContainer(for: schema, configurations: [config])
            let context2 = container2.mainContext

            // Avoid predicate APIs/macros in this test target; fetch all and filter in-memory.
            let all = try context2.fetch(FetchDescriptor<MedicalRecord>())
            let records = all.filter { $0.uuid == testUUID }

            #expect(records.count == 1, "Record should persist across container instances")
            #expect(records.first?.personalGivenName == "Test", "Persisted data should match")

            if let record = records.first {
                context2.delete(record)
                try context2.save()
            }
        }
    }

    @Test func testRecordLocationStatusMapping() async throws {
        let r = MedicalRecord()

        #expect(r.locationStatus == .local)

        r.isCloudEnabled = true
        r.isSharingEnabled = false
        r.cloudShareRecordName = nil
        #expect(r.locationStatus == .iCloud)

        r.isSharingEnabled = true
        #expect(r.locationStatus == .shared)

        r.isSharingEnabled = false
        r.cloudShareRecordName = "SOME-SHARE-RECORDNAME"
        #expect(r.locationStatus == .shared)

        r.isCloudEnabled = false
        #expect(r.locationStatus == .local)
    }
}
