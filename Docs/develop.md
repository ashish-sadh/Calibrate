# Calibrate - Development Guide

## Prerequisites
- macOS with Xcode 16+ installed
- Swift 6.x
- xcodegen (`brew install xcodegen`)
- Physical iPhone for HealthKit testing (Simulator has limited HealthKit support)

## Quick Start

```bash
# 1. Generate Xcode project
cd /Users/ashishsadh/workspace/Calibrate
xcodegen generate

# 2. Open in Xcode
open Calibrate.xcodeproj

# 3. Build (CLI)
xcodebuild -project Calibrate.xcodeproj -scheme Calibrate -destination 'platform=iOS Simulator,name=iPhone 16' build

# 4. Run tests
xcodebuild -project Calibrate.xcodeproj -scheme Calibrate -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Architecture

```
MVVM + Services
├── Models/          → GRDB records (structs conforming to Codable, FetchableRecord, PersistableRecord)
├── Views/           → SwiftUI views (pure UI, no business logic)
├── ViewModels/      → @Observable classes, bridge between Views and Services/Database
├── Services/        → Business logic (HealthKit, trend calculator, importers)
├── Database/        → GRDB setup, migrations, shared persistence
├── Resources/       → Bundled assets (foods.json, default_supplements.json)
└── Utilities/       → Shared helpers (date formatters, CSV parser, unit converters)
```

## Key Patterns

### Database Access
- Use `AppDatabase.shared` for production
- Use `AppDatabase.empty()` for tests (in-memory)
- Use GRDB `ValueObservation` for reactive UI updates
- All models use `Codable + FetchableRecord + PersistableRecord`

### HealthKit
- `HealthKitService` is an `actor` for thread safety
- Uses `HKAnchoredObjectQuery` for incremental weight sync
- Queries energy/sleep/steps on demand (not persisted)
- Persists sync anchors in `hk_sync_anchor` table

### Adding a New Feature
1. Write spec in `Docs/`
2. Add migration in `Database/Migrations.swift`
3. Create model in `Models/`
4. Create service in `Services/` (if needed)
5. Create ViewModel in `ViewModels/`
6. Create View in `Views/`
7. Write tests in `CalibrateTests/`
8. Update `ContentView.swift` tab structure if needed

## Dependencies
- **GRDB.swift** (v7.x) - SQLite database via SPM
- All other frameworks are Apple-native (SwiftUI, Charts, HealthKit, PDFKit)

## Building for Device

```bash
# Build for device (requires signing)
xcodebuild -project Calibrate.xcodeproj \
  -scheme Calibrate \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  build
```

See `PHONE-TESTING.md` for detailed instructions on deploying to your iPhone.
