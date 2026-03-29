# Drift

Local-first iOS app for weight tracking, nutrition, and body composition analysis. Powered by Apple Health data.

## Core Features

- **Weight Trend Tracking** - EMA smoothing, deficit/surplus estimation, 30-day projection
- **Apple Health Integration** - Auto-imports weight, calories burned, sleep, steps
- **Food Logging** - 128 curated foods (Indian staples + common items) with macros, plus quick-add
- **Supplements** - Daily checklist for electrolytes, magnesium glycinate, creatine
- **BodySpec DEXA** - Manual entry for body composition tracking with scan comparison
- **CGM Import** - Lingo CSV glucose data with meal correlation

## Quick Start

```bash
# Requires Xcode 16+ installed
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Open in Xcode
open Drift.xcodeproj

# Or build from CLI
xcodebuild -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

See [PHONE-TESTING.md](PHONE-TESTING.md) for device deployment instructions.

## Architecture

- SwiftUI + MVVM + Swift Charts
- GRDB.swift for local SQLite persistence
- Apple HealthKit for health data
- iOS 17+ minimum target
- Zero network calls - everything runs locally

## Key Files

| File | Purpose |
|------|---------|
| `Services/WeightTrendCalculator.swift` | EMA + linear regression + deficit math |
| `Services/HealthKitService.swift` | Apple Health read/write |
| `Database/AppDatabase.swift` | GRDB setup + all data operations |
| `Resources/foods.json` | Curated food database (128 items) |
| `Views/Weight/WeightChartView.swift` | Dual-line weight trend chart |

## Docs

- [Development Guide](Docs/develop.md)
- [Testing Guide](Docs/test.md)
- [Use Cases](Docs/use-cases.md)
- [Code Review Process](Docs/code-review-and-fix.md)
