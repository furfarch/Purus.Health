import Foundation
import SwiftData

@Model
final class MedicalDocumentEntry {
    var date: Date?
    var name: String

    /// Note only. No links, no attachments, no stored-file references.
    var note: String

    var record: MedicalRecord?

    init(date: Date? = nil, name: String = "", note: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.note = note
        self.record = record
    }
}
