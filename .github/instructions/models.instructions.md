---
description: 'SwiftData model guidelines for MyHealthData'
applyTo: 'MyHealthData/Models/**/*.swift'
---

# SwiftData Models

## Required Patterns

### Model Declaration
- Use `@Model` macro on all model classes
- Mark classes as `final` unless inheritance is explicitly needed
- Always include `uuid: String` field for stable identifiers
- Provide computed `id` property that returns `uuid` for Identifiable conformance

### Identity and Timestamps

**Only for MedicalRecord** (not for entry models):
```swift
var createdAt: Date = Date()
var updatedAt: Date = Date()
var uuid: String = UUID().uuidString
var id: String { uuid }
```

**For Entry Models** (BloodEntry, DrugEntry, etc.):
Entry models don't have uuid, id, createdAt, or updatedAt fields. They only have their domain-specific properties.

### Relationships
- Use `@Relationship` macro for all relationships
- Specify appropriate `deleteRule`: typically `.cascade` for owned children, `.nullify` for references
- Always provide `inverse` parameter for bidirectional relationships
- Initialize relationship arrays with empty arrays: `= []`

### Initialization
- Provide explicit `init()` methods for models
- Initialize `uuid` with `UUID().uuidString` in init
- Initialize `createdAt` and `updatedAt` with `Date()` in init
- Initialize all relationship arrays

## Example Model Structure

### Entry Model Pattern (BloodEntry, DrugEntry, etc.)

```swift
import Foundation
import SwiftData

@Model
final class ExampleEntry {
    var date: Date? = nil
    var name: String = ""
    var notes: String = ""
    
    @Relationship(deleteRule: .nullify, inverse: \MedicalRecord.exampleEntries)
    var record: MedicalRecord? = nil
    
    init(date: Date? = nil, name: String = "", notes: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.notes = notes
        self.record = record
    }
}
```

**Important**: Entry models don't have uuid, id, createdAt, or updatedAt fields. Only `MedicalRecord` has these identity fields.

## Don't

- Don't use `id` as a stored property (conflicts with SwiftData)
- Don't use force unwrapping in models
- Don't add business logic to models (put in Services)
- Don't forget to add new models to the Schema in `MyHealthDataApp.swift`
