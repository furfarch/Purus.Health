import Foundation
import SwiftData

/// Maps app models to the home server tables (purus_health database).
/// All values are compared as "canonical" strings so that unchanged entries look identical
/// on both sides: dates as yyyy-MM-dd, decimals with 2 places, empty = "".
enum HSValue {
    static let dateColumns: Set<String> = ["entry_date", "birthdate", "date_of_birth"]
    static let decimalColumns: Set<String> = ["weight_kg", "amount"]
    static let intColumns: Set<String> = ["year"]
    static let boolColumns: Set<String> = ["is_pet", "active", "is_primary"]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // one fixed zone, so a date never shifts by a day when the phone is in another time zone
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ d: Date?) -> String {
        guard let d else { return "" }
        return dayFormatter.string(from: d)
    }

    static func parseDay(_ s: String?) -> Date? {
        guard let s, s.count >= 10 else { return nil }
        return dayFormatter.date(from: String(s.prefix(10)))
    }

    static func decimal(_ d: Double?) -> String {
        guard let d else { return "" }
        return String(format: "%.2f", d)
    }

    /// Canonical string for a raw JSON value from the server.
    static func canonical(column: String, raw: Any?) -> String {
        guard let raw, !(raw is NSNull) else { return "" }
        if dateColumns.contains(column) {
            let s = "\(raw)"
            return s.count >= 10 ? String(s.prefix(10)) : ""
        }
        if decimalColumns.contains(column) {
            if let n = raw as? NSNumber { return decimal(n.doubleValue) }
            if let s = raw as? String, let d = Double(s) { return decimal(d) }
            return ""
        }
        if intColumns.contains(column) {
            if let n = raw as? NSNumber { return String(n.intValue) }
            if let s = raw as? String, let i = Int(s) { return String(i) }
            return ""
        }
        if boolColumns.contains(column) {
            if let b = raw as? Bool { return b ? "true" : "false" }
            if let n = raw as? NSNumber { return n.boolValue ? "true" : "false" }
            return "\(raw)" == "true" ? "true" : "false"
        }
        if let s = raw as? String { return s }
        return "\(raw)"
    }

    /// JSON value to send for a canonical string ("" is sent as "" and stored as the column default).
    static func dbValue(column: String, canonical s: String) -> Any {
        if s.isEmpty { return "" }
        if decimalColumns.contains(column) { return Double(s) ?? 0 }
        if intColumns.contains(column) { return Int(s) ?? 0 }
        if boolColumns.contains(column) { return s == "true" }
        return s
    }

    static func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }
}

typealias HSRow = [String: String]

/// A child entry type that syncs with one home server table.
protocol HomeServerEntry: PersistentModel {
    static var table: String { get }
    static var columns: [String] { get }
    static func entries(of record: MedicalRecord) -> [Self]
    static func make(for record: MedicalRecord, in context: ModelContext) -> Self
    var syncKey: String { get set }
    func canonical() -> HSRow
    func apply(_ row: HSRow)
    /// Server row -> canonical row (override when fields are combined in the app).
    static func canonicalFromServer(_ row: HSRow) -> HSRow
    /// Canonical row -> columns to send (override when fields are split on the server).
    static func dbColumns(from row: HSRow, previousServerRow: HSRow?) -> HSRow
}

extension HomeServerEntry {
    static func canonicalFromServer(_ row: HSRow) -> HSRow {
        var out = HSRow()
        for c in columns { out[c] = row[c] ?? "" }
        return out
    }
    static func dbColumns(from row: HSRow, previousServerRow: HSRow?) -> HSRow { row }
}

// MARK: - Entry mappings

extension BloodEntry: HomeServerEntry {
    static var table: String { "blood" }
    static var columns: [String] { ["entry_date", "name", "comment"] }
    static func entries(of record: MedicalRecord) -> [BloodEntry] { record.blood }
    static func make(for record: MedicalRecord, in context: ModelContext) -> BloodEntry {
        let e = BloodEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "name": name, "comment": comment] }
    func apply(_ r: HSRow) { date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; comment = r["comment"] ?? "" }
}

extension DrugEntry: HomeServerEntry {
    static var table: String { "drugs" }
    static var columns: [String] { ["entry_date", "name", "comment"] }
    static func entries(of record: MedicalRecord) -> [DrugEntry] { record.drugs }
    static func make(for record: MedicalRecord, in context: ModelContext) -> DrugEntry {
        let e = DrugEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "name": nameAndDosage, "comment": comment] }
    func apply(_ r: HSRow) { date = HSValue.parseDay(r["entry_date"]); nameAndDosage = r["name"] ?? ""; comment = r["comment"] ?? "" }

    /// The web app keeps name and dosage apart; the app shows them as one field.
    static func canonicalFromServer(_ row: HSRow) -> HSRow {
        let name = row["name"] ?? ""
        let dosage = (row["dosage"] ?? "").trimmingCharacters(in: .whitespaces)
        let combined = dosage.isEmpty ? name : (name.isEmpty ? dosage : name + " " + dosage)
        return ["entry_date": row["entry_date"] ?? "", "name": combined, "comment": row["comment"] ?? ""]
    }

    static func dbColumns(from row: HSRow, previousServerRow: HSRow?) -> HSRow {
        var out = row
        let combined = row["name"] ?? ""
        let dosage = (previousServerRow?["dosage"] ?? "").trimmingCharacters(in: .whitespaces)
        if !dosage.isEmpty, combined.hasSuffix(" " + dosage) {
            out["name"] = String(combined.dropLast(dosage.count + 1))
            out["dosage"] = dosage
        } else if !dosage.isEmpty, combined == dosage {
            out["name"] = ""
            out["dosage"] = dosage
        } else {
            out["dosage"] = ""
        }
        return out
    }
}

extension VaccinationEntry: HomeServerEntry {
    static var table: String { "vaccinations" }
    static var columns: [String] { ["entry_date", "name", "information", "place", "comment"] }
    static func entries(of record: MedicalRecord) -> [VaccinationEntry] { record.vaccinations }
    static func make(for record: MedicalRecord, in context: ModelContext) -> VaccinationEntry {
        let e = VaccinationEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow {
        ["entry_date": HSValue.day(date), "name": name, "information": information, "place": place, "comment": comment]
    }
    func apply(_ r: HSRow) {
        date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; information = r["information"] ?? ""
        place = r["place"] ?? ""; comment = r["comment"] ?? ""
    }
}

extension AllergyEntry: HomeServerEntry {
    static var table: String { "allergies" }
    static var columns: [String] { ["entry_date", "name", "information", "comment"] }
    static func entries(of record: MedicalRecord) -> [AllergyEntry] { record.allergy }
    static func make(for record: MedicalRecord, in context: ModelContext) -> AllergyEntry {
        let e = AllergyEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "name": name, "information": information, "comment": comment] }
    func apply(_ r: HSRow) {
        date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; information = r["information"] ?? ""; comment = r["comment"] ?? ""
    }
}

extension IllnessEntry: HomeServerEntry {
    static var table: String { "illnesses" }
    static var columns: [String] { ["entry_date", "name", "comment"] }
    static func entries(of record: MedicalRecord) -> [IllnessEntry] { record.illness }
    static func make(for record: MedicalRecord, in context: ModelContext) -> IllnessEntry {
        let e = IllnessEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "name": name, "comment": informationOrComment] }
    func apply(_ r: HSRow) { date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; informationOrComment = r["comment"] ?? "" }
}

extension RiskEntry: HomeServerEntry {
    static var table: String { "risks" }
    static var columns: [String] { ["entry_date", "name", "comment"] }
    static func entries(of record: MedicalRecord) -> [RiskEntry] { record.risks }
    static func make(for record: MedicalRecord, in context: ModelContext) -> RiskEntry {
        let e = RiskEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "name": name, "comment": descriptionOrComment] }
    func apply(_ r: HSRow) { date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; descriptionOrComment = r["comment"] ?? "" }
}

extension MedicalHistoryEntry: HomeServerEntry {
    static var table: String { "medical_history" }
    static var columns: [String] { ["entry_date", "name", "contact", "comment"] }
    static func entries(of record: MedicalRecord) -> [MedicalHistoryEntry] { record.medicalhistory }
    static func make(for record: MedicalRecord, in context: ModelContext) -> MedicalHistoryEntry {
        let e = MedicalHistoryEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow {
        ["entry_date": HSValue.day(date), "name": name, "contact": contact, "comment": informationOrComment]
    }
    func apply(_ r: HSRow) {
        date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; contact = r["contact"] ?? ""; informationOrComment = r["comment"] ?? ""
    }
}

extension MedicalDocumentEntry: HomeServerEntry {
    static var table: String { "medical_documents" }
    static var columns: [String] { ["entry_date", "name", "comment"] }
    static func entries(of record: MedicalRecord) -> [MedicalDocumentEntry] { record.medicaldocument }
    static func make(for record: MedicalRecord, in context: ModelContext) -> MedicalDocumentEntry {
        let e = MedicalDocumentEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { syncID } set { syncID = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "name": name, "comment": note] }
    func apply(_ r: HSRow) { date = HSValue.parseDay(r["entry_date"]); name = r["name"] ?? ""; note = r["comment"] ?? "" }
}

extension WeightEntry: HomeServerEntry {
    static var table: String { "weights" }
    static var columns: [String] { ["entry_date", "weight_kg", "comment"] }
    static func entries(of record: MedicalRecord) -> [WeightEntry] { record.weights }
    static func make(for record: MedicalRecord, in context: ModelContext) -> WeightEntry {
        let e = WeightEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { uuid } set { uuid = newValue } }
    func canonical() -> HSRow { ["entry_date": HSValue.day(date), "weight_kg": HSValue.decimal(weightKg), "comment": comment] }
    func apply(_ r: HSRow) {
        date = HSValue.parseDay(r["entry_date"])
        weightKg = (r["weight_kg"]).flatMap { Double($0) }
        comment = r["comment"] ?? ""
        updatedAt = Date()
    }
}

extension HumanDoctorEntry: HomeServerEntry {
    static var table: String { "doctors" }
    static var columns: [String] { ["name", "specialty", "phone", "email", "address", "comment"] }
    static func entries(of record: MedicalRecord) -> [HumanDoctorEntry] { record.humanDoctors }
    static func make(for record: MedicalRecord, in context: ModelContext) -> HumanDoctorEntry {
        let e = HumanDoctorEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { uuid } set { uuid = newValue } }
    func canonical() -> HSRow {
        ["name": name, "specialty": type, "phone": phone, "email": email, "address": address, "comment": note]
    }
    func apply(_ r: HSRow) {
        name = r["name"] ?? ""; type = r["specialty"] ?? ""; phone = r["phone"] ?? ""
        email = r["email"] ?? ""; address = r["address"] ?? ""; note = r["comment"] ?? ""
        updatedAt = Date()
    }
}

extension EmergencyContact: HomeServerEntry {
    static var table: String { "emergency_contacts" }
    static var columns: [String] { ["name", "phone", "email", "note"] }
    static func entries(of record: MedicalRecord) -> [EmergencyContact] { record.emergencyContacts }
    static func make(for record: MedicalRecord, in context: ModelContext) -> EmergencyContact {
        let e = EmergencyContact(); context.insert(e); e.record = record; return e
    }
    var syncKey: String {
        get { id.uuidString.lowercased() }
        set { id = UUID(uuidString: newValue) ?? UUID() }
    }
    func canonical() -> HSRow { ["name": name, "phone": phone, "email": email, "note": note] }
    func apply(_ r: HSRow) { name = r["name"] ?? ""; phone = r["phone"] ?? ""; email = r["email"] ?? ""; note = r["note"] ?? "" }
}

extension PetYearlyCostEntry: HomeServerEntry {
    static var table: String { "pet_yearly_costs" }
    static var columns: [String] { ["entry_date", "year", "category", "amount", "comment"] }
    static func entries(of record: MedicalRecord) -> [PetYearlyCostEntry] { record.petYearlyCosts }
    static func make(for record: MedicalRecord, in context: ModelContext) -> PetYearlyCostEntry {
        let e = PetYearlyCostEntry(); context.insert(e); e.record = record; return e
    }
    var syncKey: String { get { uuid } set { uuid = newValue } }
    func canonical() -> HSRow {
        ["entry_date": HSValue.day(date), "year": String(year), "category": category,
         "amount": HSValue.decimal(amount), "comment": note]
    }
    /// The app always has a date for yearly costs; a server row without date maps to 1 January of its year.
    static func canonicalFromServer(_ row: HSRow) -> HSRow {
        var out = HSRow()
        for c in columns { out[c] = row[c] ?? "" }
        if (out["entry_date"] ?? "").isEmpty, let y = out["year"], !y.isEmpty { out["entry_date"] = "\(y)-01-01" }
        return out
    }

    func apply(_ r: HSRow) {
        if let d = HSValue.parseDay(r["entry_date"]) { date = d }
        if let y = r["year"].flatMap({ Int($0) }) { year = y }
        category = r["category"] ?? ""
        amount = r["amount"].flatMap { Double($0) } ?? 0
        note = r["comment"] ?? ""
        updatedAt = Date()
    }
}

// MARK: - Profile mappings

enum HSProfile {
    static let personalColumns = [
        "family_name", "given_name", "nick_name", "gender", "birthdate", "social_security_number_enc",
        "address", "health_insurance", "health_insurance_number", "employer"
    ]
    static let petColumns = [
        "name", "animal_id", "date_of_birth", "breed", "color", "gender",
        "owner_name", "owner_phone", "owner_email",
        "vet_clinic_name", "vet_contact_name", "vet_phone", "vet_email", "vet_address", "vet_note"
    ]

    static func personal(_ r: MedicalRecord) -> HSRow {
        [
            "family_name": r.personalFamilyName, "given_name": r.personalGivenName, "nick_name": r.personalNickName,
            "gender": r.personalGender, "birthdate": HSValue.day(r.personalBirthdate),
            "social_security_number_enc": r.personalSocialSecurityNumber, "address": r.personalAddress,
            "health_insurance": r.personalHealthInsurance, "health_insurance_number": r.personalHealthInsuranceNumber,
            "employer": r.personalEmployer
        ]
    }

    static func applyPersonal(_ row: HSRow, to r: MedicalRecord) {
        r.personalFamilyName = row["family_name"] ?? ""
        r.personalGivenName = row["given_name"] ?? ""
        r.personalNickName = row["nick_name"] ?? ""
        r.personalGender = row["gender"] ?? ""
        r.personalBirthdate = HSValue.parseDay(row["birthdate"])
        r.personalSocialSecurityNumber = row["social_security_number_enc"] ?? ""
        r.personalAddress = row["address"] ?? ""
        r.personalHealthInsurance = row["health_insurance"] ?? ""
        r.personalHealthInsuranceNumber = row["health_insurance_number"] ?? ""
        r.personalEmployer = row["employer"] ?? ""
    }

    static func pet(_ r: MedicalRecord) -> HSRow {
        [
            "name": r.personalName, "animal_id": r.personalAnimalID, "date_of_birth": HSValue.day(r.personalBirthdate),
            "breed": r.petBreed, "color": r.petColor, "gender": r.personalGender,
            "owner_name": r.ownerName, "owner_phone": r.ownerPhone, "owner_email": r.ownerEmail,
            "vet_clinic_name": r.vetClinicName, "vet_contact_name": r.vetContactName, "vet_phone": r.vetPhone,
            "vet_email": r.vetEmail, "vet_address": r.vetAddress, "vet_note": r.vetNote
        ]
    }

    static func applyPet(_ row: HSRow, to r: MedicalRecord) {
        r.personalName = row["name"] ?? ""
        r.personalAnimalID = row["animal_id"] ?? ""
        r.personalBirthdate = HSValue.parseDay(row["date_of_birth"])
        r.petBreed = row["breed"] ?? ""
        r.petColor = row["color"] ?? ""
        r.personalGender = row["gender"] ?? ""
        r.ownerName = row["owner_name"] ?? ""
        r.ownerPhone = row["owner_phone"] ?? ""
        r.ownerEmail = row["owner_email"] ?? ""
        r.vetClinicName = row["vet_clinic_name"] ?? ""
        r.vetContactName = row["vet_contact_name"] ?? ""
        r.vetPhone = row["vet_phone"] ?? ""
        r.vetEmail = row["vet_email"] ?? ""
        r.vetAddress = row["vet_address"] ?? ""
        r.vetNote = row["vet_note"] ?? ""
    }
}
