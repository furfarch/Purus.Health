import Foundation
import SwiftData

@Model
final class AllergyEntry {
    var date: Date?
    var name: String
    var information: String
    var comment: String

    var record: MedicalRecord?

    init(date: Date? = nil, name: String = "", information: String = "", comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.information = information
        self.comment = comment
        self.record = record
    }
}
