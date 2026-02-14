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
                let doctor = record.humanDoctors[idx]
                VStack(alignment: .leading, spacing: 12) {
                    ContactPickerButton(title: "Pick from Contacts") { contact in
                        doctor.name = contact.displayName
                        doctor.phone = contact.phone
                        doctor.email = contact.email
                        doctor.address = contact.postalAddress
                        onChange()
                    }

                    HStack {
                        TextField(
                            "Type (e.g., GP)",
                            text: Binding(
                                get: { doctor.type },
                                set: { doctor.type = $0; onChange() }
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

                    TextField(
                        "Name",
                        text: Binding(
                            get: { doctor.name },
                            set: { doctor.name = $0; onChange() }
                        )
                    )

                    TextField(
                        "Phone",
                        text: Binding(
                            get: { doctor.phone },
                            set: { doctor.phone = $0; onChange() }
                        )
                    )

                    TextField(
                        "Email",
                        text: Binding(
                            get: { doctor.email },
                            set: { doctor.email = $0; onChange() }
                        )
                    )

                    TextField(
                        "Address",
                        text: Binding(
                            get: { doctor.address },
                            set: { doctor.address = $0; onChange() }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)

                    TextField(
                        "Note",
                        text: Binding(
                            get: { doctor.note },
                            set: { doctor.note = $0; onChange() }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                }
                .padding(.vertical, 4)

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
}
