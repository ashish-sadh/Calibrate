# Workout Timer Background Fix

## Status: CODE COMPLETE, TESTS PASSING (673/673)

## Bug
When the app is minimized during a workout, both timers (workout elapsed time and rest timer) freeze. On return, they resume from where they were instead of reflecting actual elapsed time.

## Root Cause
1. **Workout timer**: Uses `Timer.scheduledTimer` which iOS suspends in background. Although it calculates `Date().timeIntervalSince(startTime)` (correct approach), the Timer itself stops firing, so the display freezes until the next tick — which may never come if iOS kills the timer.
2. **Rest timer**: Used `restSeconds -= 1` decrement — purely incremental, so any background time is completely lost.

## Fix Applied (in `Drift/Views/Workout/WorkoutView.swift`)

### 1. Added `scenePhase` environment monitoring
- Line 697: `@Environment(\.scenePhase) private var scenePhase`
- `.onChange(of: scenePhase)` handler (after `.onDisappear`) that fires when app returns to foreground

### 2. Fixed rest timer to use wall-clock end time
- Added `@State private var restEndTime: Date?` (line ~712)
- `startRest()` now sets `restEndTime = Date().addingTimeInterval(Double(duration))`
- New `startRestTimerTick()` function calculates `remaining = Int(ceil(endTime.timeIntervalSince(Date())))` instead of decrementing
- Uses `ceil()` so partial seconds round up (shows "1" not "0" when 0.3s remains)

### 3. Foreground recovery in `onChange(of: scenePhase)` handler
When `scenePhase` becomes `.active`:
- **Workout timer**: Invalidates old timer, immediately recalculates `elapsedSeconds` from `startTime`, starts fresh timer
- **Rest timer**: Checks `restEndTime` — if time remains, updates `restSeconds` and restarts tick; if expired, sets to 0 and vibrates

## Files Changed
- `Drift/Views/Workout/WorkoutView.swift` — timer logic + scenePhase handling
- `DriftTests/WorkoutTests.swift` — 10 new tests added

## Tests Added (10 new, at bottom of WorkoutTests.swift)
Under `// MARK: - Timer Background Resilience Tests`:
1. `elapsedTimeCalculatesFromStartTimeNotIncrement` — verifies Date-based elapsed calc
2. `elapsedTimeAfterSimulatedBackground` — 10min elapsed with 5min background
3. `restTimerEndTimeBasedCalculation` — remaining = endTime - now
4. `restTimerExpiresDuringBackground` — rest finishes while backgrounded
5. `restTimerExactlyExpires` — edge case: exact duration elapsed
6. `restTimerPartialSecondRoundsUp` — ceil() for 0.3s remaining
7. `sessionPersistencePreservesStartTime` — save/load round-trips startTime
8. `sessionPersistenceWithExercises` — full session with sets round-trips
9. `sessionClearRemovesData` — clearSession works
10. `elapsedTimeZeroAtStart` — sanity check

## Manual Testing Checklist
- [ ] Start workout, minimize app for 30s, return — elapsed time should jump correctly
- [ ] Start workout, start rest timer (complete a set), minimize for rest duration, return — rest should show complete with vibration
- [ ] Start workout, start rest timer, minimize for partial rest duration, return — rest timer should show correct remaining time
- [ ] Start workout, minimize, kill app, reopen — session should restore with correct elapsed time (existing behavior, just verify)
- [ ] Rest timer progress bar should animate smoothly after returning from background

## What's NOT Covered
- Live Activity / Dynamic Island for timer (would require ActivityKit — separate feature)
- Background notifications when rest timer completes while app is minimized (would require UNUserNotificationCenter — separate feature, nice-to-have)
