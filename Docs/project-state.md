# Drift - Project State (as of March 29, 2026)

## Overview
Drift is a local-first iOS health & fitness tracking app. Everything runs on-device via Apple Health + local SQLite. No cloud, no accounts. Published on TestFlight as "Drift Fitness" (bundle: com.drift.health).

## Tech Stack
- SwiftUI + MVVM, iOS 17+, Swift 6
- GRDB.swift for SQLite (only external dependency)
- Swift Charts, HealthKit, PDFKit, Vision (OCR), AVFoundation (barcode)
- xcodegen for project generation

## Apple Developer
- Team ID: ZJ5H5XH82A
- API Key: 623N7AD6BJ, Issuer: ad762446-bede-4bcd-9776-a3613c669447
- Key file: /Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_623N7AD6BJ.p8
- App ID: 6761328187
- TestFlight groups: Drift Myself (internal), Drift Beta Users (internal), Public Testers (external)
- External group ID: c398b5ff-da6b-4a1b-a66d-eeaca1dfd386
- Public link: https://testflight.apple.com/join/NDxkRwRq
- Daily upload limit: ~25 builds/day (hit on Mar 29, resets ~24hr)

## Current Build
- Version 0.1.0, build 54 (live on TestFlight)
- 626 tests, all passing
- 795 foods, 960 exercises

## Tab Structure
Drift | Weight | Food | Exercise | More

## Features Built

### Dashboard (Drift tab)
- Purple D logo + "Drift" toolbar title
- Estimated Deficit/Surplus headline (goal-aware colors)
- Weight + Trend card (clickable → Weight tab)
- Goal progress bar (clickable → Goal page)
- Energy Balance + inline macros (clickable → Food tab, muted when no food logged)
- Active cal + Steps (clickable → Exercise tab)
- Sleep + Recovery % + HRV + RHR (clickable → Sleep & Recovery)
- Supplements taken count (clickable → Supplements)

### Weight Tab
- Time range: 1W/1M/3M/6M/1Y/All with D/W granularity
- Chart: gray dots (scale) + purple trend line + reference lines
- Averages: This Week (highlighted), Last Week, Monthly
- Insights (always from ALL data, not filtered by range):
  - Weight Changes: 3d/7d/14d/30d/90d (uses actual scale weight, not EMA)
  - Current Weight, Weekly Change, Energy Deficit, 30-Day Projection
- Monthly grouped log with day-over-day changes
- Manual weight entry + HealthKit sync
- Goal-aware colors (green = aligned with goal direction)

### Food Tab
- Date navigation: ← Today → with calendar picker (tap date)
- "Today" button when viewing past dates
- Flat chronological food diary (no breakfast/lunch/dinner/snack sections)
- Auto meal type assignment based on time of day (internal only)
- Smart search: 289 foods ranked by usage frequency, then prefix match, then alphabetical
- Usage tracking: foods you log frequently appear first in search, recent foods shown as suggestions
- Saved recipes: appear in search suggestions under "YOUR RECIPES"
- Smart serving units: food-appropriate units (egg count, tbsp for oil, ml for milk, cups for rice) - no "Unit" label
- Barcode scanner: camera → Open Food Facts API → cache locally
- OCR: photo nutrition label → Vision OCR → editable fields
- Recipe builder: add ingredients with per-item serving picker, save + log or just log
- Manual entry: enter calories/macros directly from search view
- "Copy yesterday's food" when today's diary is empty
- "Log Again" context menu on diary entries
- Quick-log from recent foods (+ button)
- 30-day logging consistency heatmap
- Delete entries on any date (x button or context menu)

### Exercise Tab
- Active calories + Steps from HealthKit at top
- Body Recovery Map: 6 muscle groups color-coded (green/orange/red/gray)
  - Clickable → exercise suggestions + recovery countdown
- Workouts per week consistency chart (12 weeks)
- Start Workout: live timer, inline rest timer (Strong-style blue bar),
  customizable rest per exercise (30s-3min), "Previous" column with last weights,
  checkmark per set → auto-starts rest → vibrates when done
- 873 exercise database (free-exercise-db, public domain)
  - Search + body part filter chips + equipment + muscle info
  - Custom exercises: persist to UserDefaults, searchable everywhere
- Templates: create, delete, start from template (prefills weights)
- Import from Strong CSV (tested with 1589 sets, 57 workouts, 52 exercises)
- Workout detail: all sets with estimated 1RM (Brzycki), share button
- Save workout as template

### More Tab
- Weight Goal: target weight + months, pace (required vs actual), daily deficit target vs actual, projection
- Sleep & Recovery: WHOOP-style score rings (Sleep/Recovery/Strain),
  sleep stages (REM/Deep/Light/Awake), hours vs needed, HRV/RHR/respiratory rate,
  30-day sleep trend, recovery insight text
  - Sleep fix: ignores inBed when detailed stages exist (no double-counting)
- Supplements: 18 popular + custom, daily checklist, consistency heatmap + streak,
  delete button, daily doses (1-5x), dosage display with frequency
- Body Composition: BodySpec PDF import (parser handles PDFKit text format),
  regional breakdown (arms/legs/trunk + L/R), trend charts, scan comparison, delete
- Glucose: Apple Health primary + CSV import, scrollable chart, zone coloring,
  spike/dip detection, fasting/fat burning analysis (1hr+ windows, avg daily, longest,
  ignores data gaps), stats (average, range, in-zone %)
- Settings: unit toggle (kg/lbs), HealthKit sync, full re-sync
- Algorithm: configurable EMA alpha, regression window, energy density (kcal/kg),
  3 presets (Conservative/Default/Responsive)
- Biomarkers: 65 blood biomarker tracking under More tab
  - Upload lab reports (PDF or photo) with OCR extraction
  - Handles Quest Diagnostics, Labcorp, WHOOP, and generic lab formats
  - 65 biomarkers across 9 categories: Heart Health, Metabolic, Hormones, Thyroid,
    Vitamins & Minerals, Inflammation, Blood Cells, Liver, Kidney
  - Donut chart summary: Optimal/Sufficient/Out of Range counts
  - Individual biomarker detail: trend chart with zone backgrounds, knowledge base
    with accordions (what, why, relationships, how to improve), impact categories
  - Range bar visualization on list view showing value position in reference range
  - Unit normalization (mmol/L→mg/dL, nmol/L→ng/mL, etc.) for cross-lab consistency
  - Encrypted local storage: AES-256-GCM via CryptoKit, key in Keychain (thisDeviceOnly)
  - Privacy clause: data never leaves device
- Factory Reset
- Privacy note

## Database (GRDB SQLite)
12 migrations (v1-v12):
- weight_entry, meal_log, food_entry, food, supplement, supplement_log
- glucose_reading, dexa_scan, dexa_region, hk_sync_anchor, barcode_cache
- favorite_food, exercise, workout, workout_set, workout_template
- lab_report, biomarker_result

## Key Services
- WeightTrendCalculator: EMA + linear regression + configurable deficit
- HealthKitService: weight sync, calories, sleep (stage-aware), HRV, RHR, glucose
- RecoveryEstimator: recovery/sleep/strain scores from HK data
- WorkoutService: CRUD + Strong CSV import + PRs + history
- ExerciseDatabase: 873 exercises + custom persistence
- OpenFoodFactsService: barcode → nutrition lookup
- NutritionLabelOCR: Vision framework text extraction
- CGMImportService: Lingo CSV parser (handles real format with TZ offsets)
- BodySpecPDFParser: PDFKit text extraction for DEXA reports
- LabReportOCR: PDF/image lab report extraction with pattern matching for 65 biomarkers
- BiomarkerKnowledgeBase: 65 biomarker definitions, reference ranges, unit conversions
- LabReportStorage: AES-256-GCM encrypted file storage with Keychain key management
- CSVParser: generic CSV parsing

## Key Files
- project.yml → xcodegen generates .xcodeproj
- Drift/DriftApp.swift → entry point, HealthKit auth on launch (skipped in simulator)
- Drift/ContentView.swift → TabView with 5 tabs
- Drift/Utilities/Theme.swift → all colors, .card() modifier
- Drift/Utilities/Log.swift → os.Logger categories
- Drift/Resources/foods.json → 128 curated foods (snake_case keys)
- Drift/Resources/biomarkers.json → 65 biomarker definitions with knowledge base
- Drift/Resources/exercises.json → 873 exercises from free-exercise-db
- Drift/Resources/default_supplements.json → just Whey Protein auto-seeded

## Tests (609)
- DriftTests/WeightTrendCalculatorTests.swift (40)
- DriftTests/UIFlowTests.swift (49)
- DriftTests/WorkoutTests.swift (68+)
- DriftTests/WorkoutPersistenceTests.swift
- DriftTests/EdgeCaseTests.swift (26)
- DriftTests/DatabaseEdgeCaseTests.swift
- DriftTests/RobustnessTests.swift
- DriftTests/FoodLoggingTests.swift (180+) — food search, logging, recipes, macros, TDEE
- DriftTests/NutritionOCRTests.swift (15)
- DriftTests/CSVParserTests.swift (4)
- DriftTests/LabReportOCRTests.swift (48) — Quest + LabCorp real PDF extraction tests
- DriftTests/DriftTests.swift (placeholder)

## Build & Test Commands
```bash
cd ~/workspace/Drift
xcodegen generate
xcodebuild -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## TestFlight Upload
```bash
# Bump build in project.yml, then:
xcodegen generate
xcodebuild archive -project Drift.xcodeproj -scheme Drift -destination 'generic/platform=iOS' -archivePath /tmp/Drift.xcarchive DEVELOPMENT_TEAM=ZJ5H5XH82A CODE_SIGN_STYLE=Automatic
xcodebuild -exportArchive -archivePath /tmp/Drift.xcarchive -exportPath /tmp/DriftExport -exportOptionsPlist /tmp/ExportOptions.plist -allowProvisioningUpdates \
  -authenticationKeyPath "/Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_623N7AD6BJ.p8" \
  -authenticationKeyID 623N7AD6BJ -authenticationKeyIssuerID ad762446-bede-4bcd-9776-a3613c669447
# Then set encryption via API and optionally add to external group
```

## Pending Work
1. **TestFlight** - build 24 live (biomarkers feature + OCR fixes + test fixes)
2. **Known issues**: Dashboard top gap (reduced but may still be visible on some devices)

## User Preferences
- Docs-first, iterative development
- Test thoroughly before publishing
- Build + test locally, only upload to TestFlight when asked
- "Drift Myself" gets every build, "Drift Beta Users" only when explicitly told
- No MacroFactor references anywhere
- Privacy-first: all data local, no cloud
