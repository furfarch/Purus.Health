my health dataimport Foundation
import SwiftData

@Model
final class WeightEntry {
    var date: Date?
    var weightKg: Double
    var comment: String

    var record: MedicalRecord?

    init(date: Date? = nil, weightKg: Double = 0.0, comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.comment = comment
        self.record = record
    }
}
