import SwiftUI
import SwiftData

struct RecordEditorSectionPetVet: View {
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    @State private var selectedEmergencyContactID: UUID?

    private var selectedContact: EmergencyContact? {
        guard let selectedEmergencyContactID else { return nil }
        return record.emergencyContacts.first(where: { $0.id == selectedEmergencyContactID })
    }

    private var hasContacts: Bool {
        !record.emergencyContacts.isEmpty
    }

    var body: some View {
        Section {
            contactPickerAndCopy

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

    @ViewBuilder
    private var contactPickerAndCopy: some View {
        if !hasContacts {
            Text("Add an Emergency Contact first, then you can select it as your vet contact.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Select Contact", selection: Binding(
                get: { selectedEmergencyContactID },
                set: { selectedEmergencyContactID = $0 }
            )) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(record.emergencyContacts) { contact in
                    Text(contact.name.isEmpty ? "(No Name)" : contact.name)
                        .tag(Optional(contact.id))
                }
            }

            Button("Copy from Selected Contact") {
                guard let contact = selectedContact else { return }
                record.copyVetDetails(from: contact)
                onChange()
            }
            .disabled(selectedContact == nil)
        }
    }
}
