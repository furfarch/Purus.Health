import SwiftUI
import SwiftData

struct RecordEditorSectionPetVet: View {
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    @State private var selectedEmergencyContactID: UUID?

    var body: some View {
        Section {
            ContactPickerButton(title: "Choose Vet from Contacts") { picked in
                if record.vetContactName.isEmpty { record.vetContactName = picked.displayName }
                if record.vetPhone.isEmpty { record.vetPhone = picked.phone }
                if record.vetEmail.isEmpty { record.vetEmail = picked.email }
                if record.vetAddress.isEmpty { record.vetAddress = picked.postalAddress }
                onChange()
            }

            if !record.emergencyContacts.isEmpty {
                Picker("Copy from Emergency Contact", selection: $selectedEmergencyContactID) {
                    Text("").tag(UUID?.none)
                    ForEach(record.emergencyContacts) { contact in
                        Text(contact.name.isEmpty ? "(No Name)" : contact.name)
                            .tag(Optional(contact.id))
                    }
                }

                Button("Copy from Selected Emergency Contact") {
                    guard let selectedID = selectedEmergencyContactID,
                          let contact = record.emergencyContacts.first(where: { $0.id == selectedID })
                    else { return }

                    record.copyVetDetails(from: contact)
                    onChange()
                }
                .disabled(selectedEmergencyContactID == nil)
            }

            TextField("Clinic Name", text: $record.vetClinicName)
            TextField("Contact Name", text: $record.vetContactName)
            TextField("Phone", text: $record.vetPhone)
            TextField("Email", text: $record.vetEmail)
            TextField("Address", text: $record.vetAddress, axis: .vertical)
                .lineLimit(1...3)
            TextField("Note", text: $record.vetNote, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Label("Veterinarian", systemImage: "stethoscope.circle")
        }
        .onAppear {
            if selectedEmergencyContactID == nil {
                selectedEmergencyContactID = record.emergencyContacts.first?.id
            }
        }
        .onChange(of: record.vetClinicName) { _, _ in onChange() }
        .onChange(of: record.vetContactName) { _, _ in onChange() }
        .onChange(of: record.vetPhone) { _, _ in onChange() }
        .onChange(of: record.vetEmail) { _, _ in onChange() }
        .onChange(of: record.vetAddress) { _, _ in onChange() }
        .onChange(of: record.vetNote) { _, _ in onChange() }
    }
}
