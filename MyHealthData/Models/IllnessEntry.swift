import Foundation
import SwiftData

@Model
final class IllnessEntry {
    var date: Date?
    var name: String
    var informationOrComment: String

    var record: MedicalRecord?

    init(date: Date? = nil, name: String = "", informationOrComment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.informationOrComment = informationOrComment
        self.record = record
    }
}
