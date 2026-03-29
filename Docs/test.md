# Calibrate - Testing Guide

## Test Strategy

### Unit Tests (automated, run in CI/locally)
Run via: `xcodebuild test -project Calibrate.xcodeproj -scheme Calibrate -destination 'platform=iOS Simulator,name=iPhone 16'`

| Component | What to Test | Location |
|-----------|-------------|----------|
| WeightTrendCalculator | EMA calculation, linear regression, deficit estimate, edge cases | `CalibrateTests/WeightTrendCalculatorTests.swift` |
| FoodDatabase | JSON loading, search results, serving math | `CalibrateTests/FoodDatabaseTests.swift` |
| CGMImportService | CSV parsing, duplicate detection, malformed rows | `CalibrateTests/CGMImportServiceTests.swift` |
| Models | GRDB record round-trips (insert, fetch, update, delete) | `CalibrateTests/ModelTests.swift` |
| Migrations | All migrations run cleanly on empty DB | `CalibrateTests/MigrationTests.swift` |

### On-Device Tests (manual, requires iPhone)

#### HealthKit Integration
1. Build and install on iPhone
2. Grant all HealthKit permissions when prompted
3. Verify: historical weight data appears in Weight tab
4. Verify: calories burned (active + basal) shows on Dashboard
5. Verify: sleep data shows on Dashboard
6. Verify: step count shows on Dashboard
7. Log food → verify it appears in Apple Health under Nutrition

#### Weight Trend
1. Ensure 7+ days of weight data exists (from HealthKit or manual entry)
2. Open Weight tab → verify dual-line chart (scale + trend)
3. Verify weight changes table (3d/7d/14d/30d/90d)
4. Verify energy deficit estimate matches expected (negative = losing)
5. Verify 30-day projection is reasonable
6. Try different time ranges (1W, 1M, 3M, 6M, 1Y, All)

#### Food Logging
1. Search "daal" → verify results appear
2. Log daal with 2 servings → verify calories doubled
3. Quick-add a custom food → verify it appears in daily log
4. Check Dashboard → verify calorie total updates
5. Check deficit = consumed - burned is displayed

#### Supplements
1. Verify 3 default supplements appear (electrolytes, mag glycinate, creatine)
2. Toggle "taken" → verify checkmark + timestamp
3. Add custom supplement → verify it appears in list
4. Check Dashboard → verify "2/3 taken" status

#### BodySpec DEXA
1. Upload a BodySpec PDF via document picker
2. Verify body composition data extracted correctly
3. Upload a second scan → verify comparison/deltas shown
4. Check trend charts for body fat %, lean mass, fat mass

#### CGM Import
1. Upload a Lingo CSV file
2. Verify glucose chart displays with correct time range
3. Log a meal → verify meal marker appears on glucose chart
4. Check glucose response metrics (pre-meal, peak, rise)

## Test Data

### Sample Weight Data (for unit tests)
```json
[
  {"date": "2026-03-01", "weight_kg": 55.0},
  {"date": "2026-03-02", "weight_kg": 54.8},
  {"date": "2026-03-03", "weight_kg": 55.2},
  {"date": "2026-03-05", "weight_kg": 54.6},
  {"date": "2026-03-06", "weight_kg": 54.5},
  {"date": "2026-03-07", "weight_kg": 54.3},
  {"date": "2026-03-08", "weight_kg": 54.7}
]
```

### Sample Lingo CSV (for unit tests)
```csv
timestamp,glucose_mg_dl
2026-03-15 08:00:00,95
2026-03-15 08:05:00,97
2026-03-15 08:10:00,102
2026-03-15 08:15:00,110
2026-03-15 08:20:00,118
2026-03-15 08:25:00,125
2026-03-15 08:30:00,130
2026-03-15 08:35:00,128
2026-03-15 08:40:00,122
2026-03-15 08:45:00,115
```

## Running Tests

```bash
# All tests
xcodebuild test -project Calibrate.xcodeproj -scheme Calibrate \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Specific test class
xcodebuild test -project Calibrate.xcodeproj -scheme Calibrate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:CalibrateTests/WeightTrendCalculatorTests

# With verbose output
xcodebuild test -project Calibrate.xcodeproj -scheme Calibrate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -resultBundlePath TestResults.xcresult
```
