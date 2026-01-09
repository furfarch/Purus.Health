import Foundation
import SwiftData

@Model
final class WeightEntry {
    var date: Date? = nil
    var weightKg: Double = 0.0
    var comment: String = ""

    var record: MedicalRecord? = nil

    init(date: Date? = nil, weightKg: Double = 0.0, comment: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.comment = comment
        self.record = record
    }
}
