# Testing Guide

## Running Tests

**CRITICAL: Never run multiple `xcodebuild test` in parallel.** They fight for the simulator and deadlock. Always kill stale processes before starting a new test run.

**Why simulator?** Test target is `bundle.unit-test` for iOS. Tests use `@testable import Drift` which targets iOS. Can't run without simulator.

**LLM eval tests** (LLMToolCallingEval, LLMGemma4Eval, LLMQwen3Eval, LLMIntegrationTest) check for model files at `/tmp/*.gguf` and **skip gracefully** if not found. They do NOT download models. These are opt-in — run separately when model is pre-staged.

**Expected timing:** ~2-3 min for all 729+ tests (simulator already booted). If it takes longer, you probably have stale xcodebuild processes — kill them.

```bash
cd /Users/ashishsadh/workspace/Drift

# ALWAYS kill stale processes first
pkill -9 -f xcodebuild 2>/dev/null; sleep 2

# All tests (729+)
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Quick pass/fail check
xcodebuild test ... 2>&1 | grep "✘"  # empty = all pass

# AI eval harness only (212+ test methods)
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'DriftTests/AIEvalHarness'

# LLM tool-calling eval (needs model on simulator — 100 queries)
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'DriftTests/LLMToolCallingEval'

# Specific test class
xcodebuild test ... -only-testing:DriftTests/WorkoutTests
```

## Test Files (19 files, 729+ tests, 248 methods)

| File | Tests | Covers |
|------|-------|--------|
| `FoodLoggingTests.swift` | 180+ | Food search, logging, recipes, macros, TDEE |
| `AIEvalHarness.swift` | 212+ methods | Food/weight/workout intent, routing, response quality, tools, JSON parsing |
| `LLMToolCallingEval.swift` | 100 queries | Real model inference: food logging, questions, weight, exercise, sleep, no-tool |
| `LLMGemma4Eval.swift` | — | Gemma 4 comparison eval |
| `WorkoutTests.swift` | 68+ | Workouts, CSV import, recovery, templates |
| `WorkoutPersistenceTests.swift` | 40+ | Session save/load, exercise persistence |
| `UIFlowTests.swift` | 49 | DB CRUD: weight, food, supplements, DEXA, glucose |
| `WeightTrendCalculatorTests.swift` | 40 | EMA, regression, deficit, projection |
| `AITests.swift` | 30+ | Action parsing, context builders, intent detection |
| `RobustnessTests.swift` | 30+ | Stress tests, concurrent access |
| `EdgeCaseTests.swift` | 26 | Large datasets, special chars, zero values |
| `DatabaseEdgeCaseTests.swift` | 20+ | Schema edge cases, cascade deletes |
| `LabReportOCRTests.swift` | 48 | Quest + LabCorp PDF extraction |
| `CycleCalculationTests.swift` | 16 | Cycle phase, ovulation, fertile window |
| `NutritionOCRTests.swift` | 15 | OCR parsing: calories, macros, serving size |
| `CSVParserTests.swift` | 4 | CSV parsing basics |

## AI Eval Harness

The eval harness (`DriftTests/AIEvalHarness.swift`) is the gold-standard test suite for AI quality. Run it after every AI change.

### Current Coverage (212+ test methods)
- Food logging precision: 23 positive cases, 12 false positive checks
- Indian food logging: 12 cases
- Food phrasing variety: 12 cases, beverages: 9, snacks: 9
- Amount parsing: 9 cases + 7 edge cases + 3 fractions + 5 exact amounts + mid-string numbers
- Weight logging: 6 positive, 4 false positive, 5 unit detection, 3+4 edge cases
- Workout routing: 7 queries, 4 false positive checks
- Workout parsing: CREATE + START with various formats
- Chain-of-thought routing: 25 queries across all domains
- Calorie estimation: 7 routing + 4 false positive checks
- Nutrition lookup: 8 query formats
- Cross-screen routing: 6 cases
- Keyword false positive prevention: 5 broad-term cases
- Response cleaner: markdown, preambles, ChatML, Gemma artifacts, quality gate, hallucination detection
- Tool call JSON parsing: valid, malformed, edge cases
- Spell correction: Levenshtein, known corrections, food word detection
- Service tests: FoodService, WeightServiceAPI, ExerciseService, SleepRecovery
- Body composition: entry, HealthKit sync, charts
- Rule engine: 19 exact-match patterns
- Domain routing: 9 domains verified
- Token budget: truncation + all contexts under budget

### Dual-Model Eval
- **AIEvalHarness (212+ methods):** Runs without model — tests parsing, routing, tools, quality gates
- **LLMToolCallingEval (100 queries):** Loads actual model, sends prompts with tool schemas, checks JSON output
  - Categories: food logging (20), food questions (15), weight (15), exercise (23), sleep (10), no-tool (11), ambiguous (5)
  - Gemma 4 baseline: food 90%, questions 70%, exercise 50%, weight 80%

### Target: 300+ test methods
Priority areas: cross-domain queries, screen-bias regression tests, multi-turn scenarios, separate SmolLM vs Gemma 4 metrics.

## Test Patterns

```swift
// Database test (empty in-memory DB)
@Test func myTest() async throws {
    let db = try AppDatabase.empty()
    // ... test with db
}

// Pure logic test
@Test func calculationTest() async throws {
    let result = MyService.calculate(input: 42)
    #expect(result == expected)
}

// AI eval pattern (precision measurement)
func testFoodIntents() {
    let cases = ["log 2 eggs", "ate chicken", ...]
    var detected = 0
    for query in cases {
        if parseFoodIntent(query) != nil { detected += 1 }
    }
    let precision = Double(detected) / Double(cases.count)
    XCTAssertGreaterThanOrEqual(precision, 0.85)
}
```

## Simulator Testing

```bash
# Install on simulator
APP=$(find ~/Library/Developer/Xcode/DerivedData/Drift-*/Build/Products/Debug-iphonesimulator/Drift.app -maxdepth 0 | head -1)
xcrun simctl install "iPhone 17 Pro" "$APP"
xcrun simctl launch "iPhone 17 Pro" com.drift.health

# Screenshot
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/drift_screenshot.png
```
