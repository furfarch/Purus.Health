import Foundation
import SwiftData

@Model
final class VaccinationEntry {
    var date: Date?
    var name: String
    var information: String
    var place: String
    var comment: String

    var record: MedicalRecord?

    init(date: Date? = nil, name: String = "", information: String = "", place: String = "", comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.information = information
        self.place = place
        self.comment = comment
        self.record = record
    }
}
