import Foundation

enum RecordSection: String, CaseIterable, Identifiable {
    case personal
    case emergency
    case blood
    case drugs
    case vaccinations
    case allergies
    case illnesses
    case medicalDocuments
    case medicalHistory
    case risks
    case weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal"
        case .emergency: return "Emergency"
        case .blood: return "Blood"
        case .drugs: return "Medications"
        case .vaccinations: return "Vaccinations"
        case .allergies: return "Allergies"
        case .illnesses: return "Illnesses"
        case .medicalDocuments: return "Documents"
        case .medicalHistory: return "History"
        case .risks: return "Risks"
        case .weight: return "Weight"
        }
    }

    var sfSymbol: String {
        switch self {
        case .personal: return "person.text.rectangle"
        case .emergency: return "cross.case"
        case .blood: return "drop"
        case .drugs: return "pills"
        case .vaccinations: return "syringe"
        case .allergies: return "allergens"
        case .illnesses: return "stethoscope"
        case .medicalDocuments: return "doc.text"
        case .medicalHistory: return "clock.arrow.circlepath"
        case .risks: return "exclamationmark.triangle"
        case .weight: return "scalemass"
        }
    }
}
