import Foundation
import SwiftData

@Model
final class IllnessEntry {
    // Home server row id (empty until first home server sync)
    var syncID: String = ""
    var date: Date? = nil
    var name: String = ""
    var informationOrComment: String = ""

    var record: MedicalRecord? = nil

    init(date: Date? = nil, name: String = "", informationOrComment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.informationOrComment = informationOrComment
        self.record = record
    }
}
