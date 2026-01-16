import SwiftUI
import SwiftData

struct RecordEditorSectionDoctors: View {
    let modelContext: ModelContext
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    private var sortedIndices: [Int] {
        record.humanDoctors.indices.sorted { a, b in
            record.humanDoctors[a].type.localizedCaseInsensitiveCompare(record.humanDoctors[b].type) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            if record.humanDoctors.isEmpty {
                Text("Add up to 5 doctors (type + contact details).")
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedIndices, id: \.self) { idx in
                HStack {
                    TextField(
                        "Type (e.g., GP)",
                        text: Binding(
                            get: { record.humanDoctors[idx].type },
                            set: { record.humanDoctors[idx].type = $0; onChange() }
                        )
                    )

                    Spacer()

                    Button(role: .destructive) {
                        let removed = record.humanDoctors.remove(at: idx)
                        modelContext.delete(removed)
                        onChange()
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                #if canImport(ContactsUI)
                ContactPickerButton(title: "Pick from Contacts") { picked in
                    apply(contact: picked, toDoctorAt: idx)
                    onChange()
                }
                #endif

                TextField(
                    "Name",
                    text: Binding(
                        get: { record.humanDoctors[idx].name },
                        set: { record.humanDoctors[idx].name = $0; onChange() }
                    )
                )

                TextField(
                    "Phone",
                    text: Binding(
                        get: { record.humanDoctors[idx].phone },
                        set: { record.humanDoctors[idx].phone = $0; onChange() }
                    )
                )

                TextField(
                    "Email",
                    text: Binding(
                        get: { record.humanDoctors[idx].email },
                        set: { record.humanDoctors[idx].email = $0; onChange() }
                    )
                )

                TextField(
                    "Address",
                    text: Binding(
                        get: { record.humanDoctors[idx].address },
                        set: { record.humanDoctors[idx].address = $0; onChange() }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)

                TextField(
                    "Note",
                    text: Binding(
                        get: { record.humanDoctors[idx].note },
                        set: { record.humanDoctors[idx].note = $0; onChange() }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)

                if idx != sortedIndices.last {
                    Divider()
                }
            }

            Button("Add Doctor") {
                guard record.humanDoctors.count < 5 else { return }
                let doctor = HumanDoctorEntry(record: record)
                record.humanDoctors.append(doctor)
                onChange()
            }
            .disabled(record.humanDoctors.count >= 5)
        } header: {
            Label("Doctors", systemImage: "stethoscope")
        }
    }

    private func apply(contact: ContactPickerResult, toDoctorAt index: Int) {
        guard record.humanDoctors.indices.contains(index) else { return }

        let name = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            record.humanDoctors[index].name = name
        }

        if !contact.phone.isEmpty {
            record.humanDoctors[index].phone = contact.phone
        }

        if !contact.email.isEmpty {
            record.humanDoctors[index].email = contact.email
        }

        let address = contact.postalAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            record.humanDoctors[index].address = address
        }

        record.humanDoctors[index].updatedAt = Date()
    }
}
