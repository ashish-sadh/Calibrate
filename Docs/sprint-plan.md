# Sprint Plan — Review #39 (Cycles 1627–1647)

Created: 2026-04-14

---

## Task 1: sendMessage decomposition
**Priority:** P0
**Classification:** SENIOR (Opus)
**Status:** [x] done — 128→28 lines, 4 phase methods extracted, 1131 tests pass

**Goal:** Organize the 25+ handler methods in AIChatView+MessageHandling.swift into clearly named phase groups. The main sendMessage dispatcher (128 lines) calls handlers across 1,168 lines. Group handlers by phase, clarify ownership of ConversationState transitions, make each phase independently testable.

**Files:**
- Drift/Views/AI/AIChatView+MessageHandling.swift (1,168 lines — main target)
- Drift/Views/AI/AIChatViewModel.swift (class definition, types)
- Drift/Services/ConversationState.swift (Phase enum)

**Approach:**
1. Read sendMessage dispatcher (lines 164-292) — understand the 9 dispatch phases
2. Group handlers by phase: static overrides, workout quick paths, confirmations, view-state handlers, multi-turn continuations, planning triggers, food intent parsing, AI pipeline
3. Extract each phase group into a clearly named extension method (e.g., `handleStaticOverrides`, `handleMultiTurnContinuation`)
4. The main sendMessage becomes a clean sequential dispatcher calling phase methods
5. Ensure ConversationState phase transitions remain sequential — never reorder or parallelize
6. Run full test suite after each extraction step

**Edge cases:** ConversationState.phase must be set AFTER handler processing completes (line 494 pattern). weak self in closures. Async/await boundaries between phases.

**Tests:** All 996+ existing tests must pass. Add focused tests for individual phase handlers if coverage gaps found.

**Acceptance:** sendMessage is a clean dispatcher under 50 lines. Each phase group is a named method. All tests pass.

---

## Task 2: Systematic bug hunt
**Priority:** P0
**Classification:** SENIOR (Opus)
**Status:** [ ] pending

**Goal:** Proactive quality pass. Carried 3 sprints — must ship. Focus on notification scheduling edge cases, food diary boundary conditions, and recent AI pipeline changes.

**Files:**
- Drift/Services/NotificationService.swift (scheduling, permission, toggle edge cases)
- Drift/ViewModels/FoodLogViewModel.swift (diary copy/reorder/delete edge cases)
- Drift/Views/AI/AIChatView+MessageHandling.swift (recent card attachment paths)

**Approach:**
1. Trace NotificationService: permission revoked mid-session, toggle race conditions, schedule after midnight, duplicate scheduling
2. Trace food diary: same-timestamp entries, copy from empty day, delete last item, edit zero-calorie entry
3. Check recent card attachment code for nil/empty state handling
4. File any bugs found as GitHub Issues with regression tests
5. If bugs found, fix them with tests in the same cycle

**Edge cases:** Permission state changes between check and schedule. Timer firing during app background.

**Tests:** Add regression tests for every bug found. Target: 5+ new tests minimum.

**Acceptance:** Analysis complete, all found bugs fixed with tests. If clean, document what was checked.

---

## Task 3: iOS widget prototype
**Priority:** P1
**Classification:** SENIOR (Opus)
**Status:** [ ] pending

**Goal:** Create a "Calories Remaining" home screen widget using WidgetKit. First Phase 4 surface — makes Drift visible throughout the day without opening the app.

**Files:**
- New: DriftWidget/ extension target
- project.yml (add widget extension target)
- Shared data: App Groups for data sharing between main app and widget

**Approach:**
1. Add App Group capability to main app and create widget extension target in project.yml
2. Run xcodegen generate
3. Create shared UserDefaults suite for App Group data sharing
4. Write today's calorie data to shared UserDefaults on each food log
5. Create TimelineProvider that reads shared calorie data
6. Design small/medium widget: calories remaining number, progress ring, date
7. Static timeline with refresh on app foreground (not live-updating — battery concern)
8. Test on simulator

**Edge cases:** No data state (user hasn't logged today). Widget timeline refresh frequency. GRDB concurrent reads from widget process — use shared UserDefaults instead for simplicity.

**Tests:** Widget provider unit tests with mock data. Main app data-sharing tests.

**Acceptance:** Widget appears on home screen showing today's remaining calories. Updates when app is opened after logging food.

---

## Task 4: Food search miss analysis
**Priority:** P2
**Classification:** JUNIOR (Sonnet + advisor)
**Status:** [ ] pending

**Goal:** Track zero-result food searches to make DB improvements data-driven. Every "not found" = user opens competitor.

**Files:**
- Drift/Services/FoodService.swift (add search miss logging)
- Drift/Database/AppDatabase.swift (add search_misses table)

**Approach:**
1. Add a `search_misses` table: query text, timestamp, count
2. On zero-result local search (before USDA fallback), log the query
3. Dedup similar queries (lowercase, trim whitespace)
4. Don't log if USDA fallback succeeds (user got a result)
5. After data accumulates, analyze top misses for targeted food additions

**Edge cases:** Privacy — search misses stay local only. Don't log partial typing (only completed searches). Dedup "chicken" and "chickens" variants.

**Tests:** Test miss logging, dedup logic, query counting.

**Acceptance:** search_misses table exists, logging works, initial analysis documented.
