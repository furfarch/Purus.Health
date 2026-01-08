import Foundation
import SwiftData

@Model
final class MedicalHistoryEntry {
    var date: Date?
    var name: String
    var contact: String
    var informationOrComment: String

    var record: MedicalRecord?

    init(date: Date? = nil, name: String = "", contact: String = "", informationOrComment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.contact = contact
        self.informationOrComment = informationOrComment
        self.record = record
    }
}
