import SwiftUI
import SwiftData

struct RecordEditorSectionPersonal: View {
    @Bindable var record: MedicalRecord
    let onChange: () -> Void

    var body: some View {
        Section {
            if record.isPet {
                TextField("Name", text: $record.personalName)
                TextField("Animal ID (ANIS)", text: $record.personalAnimalID)

                TextField("Owner Name", text: $record.ownerName)
                TextField("Owner Phone", text: $record.ownerPhone)
                TextField("Owner Email", text: $record.ownerEmail)
            } else {
                TextField("Family Name", text: $record.personalFamilyName)
                TextField("Given Name", text: $record.personalGivenName)
                TextField("Nick Name", text: $record.personalNickName)
                TextField("Gender", text: $record.personalGender)

                DatePicker(
                    "Birthdate",
                    selection: Binding(
                        get: { record.personalBirthdate ?? Date() },
                        set: { record.personalBirthdate = $0 }
                    ),
                    displayedComponents: .date
                )

                TextField("Social Security / AHV Nummer", text: $record.personalSocialSecurityNumber)
                TextField("Address", text: $record.personalAddress, axis: .vertical)
                    .lineLimit(1...4)

                TextField("Health Insurance", text: $record.personalHealthInsurance)
                TextField("Health Insurance Number", text: $record.personalHealthInsuranceNumber)
                TextField("Employer", text: $record.personalEmployer)
            }
        } header: {
            Label("Personal Information", systemImage: "person.text.rectangle")
        }
        .onChange(of: record.personalFamilyName) { _, _ in onChange() }
        .onChange(of: record.personalGivenName) { _, _ in onChange() }
        .onChange(of: record.personalNickName) { _, _ in onChange() }
        .onChange(of: record.personalGender) { _, _ in onChange() }
        .onChange(of: record.personalBirthdate) { _, _ in onChange() }
        .onChange(of: record.personalSocialSecurityNumber) { _, _ in onChange() }
        .onChange(of: record.personalAddress) { _, _ in onChange() }
        .onChange(of: record.personalHealthInsurance) { _, _ in onChange() }
        .onChange(of: record.personalHealthInsuranceNumber) { _, _ in onChange() }
        .onChange(of: record.personalEmployer) { _, _ in onChange() }
        .onChange(of: record.personalName) { _, _ in onChange() }
        .onChange(of: record.personalAnimalID) { _, _ in onChange() }
        .onChange(of: record.ownerName) { _, _ in onChange() }
        .onChange(of: record.ownerPhone) { _, _ in onChange() }
        .onChange(of: record.ownerEmail) { _, _ in onChange() }
    }
}
