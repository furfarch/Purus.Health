import Testing
import CloudKit
import SwiftData
@testable import PurusHealth

@MainActor
struct CloudMappingTests {
    private func makeContext() throws -> ModelContext {
        // In-memory only: never touch the default store.
        let container = try ModelContainer(for: MedicalRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @Test func roundTripKeepsAllFieldsAndLists() throws {
        let sourceContext = try makeContext()
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let src = MedicalRecord(
            createdAt: d, updatedAt: d,
            personalFamilyName: "Fam", personalGivenName: "Giv", personalNickName: "Nick", personalGender: "f",
            personalBirthdate: d, personalSocialSecurityNumber: "756", personalAddress: "Addr",
            personalHealthInsurance: "Ins", personalHealthInsuranceNumber: "123", personalEmployer: "Emp",
            isPet: true, personalName: "Rex", personalAnimalID: "ANIS1", petBreed: "Lab", petColor: "Black",
            ownerName: "Own", ownerPhone: "1", ownerEmail: "o@x",
            vetClinicName: "Clinic", vetContactName: "Vet", vetPhone: "2", vetEmail: "v@x", vetAddress: "VA", vetNote: "VN",
            emergencyName: "E", emergencyNumber: "3", emergencyEmail: "e@x"
        )
        sourceContext.insert(src)
        src.blood = [BloodEntry(date: d, name: "b", comment: "c", record: src)]
        src.drugs = [DrugEntry(date: d, nameAndDosage: "d", comment: "c", record: src)]
        src.vaccinations = [VaccinationEntry(date: d, name: "v", information: "i", place: "p", comment: "c", record: src)]
        src.allergy = [AllergyEntry(date: d, name: "a", information: "i", comment: "c", record: src)]
        src.illness = [IllnessEntry(date: d, name: "i", informationOrComment: "c", record: src)]
        src.risks = [RiskEntry(date: d, name: "r", descriptionOrComment: "c", record: src)]
        src.medicalhistory = [MedicalHistoryEntry(date: d, name: "h", contact: "x", informationOrComment: "c", record: src)]
        src.medicaldocument = [MedicalDocumentEntry(date: d, name: "m", note: "n", record: src)]
        src.humanDoctors = [HumanDoctorEntry(type: "GP", name: "Doc", record: src)]
        src.weights = [WeightEntry(date: d, weightKg: 12.5, comment: "w", record: src)]
        src.petYearlyCosts = [PetYearlyCostEntry(date: d, category: "Food", amount: 99, note: "n", record: src)]
        src.emergencyContacts = [EmergencyContact(name: "EC", phone: "4", email: "ec@x", note: "n", record: src)]

        let ck = CKRecord(recordType: "MedicalRecord", recordID: CKRecord.ID(recordName: src.uuid))
        CloudSyncService.shared.applyMedicalRecord(src, to: ck)

        let context = try makeContext()
        let dst = MedicalRecord(uuid: src.uuid)
        context.insert(dst)
        CloudKitMedicalRecordFetcher.apply(ckRecord: ck, to: dst, context: context)
        try context.save()

        let strings: [KeyPath<MedicalRecord, String>] = [
            \.personalFamilyName, \.personalGivenName, \.personalNickName, \.personalGender,
            \.personalSocialSecurityNumber, \.personalAddress, \.personalHealthInsurance,
            \.personalHealthInsuranceNumber, \.personalEmployer, \.personalName, \.personalAnimalID,
            \.petBreed, \.petColor, \.ownerName, \.ownerPhone, \.ownerEmail,
            \.vetClinicName, \.vetContactName, \.vetPhone, \.vetEmail, \.vetAddress, \.vetNote,
            \.emergencyName, \.emergencyNumber, \.emergencyEmail,
        ]
        for kp in strings { #expect(dst[keyPath: kp] == src[keyPath: kp]) }
        #expect(dst.isPet == src.isPet)
        #expect(dst.personalBirthdate == src.personalBirthdate)
        #expect(dst.createdAt == src.createdAt)
        #expect(dst.updatedAt == src.updatedAt)

        #expect(dst.blood.count == 1)
        #expect(dst.drugs.count == 1)
        #expect(dst.vaccinations.count == 1)
        #expect(dst.allergy.count == 1)
        #expect(dst.illness.count == 1)
        #expect(dst.risks.count == 1)
        #expect(dst.medicalhistory.count == 1)
        #expect(dst.medicaldocument.count == 1)
        #expect(dst.humanDoctors.count == 1)
        #expect(dst.weights.first?.weightKg == 12.5)
        #expect(dst.petYearlyCosts.first?.amount == 99)
        #expect(dst.emergencyContacts.first?.name == "EC")
    }

    @Test func applyMedicalRecordClearsTombstoneFlag() {
        let ck = CKRecord(recordType: "MedicalRecord")
        ck["isDeleted"] = 1 as NSNumber
        CloudSyncService.shared.applyMedicalRecord(MedicalRecord(), to: ck)
        #expect((ck["isDeleted"] as? NSNumber)?.intValue == 0)
    }
}
