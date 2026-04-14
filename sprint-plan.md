# Sprint Plan — Review #36 (Cycles 1380–1400)

Created: 2026-04-13

---

## Task 1: Proactive push notifications (protein / supplement / workout)
**Priority:** P0
**Classification:** SENIOR (Opus)
**Status:** [ ] pending

**Goal:** Extend proactive dashboard alerts to active push notifications. Three patterns: protein streak (3+ days low), supplement gap (missed 2+ days), workout gap (4+ days without training). This transforms Drift from passive data logger to active health coach.

**Files:**
- New: `Drift/Services/NotificationService.swift` — schedule/cancel local notifications
- `Drift/App/DriftApp.swift` — request permission at right moment (after first food log)
- Existing alert logic in dashboard — reuse detection patterns

**Approach:**
1. Add UserNotifications framework usage
2. Create NotificationService with: requestPermission(), scheduleProteinAlert(), scheduleSupplementAlert(), scheduleWorkoutGapAlert(), cancelAll()
3. Permission request: prompt after first successful food log (not on launch)
4. Schedule notifications at 6pm daily, cancel if condition resolved
5. Respect quiet hours: 9pm–8am no notifications
6. Add Settings toggle: "Health Nudges" on/off

**Edge cases:**
- User denies permission (gracefully degrade, don't prompt again)
- Condition resolved mid-day (cancel scheduled notification)
- App killed — use scheduled local notifications, not background fetch
- Multiple conditions at once (send one combined notification, not three)

**Tests:**
- NotificationService unit tests (permission state, scheduling logic)
- Condition detection tests (reuse from dashboard alert tests)
- Quiet hours enforcement

**Acceptance:** Users who miss protein/supplements/workouts receive a timely notification. No duplicate or 3am notifications.

---

## Task 2: Exercise instructions via AI chat
**Priority:** P1
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** "How do I do a deadlift?" returns form tips and muscle group info from the existing 873-exercise DB.

**Files:**
- `Drift/Services/ExerciseService.swift` — add exerciseInstructions(name:) method
- `Drift/AI/StaticOverrides.swift` or tool routing — route "how do I" exercise queries

**Approach:**
1. Check how exercise info is stored (instructions, muscle groups, category)
2. Add a query: given exercise name, return instructions + muscles + category
3. Route "how do I [exercise]" / "form tips for [exercise]" queries
4. Format response: brief form cue (2-3 sentences) + muscles targeted

**Edge cases:**
- Exercise not found (fall back to LLM general knowledge)
- Ambiguous name ("press" → clarify)

**Tests:**
- exerciseInstructions() returns data for known exercises
- Routing test: "how do I squat" triggers exercise info intent

**Acceptance:** Asking about exercise form in chat returns structured, useful response.

---

## Task 3: Systematic bug hunt
**Priority:** P1
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** Run analysis across new code paths (heatmap, recent AI changes). Find silent bugs before users do.

**Approach:**
1. Review recent commits for potential edge cases
2. Trace data paths through new features
3. Look for: off-by-one, empty state handling, nil coalescing, race conditions
4. Add regression tests for anything found

**Acceptance:** Analysis complete, any bugs found are fixed with regression tests.

---

## Task 4: sendMessage decomposition
**Priority:** P2
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** Break 491-line sendMessage into focused named methods. Pure refactor, no behavior change.

**Files:**
- `Drift/ViewModels/AIChatViewModel.swift`

**Approach:**
1. Read full sendMessage, identify logical sections
2. Extract each into private methods
3. Keep public interface identical
4. Run all tests to verify

**Acceptance:** sendMessage under 100 lines, all 981+ tests pass.
