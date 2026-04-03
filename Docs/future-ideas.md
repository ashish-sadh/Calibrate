# Future Ideas (Deferred from Self-Improvement Sessions)

These are larger changes identified during autonomous sessions that require human decision-making.

## Architecture
- **UserDefaults key centralization**: 30+ hardcoded string keys across 10+ files. Create a Constants.swift enum.
- **DateFormatter allocation**: 22 views create DateFormatter instances in functions. Could be moved to static lazy properties for performance.
- **DEXA data model**: 14 optional Double fields could be a flexible key-value schema for easier expansion.

## Features
- **Workout streak tracking**: Show current streak and longest streak alongside the consistency chart.
- **Food logging reminders**: Optional notification if no food logged by a certain time.
- **Export data**: Allow users to export their weight, food, workout data as CSV.
- **Widget support**: iOS home screen widget showing today's calories remaining or recovery score.

## Performance
- **Cache recovery baselines**: Dashboard fetches 14-day HRV/RHR/sleep history (42 HealthKit queries) on every load. Should cache baselines for 6 hours.
- **Accessibility labels**: Zero VoiceOver labels in the entire app. Needs systematic pass.

## TDEE
- **Schofield equation as alternative base**: Research shows the sex-averaged Schofield BMR (10.1*W + 851) × activity factor is more accurate than our sqrt scaling (16-20% higher). Could swap in as base formula when no Mifflin profile exists. Trade-off: higher estimates might feel alarming to users in deficit. Current conservative approach is safer but could be configurable.
- **Hard ceiling at 4000 kcal**: Research suggests capping no-profile TDEE at 4000 kcal (covers 140kg very-active). Only elite athletes exceed this. Current soft cap at 2700 is aggressive but matches user preference.

## Lab Report OCR
- **Epic MyChart format**: ~35% of US hospitals use Epic. Format: `Component | Value | Flag | Standard Range | Units` with H/L/HH/LL flags. Adding this parser would cover the biggest gap.
- **Cerner/Oracle Health format**: ~25% of hospitals. Format: `Test Name | Result Value | Units | Reference Range | Interpretation` with Normal/High/Low words.
- **Inline flag parsing (VA/older systems)**: Some formats put flag inline with value: `GLUCOSE 102 H mg/dL 74-100`. Need to strip trailing H/L from numeric value.
- **Colon-separated format (DTC brands)**: `Glucose: 89 mg/dL (65-99)`. Used by LetsGetChecked, some wellness brands.
- **Additional providers to detect**: BioReference Laboratories, ARUP Laboratories, Life Extension, Ulta Lab Tests, Mayo Clinic Labs.

## Apple Health Integration
- **Body fat percentage**: Could enable Katch-McArdle BMR formula for more accurate TDEE when body fat is known from smart scales.
- **VO2 Max**: Fitness level indicator from Apple Watch. Could factor into recovery scoring or activity recommendations.
- **Walking heart rate average**: More stable than resting HR for recovery estimation on days without formal workouts.

## Small Delights (researched, 1-2 hours each)
- **Weekday weight pattern**: "You tend to weigh least on Wednesdays" — group historical weights by day-of-week, show insight. Users never think to check this.
- **Macro rings on Food tab**: Concentric rings (like Apple Fitness) showing P/C/F progress toward targets. "Close the ring" motivation.
- **Time since last meal**: Dashboard shows "Last logged 4h ago" when it's been a while. Non-annoying awareness without push notifications.

## UI
- **Dark theme variant**: Some users may prefer a slightly lighter dark (OLED black vs dark gray).
- **Haptic feedback**: Add subtle haptics to key interactions (logging food, completing a set, finishing a workout).
