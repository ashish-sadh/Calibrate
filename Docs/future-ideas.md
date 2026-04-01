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

## UI
- **Dark theme variant**: Some users may prefer a slightly lighter dark (OLED black vs dark gray).
- **Haptic feedback**: Add subtle haptics to key interactions (logging food, completing a set, finishing a workout).
