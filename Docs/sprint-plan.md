# Sprint Plan — Review #37 (Cycles 1483–1503)

Created: 2026-04-13

---

## Task 1: sendMessage decomposition
**Priority:** P0
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [x] done (already decomposed — 128 lines, 21 extracted handle* methods)

**Goal:** Break 491-line sendMessage into focused named methods. Pure refactor, no behavior change.

**Files:**
- `Drift/ViewModels/AIChatViewModel.swift`

**Approach:**
1. Read full sendMessage, identify logical sections (input validation, state prep, static overrides, LLM pipeline, response handling, card attachment, cleanup)
2. Extract each into private methods with clear names
3. Keep public interface identical — `sendMessage()` becomes a coordinator that calls private methods
4. Run all 1,037 tests to verify zero behavior change

**Edge cases:**
- Early returns in nested conditions must be preserved (guard statements)
- Shared mutable state between sections (conversation state, pending vars)
- Error handling paths must remain identical

**Tests:**
- All existing 1,037 tests must pass unchanged
- No new tests needed (pure refactor)

**Acceptance:** sendMessage under 100 lines, all tests pass, zero behavior change.

---

## Task 2: Food search miss analysis + targeted additions
**Priority:** P1
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** Identify the most-searched missing foods and add them. Every "not found" = user opens MFP.

**Files:**
- `Drift/Resources/foods.json`
- Possibly `Drift/Services/SpellCorrectService.swift` for new synonyms

**Approach:**
1. Review common food queries from eval harness and failing-queries.md
2. Cross-reference with USDA for accurate nutrition data
3. Add 20-30 high-value missing foods (focus on frequently searched items)
4. Add synonyms for regional variants

**Tests:**
- Search tests for each added food
- Verify existing foods not broken

**Acceptance:** Top 20 search misses addressed. Build passes.

---

## Task 3: Notification + behavior alert test coverage
**Priority:** P1
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** NotificationService and BehaviorInsightService alert detection have zero dedicated unit tests. Add edge-case coverage.

**Files:**
- `DriftTests/` — new test file or extend existing

**Approach:**
1. Test proteinStreakAlert edge cases: exactly 3 days, 2 days (no alert), data gaps
2. Test supplementGapAlert: new supplement (no history), all taken, mixed
3. Test workoutConsistencyAlert: 4 days vs 5 days threshold
4. Test loggingGapAlert: logged today only, logged yesterday only
5. Test composeNotification: single alert, multiple alerts

**Acceptance:** All alert detection methods have dedicated tests. Coverage for BehaviorInsightService above 50%.

---

## Task 4: Systematic bug hunt
**Priority:** P1
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** Quarterly practice. Focus on notification scheduling, food diary edge cases, recent AI changes.

**Approach:**
1. Review NotificationService for edge cases (permission revoked mid-session, toggle race)
2. Review food diary copy/reorder for timestamp edge cases
3. Trace data paths through recent features
4. Add regression tests for anything found

**Acceptance:** Analysis complete, any bugs found are fixed with regression tests.

---

## Task 5: State.md refresh
**Priority:** P2
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** State.md is stale — tests show 981 (actual: 1,037), build 108 (actual: 112), capabilities incomplete.

**Files:**
- `Docs/state.md`

**Approach:**
1. Update all numbers: tests, build, foods, exercises, tools, card types
2. Update AI chat capabilities list
3. Update tech stack notes if changed

**Acceptance:** State.md accurately reflects current build.
