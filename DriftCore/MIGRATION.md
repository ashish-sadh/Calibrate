# DriftCore migration plan

Goal: extract a multi-platform `DriftCore` Swift Package so the heavy regression and LLM-eval tests run on macOS without the iOS Simulator. The Drift iOS app keeps everything platform-bound (UIKit, SwiftUI, HealthKit live integration).

## Status — 2026-04-25

| | |
|---|---|
| iOS build | ✅ green (`xcodebuild -scheme Drift`) |
| macOS DriftCore build | ✅ green (`cd DriftCore && swift build`) |
| Models in Core | 13 of 20 |
| Utilities in Core | 3 of 7 (DateFormatters, Log, MacroFormatters) |
| Database in Core | 0 of 5 — rolled back; needs Models split first |
| Services in Core | 0 of 72 |
| Tests on Core | 0 — `Tests/DriftCoreTests/` exists but empty |

## Why this is harder than the audit suggested

The initial audit classified files by *imports* (no UIKit / SwiftUI / HealthKit = bucket A, safe to move). That bucketing ignored *type-reference coupling*. In practice:

- `Drift/Models/Food.swift` declares an extension method that returns `QuickAddView` (a SwiftUI type). The Models file imports nothing from SwiftUI directly, but it references `QuickAddView` in its body. When you move `Food.swift` out of the iOS module, that reference fails.
- `Drift/Database/AppDatabase.swift` references `Food`, `SavedFood`, `BarcodeCache`, `PlantPointsService`, `BodySpecPDFParser` — types that are still in Drift. Database can't move until they do.
- `BarcodeCache.swift` references `OpenFoodFactsService` (a Service, still in Drift). It can't move with the other Models.

So the dependency graph is denser than imports-alone showed. The right unit of work isn't "move file X" but "split file X so the data half can move and the platform half stays."

## Path forward — file-splitting strategy

For each entangled file, split into two:

- **`{Type}.swift`** in `DriftCore/Sources/DriftCore/Models/` (or `Services/`). Pure data, no UI.
- **`{Type}+iOSSupport.swift`** in `Drift/`. An extension that adds the platform-bound bits (SwiftUI helpers, HealthKit converters, UIImage adapters).

Example for `Food.swift`:

```swift
// DriftCore/Sources/DriftCore/Models/Food.swift
public struct Food: ... {
    // properties, GRDB conformance, parsing
}

// Drift/Models/Food+QuickAdd.swift   (stays in iOS app)
import SwiftUI
import DriftCore

extension Food {
    var quickAddView: QuickAddView { QuickAddView(food: self) }
}
```

This is mechanical work but bounded.

## Remaining phases

Each phase commits independently. Each verified by both `cd DriftCore && swift build` AND `xcodebuild -scheme Drift build`.

### Phase 1c — finish Models + Database (2 hr)

1. Split `Food.swift` → `DriftCore/Models/Food.swift` + `Drift/Models/Food+QuickAdd.swift`.
2. Split `BarcodeCache.swift` → core data part + iOS extension that calls `OpenFoodFactsService`.
3. Split `PhotoLogEntry.swift` similarly (CloudVision types stay in Drift via extension).
4. Move `SavedFood`, `ServingUnit`, `Workout` (now unblocked).
5. Move all 5 Database files (now unblocked).
6. Verify both builds.

### Phase 1d — Services bucket-A (~63 files, 2 hr)

Move in waves of 10–15. After each wave: build, fix what breaks, commit. Order matters — start with leaf services that don't depend on others (e.g., `InputNormalizer`, `IntentClassifier`, `SpellCorrectService`, `PronounResolver`). Then mid-tier (`ToolRanker`, `AIActionParser`, `ConversationState`). Finish with high-fanout (`ToolRegistration`, `AIToolAgent`).

### Phase 2 — Protocol-extract bucket-B (8 files, 1 hr)

Each of these gets a Core protocol + iOS adapter:

| File | Core protocol | iOS adapter |
|---|---|---|
| `HealthKitService.swift` | `HealthDataProvider` | `HKHealthStore`-backed impl |
| `HealthKitService+Cycle.swift` | (extends above) | (extends above) |
| `HealthKitService+Sleep.swift` | (extends above) | (extends above) |
| `WidgetDataProvider.swift` | `WidgetRefresher` | `WidgetCenter.shared.reloadAllTimelines()` |
| `NotificationService.swift` | `LocalNotifier` | `UNUserNotificationCenter`-backed impl |
| `SpeechRecognitionService.swift` | `SpeechRecognizer` | iOS Speech-framework impl |
| `BodySpecPDFParser.swift` | core PDF logic moves; iOS UI part stays | — |
| `CloudVision/CloudVisionKey.swift` | `KeychainStorage` | iOS Keychain-backed impl |

Resolves the 5 cross-bucket edges identified in the audit:
- `ToolRegistration` → `PhotoLogTool` (use `#if os(iOS)` conditional registration)
- `FoodService` → `WidgetDataProvider` (call via injected `WidgetRefresher?`)
- `StaticOverrides` → `WidgetDataProvider` (same)
- `AIDataCache` / `CycleCalculations` → `HealthKitService` (call via injected `HealthDataProvider?`)

### Phase 3 — wire test targets to DriftCore (30 min)

In `project.yml`:

- `DriftRegressionTests` and `DriftLLMEvalTests` add `package: DriftCore` dependency.
- Test files change `@testable import Drift` → `@testable import DriftCore` for the moved code (or keep both if the test exercises both layers).

### Phase 4 — macOS test targets (30 min)

Add to `project.yml`:

```yaml
DriftRegressionTestsMacOS:
  type: bundle.unit-test
  platform: macOS
  deploymentTarget: "14.0"
  sources:
    - path: DriftRegressionTests
  dependencies:
    - package: DriftCore
    - framework: Frameworks/llama.xcframework

DriftLLMEvalTestsMacOS:
  type: bundle.unit-test
  platform: macOS
  deploymentTarget: "14.0"
  sources:
    - path: DriftTests/LLMEval
  dependencies:
    - package: DriftCore
    - framework: Frameworks/llama.xcframework
```

Plus matching schemes. Now:

```bash
xcodebuild test -scheme DriftRegressionTestsMacOS \
  -destination 'platform=macOS'    # ~30s, no simulator
```

## Acceptance criteria

- `cd DriftCore && swift test` passes the migrated regression suite on macOS.
- `xcodebuild test -scheme Drift -destination 'iOS Simulator'` still passes the iOS unit tests.
- `xcodebuild test -scheme DriftRegressionTestsMacOS -destination 'macOS'` runs the regression gate in under 1 minute.
- No file in DriftCore imports `UIKit`, `SwiftUI`, `HealthKit`, `WidgetKit`, `AVFoundation`, `Speech`, `Photos`, or `AppIntents`.

## Total estimated effort

~6 hours across the four phases. Done in one focused day or four ~90-min sessions.

## What's done already (commit `27e21f1`)

- DriftCore SPM package scaffolded.
- 13 Models, 3 Utilities migrated.
- 100+ Drift files updated with `import DriftCore`.
- `DriftLLMEvalMacOS` switched to depend on the package.
- DEXARegion and DailyNutrition got explicit `public init`s.

This is a real foundation. The next agent (or future-me) picks up at Phase 1c with a clear file-splitting strategy, not a copy-everything-and-hope strategy.
