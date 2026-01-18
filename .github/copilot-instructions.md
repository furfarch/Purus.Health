---
description: 'Copilot instructions for MyHealthData - a SwiftUI-based iOS/macOS app for managing personal medical records with SwiftData and CloudKit integration'
---

# MyHealthData - Copilot Instructions

## Project Overview

MyHealthData is a SwiftUI-based iOS/macOS application for managing personal medical records. The app uses SwiftData for local persistence and CloudKit for cloud synchronization and sharing capabilities.

## Technology Stack

- **Language**: Swift 5.9+
- **Framework**: SwiftUI
- **Data Persistence**: SwiftData with CloudKit integration
- **Testing**: Swift Testing framework (using `@Test` macro)
- **Platforms**: iOS and macOS

## Architecture

### Data Models

- Use `@Model` macro for SwiftData entities
- All models inherit cascade delete rules via `@Relationship(deleteRule: .cascade)`
- Main entity is `MedicalRecord` with relationships to various entry types (BloodEntry, DrugEntry, VaccinationEntry, etc.)
- Use `uuid` field for stable identifiers (avoid using `id` which conflicts with SwiftData synthesized id)
- Conform to `Identifiable` by providing a computed `id` property that returns `uuid`

### CloudKit Integration

- CloudKit features are opt-in per record via `isCloudEnabled` flag
- Support for sharing records with `isSharingEnabled` and `cloudShareRecordName`
- Use `CloudKitMedicalRecordFetcher` for syncing
- ModelConfiguration uses `cloudKitDatabase: .none` for local storage

### Views and UI

- Follow SwiftUI declarative patterns
- Use `@Environment(\.modelContext)` for data access
- Separate concerns: Views in `Views/`, Models in `Models/`, Services in `Services/`
- Support both human and pet records (check `isPet` flag)

## Coding Standards

### Swift Conventions

- Use Swift's standard naming conventions (camelCase for properties and methods, PascalCase for types)
- Prefer explicit type annotations for clarity in model properties
- Use descriptive property names (e.g., `personalGivenName` instead of `firstName`)
- Mark classes as `final` when inheritance is not intended

### SwiftUI Best Practices

- Use `@MainActor` when required for UI operations
- Leverage SwiftUI property wrappers appropriately (`@State`, `@Binding`, `@Environment`)
- Create preview providers using `#Preview` macro
- For previews, use in-memory model containers: `.modelContainer(for: MedicalRecord.self, inMemory: true)`

### Data Management

- Always use `ModelConfiguration` with `isStoredInMemoryOnly: false` for persistent storage
- Use cascade delete rules to maintain data integrity
- Handle ModelContainer creation errors gracefully with fallback to in-memory storage
- Save context after modifications: `try context.save()`

### Error Handling

- Use Swift's `do-catch` blocks for error-prone operations
- Provide fallback behavior when operations fail (see `MyHealthDataApp.init()` for example)
- Log errors with descriptive messages using print statements with component prefix (e.g., `[MyHealthDataApp]`)

## Testing Guidelines

### Test Framework

- Use Swift Testing framework with `@Test` macro (not XCTest)
- Import the module under test with `@testable import MyHealthData`
- Use `#expect()` assertions instead of XCTAssert
- Mark async tests with `async throws`
- Use `@MainActor` for tests that interact with SwiftData contexts

### Test Structure

- Group related tests in structs
- Use descriptive test names that explain what is being tested
- Clean up test data after tests complete (delete created records)
- For persistence tests, create separate ModelContainer instances to verify data is truly persisted

### Testing Conventions

- Test model properties and computed values
- Test data persistence across container instances
- Verify cascade delete behavior
- Test edge cases (empty strings, nil values, etc.)
- Avoid using predicate APIs/macros in tests; fetch all and filter in-memory for compatibility
- **Example test patterns:**
  ```swift
  // Testing persistence
  @Test @MainActor func testPersistence() async throws {
      let schema = Schema([MedicalRecord.self])
      let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      // Test your persistence logic
  }
  
  // Testing computed properties
  @Test func testDisplayName() async throws {
      let record = MedicalRecord()
      record.personalGivenName = "John"
      #expect(record.displayName == "John")
  }
  ```

## File Organization

```
MyHealthData/
├── Models/           # SwiftData model definitions
├── Views/            # SwiftUI views
│   └── RecordEditor/ # Sub-views for editing
│   └── RecordViewer/ # Sub-views for viewing
├── Services/         # Business logic and services
└── Assets.xcassets   # Asset catalog
```

## Building and Testing

### Building

- This is an Xcode project (`.xcodeproj`)
- Build using Xcode IDE or command-line tools
- Supports both iOS and macOS targets
- **Command-line build examples:**
  ```bash
  # Build for iOS
  xcodebuild -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=iOS Simulator,name=iPhone 15' build
  
  # Build for macOS
  xcodebuild -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=macOS' build
  ```

### Running Tests

- Tests are located in `MyHealthDataTests/`
- Use Swift Testing framework (not XCTest)
- Run tests through Xcode Test Navigator or command-line
- **Command-line test examples:**
  ```bash
  # Run all tests on iOS Simulator
  xcodebuild test -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=iOS Simulator,name=iPhone 15'
  
  # Run all tests on macOS
  xcodebuild test -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=macOS'
  ```

## Cloud and Sharing Features

- CloudKit container identifier: `iCloud.com.furfarch.MyHealthData`
- Sharing is per-record, not app-wide
- Use `CloudSyncService` for cloud operations
- Track record location status: `.local`, `.iCloud`, or `.shared`

## Important Notes

- Support both human and pet medical records (check `isPet` field)
- Display names differ for humans vs pets (use `displayName` computed property)
- Legacy emergency contact fields exist for backward compatibility
- New emergency contacts use the `EmergencyContact` relationship
- Always use persistent storage unless specifically testing in-memory scenarios

## Security and Privacy

- **NEVER** commit sensitive medical data, API keys, or credentials to the repository
- Use iOS/macOS Keychain for storing sensitive user credentials if needed
- Respect user privacy - medical data is sensitive and must be handled with care
- CloudKit data should be properly secured and access controlled
- Test with mock/synthetic data, never use real patient information
- Follow HIPAA-like privacy principles even though this is a personal app

## Common Code Patterns

### Creating a New Entry Model

Entry models (BloodEntry, DrugEntry, etc.) follow a simple pattern without uuid/id fields:

```swift
@Model
final class NewEntry {
    var date: Date? = nil
    var name: String = ""
    var notes: String = ""
    
    @Relationship(deleteRule: .nullify, inverse: \MedicalRecord.newEntries)
    var record: MedicalRecord? = nil
    
    init(date: Date? = nil, name: String = "", notes: String = "", record: MedicalRecord? = nil) {
        self.date = date
        self.name = name
        self.notes = notes
        self.record = record
    }
}
```

**Note**: Only `MedicalRecord` has uuid, id, createdAt, and updatedAt fields. Entry models don't need these.

### Creating a SwiftUI View with ModelContext

```swift
struct MyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [MedicalRecord]
    
    var body: some View {
        // Your view code
    }
}
```

### Saving Changes to ModelContext

```swift
// After modifying model objects
do {
    try modelContext.save()
} catch {
    print("[ComponentName] Error saving: \(error)")
}
```

### Preview Provider Pattern

```swift
#Preview {
    MyView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
```
