# Self-Improvement Session Log

## Session 4 (April 3, 2026) — IN PROGRESS
- **Commits**: 16
- **Commits**: 26
- **Tests**: 640 → 663 (+23, 0 regressions, 2 flaky tests fixed)
- **Food DB**: 817 → 979 foods (+127 Indian, +30 global, +5 spirits), 8 USDA corrections

### New Features
- Cycle tracking from Apple Health (6-section view: hero, timeline, biometric correlation chart, cycle length trend, fertile window, history)
- Food diary time-ordered entries with `loggedAt` field + copy-from-yesterday preserves eating times
- Copied entry indicator (purple doc.on.doc icon)
- Full simulator mock data for all HealthKit metrics (calories, steps, sleep, HRV, RHR, workouts, cycle)
- Advanced Insights opt-in toggle for fertile window (privacy-first)
- Privacy note on cycle page

### Bug Fixes
- Ovulation estimate: `avg/2` → standard `avg-14` formula
- `fertileWindowDayRange` was ignoring its parameter
- Duplicate cycleLengths computation → single source of truth
- DateFormatter per-call allocations → shared static instances (60+ allocations/render → 0)
- copyFromYesterday double-tap guard
- copyFromYesterday handles SQLite datetime format for old entries
- Mixed ISO8601/SQLite timestamp sort fix
- Duplicate shortDate formatter removed
- Neutralized "Apple Watch" → "fitness-tracking watch" in SleepRecoveryView

### Code Quality
- Extracted CycleCalculations.swift (testable computation layer)
- 16 cycle calculation tests + 6 loggedAt/formatter tests

### Food Database
- 127 Indian foods: besan, ladoo, barfi, chutneys, all paratha types, paneer curries, south Indian, regional
- 30 global foods: berries, condiments, seafood, beverages, grains
- 8 corrections: dal fiber +50%, cottage cheese -14% cal/protein, egg -6 cal, cabbage all macros

### Barcode Scanner Fix
- Scanned foods now use smart unit picker (ml, cup, g, tbsp) instead of bare "100g servings" stepper
- Uses actual product serving size from OpenFoodFacts, not hardcoded 100g
- Fixed critical display bug: preview showed per-100g values instead of per-serving
- "Scan Another" now properly resets OCR state

### Research
- UX research curated to Docs/future-ideas.md (food/exercise logging, AI photo, exercise GIFs)
- App taste memory saved (privacy-first, Indian food focus, clean dark UI, practical over fancy)

---

## Session 3 (April 2-3, 2026) — COMPLETED
- **Commits**: 64
- **TestFlight**: Builds 51-57 published
- **Tests**: 566 → 630 (+64, 0 regressions)
- **Food DB**: 716 → 817 foods
- **Exercise DB**: 884 → 960 exercises

### New Features
- "New Low!" / "New High!" milestone toast on weight entry
- "Same as yesterday" for supplements
- Weekday weight pattern insight ("You weigh least on Wednesdays")
- "Favorite all exercises" toggle in workout finish
- "Wrong direction" detection on goal pace
- Hevy CSV import (auto-detected alongside Strong)
- Auto-extract workout templates from Strong/Hevy recurring workouts
- Strong CSV: RPE + Weight Unit (kg→lbs auto-conversion)
- Hevy: warmup set detection from set_type
- Smart serving defaults (remembers last-used amount per food)
- Quick-log uses last serving size
- Food logging streak counter
- Template list shows exercise names preview
- Deficit explainer (?) with calculation breakdown

### UI Redesign
- True black background, lighter cards (0.08 opacity)
- 47 font fixes (no sub-11pt), VoiceOver on 7 screens
- Apple Health style weight chart (clean line, no scatter)
- Renpho-style TDEE ring (eating/deficit/burning)
- Food tab: 7-day strip, week nav, past-date amber banner, dots for logged days
- Food log half-sheet, energy balance ring, smart intake estimation

### Algorithms
- Recovery overhaul: missing HRV → weight redistribution (55→88)
- TDEE soft cap at 2700, target sync fix
- Weight trend fallback uses recent entries

### Bug Fixes
- 20+ bug fixes including factory reset, barcode serving, duration parsing, card contrast, weekOffset reset, macro field contrast, chart annotations

---

## Previous Sessions
- Session 2 (April 1-2): 33 commits, Builds 51-53
- Session 1 (March 29-30): 33 commits, Builds 48-49
