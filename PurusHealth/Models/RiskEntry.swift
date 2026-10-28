import Foundation
import SwiftData

@Model
final class RiskEntry {
    // Home server row id (empty until first home server sync)
    var syncID: String = ""
    var date: Date? = nil
    var name: String = ""
    var descriptionOrComment: String = ""

    var record: MedicalRecord? = nil

    init(date: Date? = nil, name: String = "", descriptionOrComment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.descriptionOrComment = descriptionOrComment
        self.record = record
    }
}
