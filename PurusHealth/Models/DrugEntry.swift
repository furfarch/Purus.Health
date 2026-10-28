import Foundation
import SwiftData

@Model
final class DrugEntry {
    // Home server row id (empty until first home server sync)
    var syncID: String = ""
    var date: Date? = nil
    var nameAndDosage: String = ""
    var comment: String = ""

    var record: MedicalRecord? = nil

    init(date: Date? = nil, nameAndDosage: String = "", comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.nameAndDosage = nameAndDosage
        self.comment = comment
        self.record = record
    }
}
