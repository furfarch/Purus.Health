import Foundation

// MARK: - Codable structs for CloudKit serialization
// These structs are used to serialize SwiftData relationships to JSON for CloudKit storage
// and deserialize them back when syncing from CloudKit.

struct CodableBloodEntry: Codable {
    let date: Double?
    let name: String
    let comment: String
}

struct CodableDrugEntry: Codable {
    let date: Double?
    let nameAndDosage: String
    let comment: String
}

struct CodableVaccinationEntry: Codable {
    let date: Double?
    let name: String
    let information: String
    let place: String
    let comment: String
}

struct CodableAllergyEntry: Codable {
    let date: Double?
    let name: String
    let information: String
    let comment: String
}

struct CodableIllnessEntry: Codable {
    let date: Double?
    let name: String
    let informationOrComment: String
}

struct CodableRiskEntry: Codable {
    let date: Double?
    let name: String
    let descriptionOrComment: String
}

struct CodableMedicalHistoryEntry: Codable {
    let date: Double?
    let name: String
    let contact: String
    let informationOrComment: String
}

struct CodableMedicalDocumentEntry: Codable {
    let date: Double?
    let name: String
    let note: String
}

struct CodableHumanDoctorEntry: Codable {
    let uuid: String
    let createdAt: Double
    let updatedAt: Double
    let type: String
    let name: String
    let phone: String
    let email: String
    let address: String
    let note: String
}

struct CodableWeightEntry: Codable {
    let uuid: String
    let createdAt: Double
    let updatedAt: Double
    let date: Double?
    let weightKg: Double?
    let comment: String
}

struct CodablePetYearlyCostEntry: Codable {
    let uuid: String
    let createdAt: Double
    let updatedAt: Double
    let date: Double
    let year: Int
    let category: String
    let amount: Double
    let note: String
}

struct CodableEmergencyContact: Codable {
    let id: String
    let name: String
    let phone: String
    let email: String
    let note: String
}
