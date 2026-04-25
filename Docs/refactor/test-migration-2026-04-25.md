# Test Migration Log — DriftTests → DriftCoreTests

**Date:** 2026-04-25
**Goal:** Move pure-logic tests out of the iOS DriftTests target into the cross-platform DriftCore Swift package test target so they run via `swift test` (<1s warm) instead of forcing an iOS Simulator boot (~27s).

## Initial scan (heuristic, scripts/test-portability-scan.sh)

- DriftTests/*.swift total: 81
- Files importing `@testable import DriftCore`: 73
- **Portable candidates (no iOS-only refs): 55**
- Non-portable (must stay in DriftTests): 18
- No DriftCore import (untouched): 0

Heuristic blocklist:
```
HealthKitService, FoodLogViewModel, WeightViewModel, AIChatViewModel,
WorkoutViewModel, WidgetCenterRefresher, WidgetDataProvider,
NotificationService, SpeechRecognitionService, BodySpecPDFParser,
LabReportOCR, NutritionLabelOCR, PhotoLogTool, UIImage, UIView,
DriftApp, ContentView, HomeView, DashboardView,
import UIKit/SwiftUI/HealthKit/WidgetKit/AVFoundation/Speech/Photos/AppIntents
```

## Non-portable (stay in DriftTests)

| File | Reason |
|---|---|
| AITests.swift | NotificationService |
| ChatSuggestionPillsTests.swift | AIChatViewModel |
| ClarificationFlowTests.swift | AIChatViewModel |
| ConfirmationCardTests.swift | AIChatViewModel |
| ConversationStatePersistenceTests.swift | AIChatViewModel |
| CycleCalculationTests.swift | HealthKitService |
| EdgeCaseTests.swift | NutritionLabelOCR |
| FoodLoggingTests.swift | FoodLogViewModel |
| FoodServiceTests.swift | FoodLogViewModel |
| IntegrationTests.swift | FoodLogViewModel |
| LabReportOCRTests.swift | LabReportOCR |
| MealLogUnificationTests.swift | FoodLogViewModel |
| NotificationServiceTests.swift | NotificationService |
| NutritionOCRTests.swift | NutritionLabelOCR |
| PhotoLogServiceTests.swift | import UIKit |
| PhotoLogToolTests.swift | import UIKit |
| SpeechRecognitionTests.swift | SpeechRecognitionService |
| WidgetDataTests.swift | WidgetDataProvider |

## Portable list (55 files)

Pilot wave (5):
- CSVParserTests.swift
- ClarificationBuilderTests.swift
- ComposedFoodParserTests.swift
- AIResponseCleanerTests.swift
- ConversationHistoryBuilderTests.swift

Remaining 50 files batched into waves of ~10. The heuristic is a *starting point* — actual portability is decided by the compiler. Files that fail to build under `swift test` because they depend on a Drift-target symbol or an `internal`-but-only-`@testable`-via-Drift symbol are reverted to DriftTests with a note.

## Wave log

(Filled in as waves complete.)
