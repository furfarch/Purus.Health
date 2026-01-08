import Foundation
import SwiftData

@Model
final class DrugEntry {
    var date: Date?
    var nameAndDosage: String
    var comment: String

    var record: MedicalRecord?

    init(date: Date? = nil, nameAndDosage: String = "", comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.nameAndDosage = nameAndDosage
        self.comment = comment
        self.record = record
    }
}
