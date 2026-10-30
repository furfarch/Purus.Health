import SwiftUI
import SwiftData

struct RecordEditorSectionEmergency: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section {
            TextField("Emergency Contact Name", text: $record.emergencyName)
            TextField("Emergency Contact Number", text: $record.emergencyNumber)
            TextField("Emergency Contact Email", text: $record.emergencyEmail)

            // Bound to the objects (not indices) so deleting a focused row cannot index out of range.
            ForEach(record.emergencyContacts.sortedByName, id: \.id) { contact in
                EmergencyContactRowView(contact: contact, onChange: onChange) {
                    record.emergencyContacts.removeAll { $0.id == contact.id }
                    modelContext.delete(contact)
                    onChange()
                }
            }

            Button("Add Emergency Contact") {
                let contact = EmergencyContact(record: record)
                record.emergencyContacts.append(contact)
                onChange()
            }
        } header: {
            Label("Emergency Information", systemImage: "cross.case")
        }
        .onChange(of: record.emergencyName) { onChange() }
        .onChange(of: record.emergencyNumber) { onChange() }
        .onChange(of: record.emergencyEmail) { onChange() }
    }
}

struct EmergencyContactRowView: View {
    @Bindable var contact: EmergencyContact
    let onChange: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("Name", text: $contact.name)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
        }
        TextField("Phone", text: $contact.phone)
        TextField("Email", text: $contact.email)
        TextField("Note", text: $contact.note, axis: .vertical)
            .lineLimit(1...3)
            .onChange(of: contact.name) { onChange() }
            .onChange(of: contact.phone) { onChange() }
            .onChange(of: contact.email) { onChange() }
            .onChange(of: contact.note) { onChange() }
    }
}

extension Array where Element == EmergencyContact {
    /// Stable display order (no order field in the model).
    var sortedByName: [EmergencyContact] {
        sorted {
            let c = $0.name.localizedCaseInsensitiveCompare($1.name)
            return c == .orderedSame ? $0.id.uuidString < $1.id.uuidString : c == .orderedAscending
        }
    }
}
