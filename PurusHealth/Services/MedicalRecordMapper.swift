import Foundation

enum MedicalRecordMapper {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        // Dates are picked as local days; format them in the local time zone (UTC shifted them by a day)
        f.timeZone = TimeZone.current
        return f
    }()

    /// Oldest first; entries without a date go last.
    private static func byDate<T>(_ items: [T], _ date: (T) -> Date?) -> [T] {
        items.sorted { (date($0) ?? .distantFuture) < (date($1) ?? .distantFuture) }
    }

    static func toExport(record: MedicalRecord) -> MedicalRecordExport {
        let petInfo: MedicalRecordExport.PetInformation? = record.isPet ? .init(
            personalName: record.personalName,
            personalAnimalID: record.personalAnimalID,
            ownerName: record.ownerName,
            ownerPhone: record.ownerPhone,
            ownerEmail: record.ownerEmail,
            petBreed: record.petBreed,
            petColor: record.petColor,
            sex: record.personalGender,
            dateOfBirth: record.personalBirthdate.map { iso8601.string(from: $0) } ?? "",
            vetClinicName: record.vetClinicName,
            vetContactName: record.vetContactName,
            vetPhone: record.vetPhone,
            vetEmail: record.vetEmail,
            vetAddress: record.vetAddress,
            vetNote: record.vetNote
        ) : nil

        // Map emergency contacts; if none exist but legacy fields exist, create a single contact
        var emergencyContacts: [MedicalRecordExport.EmergencyContact] = []
        if !record.emergencyContacts.isEmpty {
            emergencyContacts = record.emergencyContacts.sortedByName.map { c in
                .init(name: c.name, phone: c.phone, email: c.email, note: c.note)
            }
        } else if !record.emergencyName.isEmpty || !record.emergencyNumber.isEmpty || !record.emergencyEmail.isEmpty {
            emergencyContacts = [.init(name: record.emergencyName, phone: record.emergencyNumber, email: record.emergencyEmail, note: "")]
        }

        return MedicalRecordExport(
            isPet: record.isPet,
            personalinformation: .init(
                personalFamilyName: record.personalFamilyName,
                personalGivenName: record.personalGivenName,
                personalNickName: record.personalNickName,
                personalGender: record.personalGender,
                personalBirthdate: record.personalBirthdate.map { iso8601.string(from: $0) } ?? "",
                personalSocialSecurityNumber: record.personalSocialSecurityNumber,
                personalAddress: record.personalAddress,
                personalHealthInsurance: record.personalHealthInsurance,
                personalHealthInsuranceNumber: record.personalHealthInsuranceNumber,
                personalEmployer: record.personalEmployer
            ),
            petinformation: petInfo,
            emergencyContacts: emergencyContacts,
            blood: byDate(record.blood, { $0.date }).map {
                .init(
                    bloodDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    bloodName: $0.name,
                    bloodComment: $0.comment
                )
            },
            drugs: byDate(record.drugs, { $0.date }).map {
                .init(
                    drugDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    drugName: $0.nameAndDosage,
                    drugComment: $0.comment
                )
            },
            vaccinations: byDate(record.vaccinations, { $0.date }).map {
                .init(
                    vaccinationDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    vaccinationName: $0.name,
                    vaccinationInfo: $0.information,
                    vaccinationPlace: $0.place,
                    vaccinationComment: $0.comment
                )
            },
            allergy: byDate(record.allergy, { $0.date }).map {
                .init(
                    allergyDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    allergyName: $0.name,
                    allergyInformation: $0.information,
                    allergyComment: $0.comment
                )
            },
            illness: byDate(record.illness, { $0.date }).map {
                .init(
                    illnessDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    illnessName: $0.name,
                    illnessComment: $0.informationOrComment
                )
            },
            risks: byDate(record.risks, { $0.date }).map {
                .init(
                    risksDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    risksName: $0.name,
                    risksComment: $0.descriptionOrComment
                )
            },
            medicalhistory: byDate(record.medicalhistory, { $0.date }).map {
                .init(
                    medicalhistoryDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    medicalhistoryName: $0.name,
                    medicalhistoryContact: $0.contact,
                    medicalhistoryComment: $0.informationOrComment
                )
            },
            medicaldocument: byDate(record.medicaldocument, { $0.date }).map {
                .init(
                    medicaldocumentDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    medicaldocumentName: $0.name,
                    medicaldocumentComment: $0.note
                )
            },
            // Only include weights for pets. Humans receive an empty weights array.
            weights: record.isPet ? byDate(record.weights, { $0.date }).map {
                .init(
                    weightDate: $0.date.map { iso8601.string(from: $0) } ?? "",
                    weightKg: $0.weightKg,
                    weightComment: $0.comment
                )
            } : [],
            doctors: record.humanDoctors.map {
                .init(doctorType: $0.type, doctorName: $0.name, doctorPhone: $0.phone, doctorEmail: $0.email, doctorAddress: $0.address, doctorNote: $0.note)
            },
            // Yearly costs are pet-only, like weights.
            petYearlyCosts: record.isPet ? byDate(record.petYearlyCosts, { $0.date }).map {
                .init(costDate: iso8601.string(from: $0.date), costYear: $0.year, costCategory: $0.category, costAmount: $0.amount, costNote: $0.note)
            } : []
        )
    }
}
