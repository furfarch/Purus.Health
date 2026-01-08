import Foundation
import SwiftData

@Model
final class MedicalRecord {
    var createdAt: Date
    var updatedAt: Date

    // Record type
    var isPet: Bool

    // Personal Information
    // Legacy human fields (kept for backward compatibility)
    var personalFamilyName: String
    var personalGivenName: String
    var personalNickName: String
    var personalGender: String
    var personalBirthdate: Date?
    var personalSocialSecurityNumber: String
    var personalAddress: String
    var personalHealthInsurance: String
    var personalHealthInsuranceNumber: String
    var personalEmployer: String

    // New pet-friendly fields (kept alongside legacy fields)
    var personalName: String
    var personalAnimalID: String
    var ownerName: String
    var ownerPhone: String
    var ownerEmail: String

    // Emergency Contact(s)
    // Legacy single contact fields are kept for migration/backward compatibility
    var emergencyName: String
    var emergencyNumber: String
    var emergencyEmail: String

    // New: multiple emergency contacts
    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.record)
    var emergencyContacts: [EmergencyContact]

    @Relationship(deleteRule: .cascade, inverse: \BloodEntry.record)
    var blood: [BloodEntry]

    @Relationship(deleteRule: .cascade, inverse: \DrugEntry.record)
    var drugs: [DrugEntry]

    @Relationship(deleteRule: .cascade, inverse: \VaccinationEntry.record)
    var vaccinations: [VaccinationEntry]

    @Relationship(deleteRule: .cascade, inverse: \AllergyEntry.record)
    var allergy: [AllergyEntry]

    @Relationship(deleteRule: .cascade, inverse: \IllnessEntry.record)
    var illness: [IllnessEntry]

    @Relationship(deleteRule: .cascade, inverse: \RiskEntry.record)
    var risks: [RiskEntry]

    @Relationship(deleteRule: .cascade, inverse: \MedicalHistoryEntry.record)
    var medicalhistory: [MedicalHistoryEntry]

    @Relationship(deleteRule: .cascade, inverse: \MedicalDocumentEntry.record)
    var medicaldocument: [MedicalDocumentEntry]

    // New: weights for pets (and humans if desired)
    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.record)
    var weights: [WeightEntry]

    init(
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPet: Bool = false,
        // Legacy human initializer params
        personalFamilyName: String = "",
        personalGivenName: String = "",
        personalNickName: String = "",
        personalGender: String = "",
        personalBirthdate: Date? = nil,
        personalSocialSecurityNumber: String = "",
        personalAddress: String = "",
        personalHealthInsurance: String = "",
        personalHealthInsuranceNumber: String = "",
        personalEmployer: String = "",
        // New pet-friendly params
        personalName: String = "",
        personalAnimalID: String = "",
        ownerName: String = "",
        ownerPhone: String = "",
        ownerEmail: String = "",
        // Emergency
        emergencyName: String = "",
        emergencyNumber: String = "",
        emergencyEmail: String = "",
        // Relationships
        blood: [BloodEntry] = [],
        drugs: [DrugEntry] = [],
        vaccinations: [VaccinationEntry] = [],
        allergy: [AllergyEntry] = [],
        illness: [IllnessEntry] = [],
        risks: [RiskEntry] = [],
        medicalhistory: [MedicalHistoryEntry] = [],
        medicaldocument: [MedicalDocumentEntry] = [],
        emergencyContacts: [EmergencyContact] = [],
        weights: [WeightEntry] = []
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        self.isPet = isPet

        self.personalFamilyName = personalFamilyName
        self.personalGivenName = personalGivenName
        self.personalNickName = personalNickName
        self.personalGender = personalGender
        self.personalBirthdate = personalBirthdate
        self.personalSocialSecurityNumber = personalSocialSecurityNumber
        self.personalAddress = personalAddress
        self.personalHealthInsurance = personalHealthInsurance
        self.personalHealthInsuranceNumber = personalHealthInsuranceNumber
        self.personalEmployer = personalEmployer

        self.personalName = personalName
        self.personalAnimalID = personalAnimalID
        self.ownerName = ownerName
        self.ownerPhone = ownerPhone
        self.ownerEmail = ownerEmail

        self.emergencyName = emergencyName
        self.emergencyNumber = emergencyNumber
        self.emergencyEmail = emergencyEmail

        self.emergencyContacts = emergencyContacts

        self.blood = blood
        self.drugs = drugs
        self.vaccinations = vaccinations
        self.allergy = allergy
        self.illness = illness
        self.risks = risks
        self.medicalhistory = medicalhistory
        self.medicaldocument = medicaldocument

        self.weights = weights
    }

    // Computed display name used by the UI
    var displayName: String {
        if isPet {
            let name = personalName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Medical Record" : name
        } else {
            let family = personalFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let given = personalGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
            if family.isEmpty && given.isEmpty {
                return "Medical Record"
            }
            return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}
