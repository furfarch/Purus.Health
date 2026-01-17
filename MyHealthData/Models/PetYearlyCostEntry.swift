import Foundation
import SwiftData

@Model
final class PetYearlyCostEntry {
    var createdAt: Date
    var updatedAt: Date

    // Local stable identifier
    var uuid: String
    var id: String { uuid }

    var year: Int
    var category: String
    var amount: Double
    var note: String

    // Inverse is declared on MedicalRecord.petYearlyCosts.
    var record: MedicalRecord?

    init(
        uuid: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        year: Int = Calendar.current.component(.year, from: Date()),
        category: String = "",
        amount: Double = 0,
        note: String = "",
        record: MedicalRecord? = nil
    ) {
        self.uuid = uuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.year = year
        self.category = category
        self.amount = amount
        self.note = note
        self.record = record
    }
}
