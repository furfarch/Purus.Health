# CloudKit JSON Storage - How It Works

## Overview

This document explains how relationship arrays (vaccinations, medications, weight entries, etc.) are synced to CloudKit using JSON serialization.

## Architecture

CloudKit has a limitation: it doesn't support direct array relationships like SwiftData does. The standard solution is to serialize arrays as JSON strings.

### Flow Diagram

```
SwiftData Objects          JSON Serialization          CloudKit
──────────────────         ──────────────────         ─────────
[BloodEntry]      ─────>   "bloodEntries" field   ─────>  CKRecord
  - date                   (STRING containing                
  - name                    JSON array)
  - comment
```

## Example: Vaccination Entries

### In SwiftData (Local App Storage)
```swift
record.vaccinations = [
    VaccinationEntry(
        date: Date(timeIntervalSince1970: 1708041600),
        name: "COVID-19 Booster",
        information: "Pfizer",
        place: "City Hospital",
        comment: "No side effects"
    ),
    VaccinationEntry(
        date: Date(timeIntervalSince1970: 1710720000),
        name: "Flu Shot",
        information: "Annual",
        place: "Pharmacy",
        comment: "Slight soreness"
    )
]
```

### In CloudKit (Cloud Storage)
The `vaccinationEntries` field (type: STRING) contains:
```json
[
  {
    "date": 1708041600,
    "name": "COVID-19 Booster",
    "information": "Pfizer",
    "place": "City Hospital",
    "comment": "No side effects"
  },
  {
    "date": 1710720000,
    "name": "Flu Shot",
    "information": "Annual",
    "place": "Pharmacy",
    "comment": "Slight soreness"
  }
]
```

**Note:** The date is stored as Unix timestamp (seconds since 1970) and converted back to Date when deserializing.

## Example: Weight Entries

### In SwiftData
```swift
record.weights = [
    WeightEntry(
        uuid: "uuid-1",
        createdAt: Date(),
        updatedAt: Date(),
        date: Date(timeIntervalSince1970: 1708041600),
        weightKg: 75.5,
        comment: "Morning weight"
    ),
    WeightEntry(
        uuid: "uuid-2",
        createdAt: Date(),
        updatedAt: Date(),
        date: Date(timeIntervalSince1970: 1710720000),
        weightKg: 74.2,
        comment: "After diet"
    )
]
```

### In CloudKit
The `weightEntries` field (type: STRING) contains:
```json
[
  {
    "uuid": "uuid-1",
    "createdAt": 1708041600,
    "updatedAt": 1708041600,
    "date": 1708041600,
    "weightKg": 75.5,
    "comment": "Morning weight"
  },
  {
    "uuid": "uuid-2",
    "createdAt": 1710720000,
    "updatedAt": 1710720000,
    "date": 1710720000,
    "weightKg": 74.2,
    "comment": "After diet"
  }
]
```

## All Relationship Fields

Each of these CloudKit fields stores a JSON array with complete entry data:

| CloudKit Field | SwiftData Type | Key Fields Preserved |
|---------------|----------------|---------------------|
| `bloodEntries` | `[BloodEntry]` | date, name, comment |
| `drugEntries` | `[DrugEntry]` | date, nameAndDosage, comment |
| `vaccinationEntries` | `[VaccinationEntry]` | date, name, information, place, comment |
| `allergyEntries` | `[AllergyEntry]` | date, name, information, comment |
| `illnessEntries` | `[IllnessEntry]` | date, name, informationOrComment |
| `riskEntries` | `[RiskEntry]` | date, name, descriptionOrComment |
| `medicalHistoryEntries` | `[MedicalHistoryEntry]` | date, name, contact, informationOrComment |
| `medicalDocumentEntries` | `[MedicalDocumentEntry]` | date, name, note |
| `humanDoctorEntries` | `[HumanDoctorEntry]` | uuid, createdAt, updatedAt, type, name, phone, email, address, note |
| `weightEntries` | `[WeightEntry]` | uuid, createdAt, updatedAt, date, weightKg, comment |
| `petYearlyCostEntries` | `[PetYearlyCostEntry]` | uuid, createdAt, updatedAt, date, year, category, amount, note |
| `emergencyContactEntries` | `[EmergencyContact]` | id, name, phone, email, note |

## Data Preservation

✅ **All data is preserved** including:
- Dates (stored as Unix timestamps, converted to Date objects)
- Multiple entries (arrays can contain 0-n items)
- All fields from the original SwiftData models
- Order is maintained

## Implementation Details

### Serialization (Local → CloudKit)
```swift
// CloudSyncService.swift:723-726
let codableBlood = record.blood.map { 
    CodableBloodEntry(
        date: $0.date?.timeIntervalSince1970, 
        name: $0.name, 
        comment: $0.comment
    ) 
}
if let bloodJSON = try? JSONEncoder().encode(codableBlood), 
   let bloodString = String(data: bloodJSON, encoding: .utf8) {
    ckRecord["bloodEntries"] = bloodString as NSString
}
```

### Deserialization (CloudKit → Local)
```swift
// CloudKitMedicalRecordFetcher.swift:333-343
if let bloodString = ckRecord["bloodEntries"] as? String,
   let bloodData = bloodString.data(using: .utf8),
   let codableBlood = try? JSONDecoder().decode([CodableBloodEntry].self, from: bloodData) {
    // Clear existing entries
    for entry in record.blood {
        context.delete(entry)
    }
    // Create new SwiftData objects from JSON
    record.blood = codableBlood.map { codable in
        BloodEntry(
            date: codable.date.map { Date(timeIntervalSince1970: $0) }, 
            name: codable.name, 
            comment: codable.comment, 
            record: record
        )
    }
}
```

## Why This Approach?

1. **CloudKit Limitation**: CloudKit doesn't support direct relationship arrays
2. **Standard Pattern**: JSON serialization is the recommended approach for complex data
3. **Flexibility**: Easy to add new fields to entries without schema changes
4. **Efficiency**: Single field per relationship type, not separate records per entry
5. **Data Integrity**: All fields preserved, no data loss

## Schema Requirements

For this to work, the CloudKit schema MUST define these STRING fields. This was missing in PR #46, which is why sync wasn't working. The schema update in this PR adds all 12 required fields.

## Frequently Asked Questions

**Q: Why not create separate CloudKit record types for each entry?**  
A: That would require complex relationship management, multiple record fetches, and higher costs. JSON serialization is simpler and more efficient for child records.

**Q: What if I have 100 vaccination entries?**  
A: All 100 will be serialized to the JSON array. CloudKit STRING fields support up to 1MB of data, which can hold thousands of entries.

**Q: Is the data secure?**  
A: Yes. The data is stored in your private CloudKit container with the same encryption and access controls as other fields.

**Q: What happens if deserialization fails?**  
A: The existing local data is preserved. Errors in JSON parsing don't delete local entries.

---

**Implementation Files:**
- Serialization: `PurusHealth/Services/CloudSyncService.swift` (lines 721-792)
- Deserialization: `PurusHealth/Services/CloudKitMedicalRecordFetcher.swift` (lines 331-475)
- Codable Models: `PurusHealth/Services/CloudKitCodableModels.swift`
- Schema Definition: `cloudkit-development.cdkb` (lines 46-57)
