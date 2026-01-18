# MyHealthData

A SwiftUI-based iOS and macOS application for managing personal medical records with CloudKit synchronization and sharing capabilities.

## Features

- 📱 **Universal App**: Native support for both iOS and macOS
- 💾 **Local Storage**: SwiftData for robust local persistence
- ☁️ **Cloud Sync**: Optional CloudKit integration per record
- 🤝 **Sharing**: Share medical records with others via CloudKit
- 🐕 **Pet Support**: Manage both human and pet medical records
- 📊 **Multiple Entry Types**: Blood entries, medications, vaccinations, allergies, illnesses, medical history, and more
- 📄 **Export**: Export records to PDF or HTML formats
- 🔒 **Privacy-Focused**: All data stored locally by default, cloud features are opt-in

## Technology Stack

- **Language**: Swift 5.9+
- **Framework**: SwiftUI
- **Data Persistence**: SwiftData with CloudKit integration
- **Testing**: Swift Testing framework
- **Platforms**: iOS 17.0+, macOS 14.0+

## Project Structure

```
MyHealthData/
├── Models/              # SwiftData model definitions
├── Views/               # SwiftUI views
│   ├── RecordEditor/    # Sub-views for editing records
│   └── RecordViewer/    # Sub-views for viewing records
├── Services/            # Business logic and services
└── Assets.xcassets      # Asset catalog
```

## Building and Running

### Requirements

- Xcode 15.0 or later
- iOS 17.0+ or macOS 14.0+
- Swift 5.9+

### Building

1. Open `MyHealthData.xcodeproj` in Xcode
2. Select your target platform (iOS or macOS)
3. Build and run (⌘R)

### Command Line

```bash
# Build for iOS
xcodebuild -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for macOS
xcodebuild -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=macOS' build
```

## Testing

Tests are written using the Swift Testing framework (not XCTest).

```bash
# Run tests on iOS Simulator
xcodebuild test -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=iOS Simulator,name=iPhone 15'

# Run tests on macOS
xcodebuild test -project MyHealthData.xcodeproj -scheme MyHealthData -destination 'platform=macOS'
```

## GitHub Copilot Instructions

This repository includes comprehensive GitHub Copilot instructions to help with code generation and maintenance:

- **`.github/copilot-instructions.md`**: Main repository-wide instructions
- **`.github/instructions/`**: Path-specific instructions for different code areas
  - `models.instructions.md`: SwiftData model guidelines
  - `views.instructions.md`: SwiftUI view patterns
  - `services.instructions.md`: Service layer best practices
  - `tests.instructions.md`: Testing conventions

These instructions help Copilot understand the project's conventions, patterns, and best practices.

## Contributing

When contributing to this project, please follow the coding standards and patterns documented in the Copilot instructions:

- Use Swift's standard naming conventions
- Follow SwiftUI best practices
- Write tests using Swift Testing framework
- Ensure models follow the SwiftData patterns
- Handle errors gracefully
- Respect privacy and security guidelines

## Privacy and Security

MyHealthData is designed with privacy in mind:

- All data is stored locally by default
- CloudKit features are opt-in per record
- No tracking or analytics
- Medical data is sensitive - never commit real patient information to the repository
- Use mock/synthetic data for testing

## License

[Add your license information here]

## Contact

[Add contact information here]
