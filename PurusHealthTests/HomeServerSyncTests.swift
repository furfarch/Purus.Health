import Testing
import Foundation
import SwiftData
@testable import PurusHealth

@MainActor
struct HomeServerSyncTests {
    private let tables = ["profiles", "personal_information", "pet_information", "blood", "drugs", "vaccinations",
                          "allergies", "illnesses", "risks", "medical_history", "medical_documents", "weights",
                          "doctors", "emergency_contacts", "pet_yearly_costs"]

    private func fullAnswer() -> [String: Any] {
        var resp: [String: Any] = [:]
        for t in tables { resp[t] = [[String: Any]]() }
        return resp
    }

    private func memoryContext() throws -> ModelContext {
        let schema = Schema([MedicalRecord.self, BloodEntry.self, DrugEntry.self, VaccinationEntry.self, AllergyEntry.self,
                             IllnessEntry.self, RiskEntry.self, MedicalHistoryEntry.self, MedicalDocumentEntry.self,
                             EmergencyContact.self, WeightEntry.self, HumanDoctorEntry.self, PetYearlyCostEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func missingTableIsAnError() throws {
        var resp = fullAnswer()
        _ = try HomeServerSyncService.shared.parseServer(resp)
        resp.removeValue(forKey: "weights")
        #expect(throws: HomeServerSyncService.SyncError.self) { try HomeServerSyncService.shared.parseServer(resp) }
    }

    @Test func emptyServerDoesNotWipeLocalRecords() throws {
        let context = try memoryContext()
        context.insert(MedicalRecord())
        try context.save()
        let server = try HomeServerSyncService.shared.parseServer(fullAnswer())
        #expect(throws: HomeServerSyncService.SyncError.self) {
            try HomeServerSyncService.shared.checkApplicable(server: server, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<MedicalRecord>()) == 1)
    }

    @Test func pushAnswerNeedsStatusOk() throws {
        try HomeServerSyncService.checkPushAnswer(["status": "ok"])
        #expect(throws: HomeServerSyncService.SyncError.self) { try HomeServerSyncService.checkPushAnswer([:]) }
        #expect(throws: HomeServerSyncService.SyncError.self) { try HomeServerSyncService.checkPushAnswer(["status": "error"]) }
    }

    @Test func dayRoundTripIsStableInOtherTimeZones() {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        for zone in ["Pacific/Auckland", "America/Los_Angeles", "Asia/Tokyo"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            #expect(HSValue.day(HSValue.parseDay("2024-03-05")) == "2024-03-05")
            // the same instant everywhere: midnight in Zurich, not in the phone's zone
            var zurich = Calendar(identifier: .gregorian)
            zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
            #expect(HSValue.parseDay("2024-03-05") == zurich.date(from: DateComponents(year: 2024, month: 3, day: 5)))
            #expect(HSValue.day(HSValue.parseDay("1980-12-31T00:00:00Z")) == "1980-12-31")
        }
    }

    @Test func drugNameAndDosageSplit() {
        let server: HSRow = ["entry_date": "2024-01-01", "name": "Ibuprofen", "dosage": "400 mg", "comment": ""]
        let canon = DrugEntry.canonicalFromServer(server)
        #expect(canon["name"] == "Ibuprofen 400 mg")
        let out = DrugEntry.dbColumns(from: canon, previousServerRow: server)
        #expect(out["name"] == "Ibuprofen")
        #expect(out["dosage"] == "400 mg")
        // dosage edited away in the app: everything goes into name
        let edited = DrugEntry.dbColumns(from: ["name": "Ibuprofen 200 mg"], previousServerRow: server)
        #expect(edited["name"] == "Ibuprofen 200 mg")
        #expect(edited["dosage"] == "")
    }
}
