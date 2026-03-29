# Drift - Testing Process

## Overview

Drift has 202 automated tests across 6 test files covering all features.
Tests run locally via `xcodebuild test` on iOS Simulator.

## Running Tests

```bash
cd ~/workspace/Drift

# Run all tests
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Quick check (just pass/fail)
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "✘"
# Empty output = all pass

# Count tests
grep -c "@Test func" DriftTests/*.swift | awk -F: '{sum += $2} END {print sum}'
```

## Test Files

| File | Tests | Covers |
|------|-------|--------|
| `WeightTrendCalculatorTests.swift` | 40 | EMA, regression, deficit, projection, weight changes, config |
| `UIFlowTests.swift` | 49 | DB CRUD: weight, food, supplements, DEXA, glucose, goals, CSV |
| `NutritionOCRTests.swift` | 15 | OCR parsing: calories, macros, serving size, edge cases |
| `WorkoutTests.swift` | 68 | Workouts, Strong CSV import, recovery estimator, favorites, barcode, servings, goals |
| `EdgeCaseTests.swift` | 26 | Edge cases: large datasets, special chars, zero values, cascade deletes |
| `CSVParserTests.swift` | 4 | CSV parsing basics |

## Simulation Testing (Manual)

For visual UI verification, use the iOS Simulator:

### Setup
```bash
# Build for simulator
xcodebuild -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Install on simulator
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Drift-*/Build/Products/Debug-iphonesimulator/Drift.app -maxdepth 0 | head -1)
xcrun simctl install "iPhone 17 Pro" "$APP_PATH"

# Launch
xcrun simctl launch "iPhone 17 Pro" com.drift.health
```

### Seed Test Data
```bash
# Get database path
CONTAINER=$(xcrun simctl get_app_container "iPhone 17 Pro" com.drift.health data)
DB="$CONTAINER/Library/Application Support/Drift/drift.sqlite"

# Kill app first
xcrun simctl terminate "iPhone 17 Pro" com.drift.health

# Insert data
sqlite3 "$DB" << 'SQL'
INSERT OR REPLACE INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk) VALUES
('2026-03-20', 54.3, 'healthkit', datetime('now'), 1),
('2026-03-25', 53.9, 'healthkit', datetime('now'), 1),
('2026-03-28', 53.8, 'healthkit', datetime('now'), 1);
-- Add more as needed
SQL

# Relaunch
xcrun simctl launch "iPhone 17 Pro" com.drift.health
```

### Take Screenshots
```bash
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/drift_screenshot.png
```

### UI Test Checklist

#### Dashboard
- [ ] Drift logo + title in toolbar
- [ ] Estimated deficit/surplus headline shows
- [ ] Weight + Trend cards show correct values
- [ ] Energy balance shows when food logged, muted when not
- [ ] Tap Weight card → Weight tab
- [ ] Tap Energy card → Food tab
- [ ] Recovery card shows if sleep data exists
- [ ] Supplements card shows if supplements exist

#### Weight Tab
- [ ] Time range selector (1W/1M/3M/6M/1Y/All) works
- [ ] Chart shows gray dots (scale) + purple line (trend)
- [ ] Reference lines: dashed start, solid current with labels
- [ ] Insights always show full data regardless of time range
- [ ] Weight changes match actual scale weight direction
- [ ] Monthly grouped log with day-over-day changes
- [ ] Add weight manually works
- [ ] Delete weight works

#### Food Tab
- [ ] Date navigation (← Today →) works
- [ ] Shows correct meals for selected date
- [ ] Search finds foods from 128-item database
- [ ] Barcode scanner opens camera
- [ ] Quick Add → Favorites tab works
- [ ] Quick Add → New (recipe builder) works
- [ ] Delete food entry works
- [ ] Consistency heatmap shows 30 days

#### Exercise Tab
- [ ] Import Strong CSV works
- [ ] Start workout → timer runs continuously
- [ ] Add exercise → prefills last weight/reps
- [ ] Mark set done → rest timer starts (90s)
- [ ] Rest timer vibrates when done
- [ ] Muscle group labels on exercises
- [ ] Finish → saves workout
- [ ] History shows all workouts
- [ ] Detail view shows all sets with 1RM
- [ ] Share button generates text summary
- [ ] Save as template works

#### More Tab
- [ ] Weight Goal setting and display
- [ ] Sleep & Recovery shows scores
- [ ] Supplements checklist with consistency graph
- [ ] Body Composition shows DEXA data
- [ ] Glucose shows chart with zones
- [ ] Settings: unit toggle, Health sync
- [ ] Algorithm tuning works
- [ ] Factory Reset works
- [ ] Privacy note visible

## Autonomous Improvement Loop

When working on UI improvements without human review:

1. **Build**: `xcodebuild build` must succeed
2. **Test**: All 202+ tests must pass
3. **Simulator check**: Install, seed data, take screenshot, visually verify
4. **Commit**: Only if build + test + visual check pass
5. **Document**: Note what changed and what was verified

### Screenshot Verification Script
```bash
#!/bin/bash
# verify.sh - Build, test, install, screenshot
cd ~/workspace/Drift

echo "Building..."
xcodebuild -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -1

echo "Testing..."
FAILURES=$(xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "✘" | wc -l)
echo "Failures: $FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "Installing on simulator..."
  APP=$(find ~/Library/Developer/Xcode/DerivedData/Drift-*/Build/Products/Debug-iphonesimulator/Drift.app -maxdepth 0 | head -1)
  xcrun simctl install "iPhone 17 Pro" "$APP"
  xcrun simctl terminate "iPhone 17 Pro" com.drift.health 2>/dev/null
  xcrun simctl launch "iPhone 17 Pro" com.drift.health
  sleep 4
  xcrun simctl io "iPhone 17 Pro" screenshot /tmp/drift_verify.png
  echo "Screenshot: /tmp/drift_verify.png"
fi
```

## Adding New Tests

When adding a new feature:
1. Write the feature code
2. Add tests in the appropriate test file (or create new one)
3. Run full test suite
4. Verify no regressions

### Test naming convention
- `@Test func featureActionExpectation()` e.g., `weightChangesDecreasingCorrectly`
- Group by `// MARK: - Category (N tests)`

### Test patterns
```swift
// Database test (use empty in-memory DB)
@Test func myTest() async throws {
    let db = try AppDatabase.empty()
    // ... test with db
}

// Pure logic test
@Test func calculationTest() async throws {
    let result = MyService.calculate(input: 42)
    #expect(result == expected)
}

// Model test
@Test func modelPropertyTest() async throws {
    let m = MyModel(value: 10)
    #expect(m.computed == 20)
}
```
