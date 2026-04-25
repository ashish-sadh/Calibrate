# DriftCore migration plan

Goal: extract a multi-platform `DriftCore` Swift Package so the heavy regression and LLM-eval tests run on macOS without the iOS Simulator. The Drift iOS app keeps everything platform-bound (UIKit, SwiftUI, HealthKit live integration).

## Status — 2026-04-25 (after Plan A iter 1 — LLM eval on macOS)

**Both prizes delivered.** macOS now runs:

| Suite | macOS time | iOS Simulator (prior) | Speedup |
|---|---|---|---|
| `cd DriftCore && swift test` (26 gold-set tests) | **0.012s** warm / 4.3s cold | ~8 min | **~700x** warm |
| `xcodebuild test -scheme DriftLLMEvalMacOS` (57 IntentRoutingEval tests, real Gemma 4 inference) | **5m 15s** wall | ~30 min | **~6x** |
| `xcodebuild test -scheme DriftLLMEvalMacOS -only-testing:NormalizerEval` (22 deterministic) | **6s** wall | ~5 min | **~50x** |

The LLM eval on macOS uses native Apple Silicon llama.cpp from `Frameworks/llama.xcframework/macos-arm64/`. The 57-test routing eval surfaced 26 real LLM regressions, separable from infrastructure noise.

### Scope completed in Plan A iter 1
- Moved `ToolRanker` (rank, quickExtractPrompt, tryRulePick, extractParamsForTool, buildPrompt) to Core. Pure logic, only depended on already-Core types.
- Added `PromptUtils.truncateToFit` / `estimateTokens` (Core).
- **Dedup #1:** Screen→service mapping was duplicated 3x across `ToolRegistry.toolsForScreen`, `ToolRanker.screenDefaults`, and (in iOS) `AIChainOfThought.execute`. Consolidated onto `AIScreen.serviceName` + `AIScreen.defaultTools` extensions.
- **Dedup #2:** Food-verb prefix stripping was duplicated between `parseFoodIntent` and `parseMultiFoodIntent` (3 identical constant lists + same strip sequence). Extracted `stripFoodLead(_:)` private helper.
- Fixed `Frameworks/llama.xcframework/macos-arm64/llama.framework/llama` install_name (was hard-coded to `/tmp/llama-src/...`) and re-codesigned ad-hoc; iOS slice unaffected.
- Bulk-added `import DriftCore` to 18 `DriftLLMEvalMacOS/` test files.

### What's still iOS-only (and not blocking the AI iteration loop)
- **4 gold-set tests** that need `StaticOverrides` + full `ToolRegistration`: `testExerciseIntents`, `testNavigationIntents`, `testVoiceExerciseLogging`, `testGoldSetSummary`. Worth doing only if you actually iterate on StaticOverrides/exercise routing.
- ~25 service files (Food/Workout/Exercise/Supplement/Glucose/Biomarker/DEXA/Weight/TDEE/AIDataCache/ConversationState/AppDatabase + Database/) — moving them to Core is architectural cleanup, not a user-visible win since macOS test runs already work.
- Real protocol shims for `HealthDataProvider` + `WidgetRefresher` only become necessary if/when the above services move (and only those services touch HealthKit/Widget directly).
- **Dedup #3** (domain-keyword classification across `AIChainOfThought.plan` / `ToolRanker.profiles` / `StaticOverrides`) — call sites have different concerns (broad context fetch vs scored ranking vs pattern match); unifying would lose information. Skipping.

## Status — 2026-04-25 (after Plan B — gold-set on macOS)

**Plan B delivered:** 24 of 26 gold-set tests now run on macOS in **0.019s** (24/26 ≈ 92%; remaining 2 need StaticOverrides + ToolRanker + ToolRegistration).

| | |
|---|---|
| `cd DriftCore && swift test` cold | **13.8s** (was 8min on simulator — ~35x speedup) |
| `cd DriftCore && swift test` warm | **0.7s** (~700x speedup) |
| Tests passing | **24 / 24 macOS-runnable subset** |
| iOS DriftRegressionTests | unchanged — still runs the full 26-test suite |
| iOS app build | ✅ green |

### What now lives in DriftCore (Plan B)
| Service | Notes |
|---|---|
| `InputNormalizer` | pure Foundation |
| `AIScreen` | enum |
| `AIActionParser` | regex / JSON parsing |
| `AIActionExecutor` | parsing methods (parseFoodIntent / parseMultiFoodIntent / parseWeightIntent / extractAmount); iOS-side `findFood`/`findFoodWithAI` extension stays in Drift |
| `IntentClassifier` | nonisolated parts (parseResponse, mapResponse, buildUserMessage, composeUserMessage, needsRecentEntries, systemPrompt, withTimeout); iOS-side `buildContextualUserMessage`/`classifyFull` extension stays in Drift |
| `ToolSchema`, `ToolRegistry`, `ToolCall`, `parseToolCallJSON` | type defs + registry; `execute()` lives in Drift via extension (touches `ConversationState`) |
| `WeightUnit` | enum (moved from Drift/Utilities/Units.swift) |

### Plan A — what's still ahead
The remaining tests (testExerciseIntents, testNavigationIntents, testHealthIntents, testNormalizerImprovesToolRanking, testVoiceExerciseLogging, testGoldSetSummary) need StaticOverrides + ToolRegistration + ToolRanker on macOS. That requires a `PlatformBackend` protocol layer to inject AppDatabase / HealthKitService / WidgetDataProvider / WeightTrendService into the AI pipeline — invasive but follows the same split-Core/iOS pattern. Plan A delivers the LLM eval on macOS too (llama.cpp runs natively on Apple Silicon).

## Status — 2026-04-25 (after Phase 1c)

| | |
|---|---|
| iOS build | ✅ green (`xcodebuild -scheme Drift`) |
| macOS DriftCore build | ✅ green (`cd DriftCore && swift build`) |
| Models in Core | **19 of 20** (only WeightGoal remains in Drift, blocked on TDEEEstimator + WeightTrendCalculator) |
| Utilities in Core | 3 of 7 (DateFormatters, Log, MacroFormatters) |
| Database in Core | 0 of 5 — needs PlantPointsService + BodySpecPDFParser + QuickAddView.RecipeItem split first |
| Services in Core | 0 of 72 |
| Tests on Core | 0 — `Tests/DriftCoreTests/` exists but empty |

## File splits done (Phase 1c)

| Original | DriftCore (data) | Drift (iOS extension) |
|---|---|---|
| `Drift/Models/Food.swift` | `DriftCore/.../Food.swift` (struct, GRDB) | `Drift/Models/Food+RecipeAccessors.swift` (uses `QuickAddView.RecipeItem`) |
| `Drift/Models/BarcodeCache.swift` | `DriftCore/.../BarcodeCache.swift` (struct, GRDB, displayName) | `Drift/Models/BarcodeCache+OFF.swift` (`init(from product: OpenFoodFactsService.Product)`) |
| `Drift/Models/PhotoLogEntry.swift` | `DriftCore/.../PhotoLogServingUnit.swift` (just the enum) | rest of `Drift/Models/PhotoLogEntry.swift` stays (PhotoLogEditableItem, PhotoLogViewState, PhotoLogTotals — depend on CloudVision) |
| `Drift/Models/Workout.swift` | `DriftCore/.../Workout.swift` (Exercise, Workout, WorkoutSet, WorkoutTemplate, TemplateExercise, WorkoutSummary — all data + GRDB) | `Drift/Models/Workout+Display.swift` (`WorkoutSet.display` references `Preferences.weightUnit`) |

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
