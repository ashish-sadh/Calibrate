# Sprint Board

Priority: AI chat reliability + coverage hardening. Addresses design doc #65 (brittle AI chat) and voice input edge cases.

## In Progress

_(pick from Ready)_

## Ready

### SENIOR
- [ ] **#78 AI Chat: Input normalization pipeline** — Centralized preprocessing before all matchers. Strip filler words, normalize whitespace, handle voice artifacts. Root cause fix for P0s #67-69.
- [ ] **#79 AI Chat: Food logging gold set eval** — 30+ comprehensive eval queries covering voice-style, multi-food, Indian foods, vague quantities. Measurement framework for design doc #65.
- [ ] **#80 AI Chat: Multi-turn context hardening** — Test and fix context loss between turns. 10+ multi-turn scenarios. Addresses #65 ("need to get better with multi turn").

### JUNIOR
- [x] **#81 Coverage: WeightTrendService** — Stale-with-old-entries test (73-76 day entries, latestWeightKg from unfiltered fetch).
- [x] **#82 Coverage: AIRuleEngine** — 11 food-seeded branch tests: yesterdaySummary with data, caloriesLeft remaining/over, dailySummary food path, quickInsight with food+trend, nextAction protein branches, weeklySummary structure.
- [ ] **#83 Food DB: Top 20 search misses** — Use search miss tracking data. USDA cross-reference.
- [ ] **#84 Bug hunting: AI food logging edge cases** — Systematic analysis. Last hunt found 3 P0s.
- [x] **#85 Eval: Voice-style input test cases** — 13 cases: run-on multi-food, filler+restart, repeated conjunctions, mixed-case fillers, chained restarts, extra whitespace.
- [x] **#86 UI: Exercise card visual enhancement** — Done (muscle group SF Symbol chips shipped in prior sprint).
- [x] **#87 Coverage: NotificationService + BehaviorInsightService hardening** — 4-alert composition, all-poor-sleep boundary, exactly-6h boundary, proactive alerts structural integrity.

### Design Docs (senior handles directly, not sprint tasks)
- #65 Design: How should we structurally fix AI chat?
- #66 Design: How to enrich images and youtube in exercises
- #74 Feature: Improve lab reports upload and try to use LLM when available to parse values

---

## Permanent Tasks (never remove — always pick from these when nothing else is queued)

**Before picking a task, read `Docs/roadmap.md` → "Now" items in the relevant domain. Work on what advances the current phase.**

### AI Chat Architecture & Quality (always ongoing)
Equally important pillar. Prefer architectural improvements over keyword additions.

- [ ] **State machine refactor** — Replace scattered pendingMealName/pendingWorkout state vars with a proper conversation state machine. States: idle → classifying → executing_tool → confirming → logging. Clear transitions, no dangling state.
- [ ] **Prompt consolidation** — Single source of truth for tool schemas, examples, context injection. Measure token count, compress.
- [ ] **Multi-turn reliability** — Eliminate bugs where context is lost between turns. Test: 3-turn meal logging, 3-turn workout building, topic switching mid-conversation.
- [ ] **Natural freeform logging** — "log for breakfast 2 eggs and spinach and bread and coffee with 2% milk with protein powder and creatine" or "log chipotle bowl with 800 calories" → AI parses everything, asks clarifying questions, does macro calculations, logs it.
- [ ] **Meal planning** — "plan my meals for today" → iterative suggestions based on remaining macros + history.
- [ ] **Workout split builder** — "build me a PPL split" → multi-turn designing across sessions.
- [ ] **Navigate to screen** — "show me my weight chart", "go to food tab". Needs navigation tool.
- [ ] When no obvious gap: stress-test with real queries from `Docs/failing-queries.md` and fix what breaks.

### UI Overhaul (always ongoing)
Equally important pillar. Bold changes encouraged — a full theme redesign overnight is fine. New card styles, new color palette, new typography — go for it. The only rule: app-wide consistency.

- [ ] **Theme overhaul** — Pick a direction and execute across ALL views in one cycle. Dark+accent, light+minimal, glassmorphism — any coherent vision. Touch every view.
- [ ] **Dashboard redesign** — Better information hierarchy, scannable at a glance, clearer progress indicators.
- [ ] **Chat UI polish** — Message bubbles, typing indicators, tool execution feedback, streaming UX.
- [ ] **Food diary UX** — Faster logging flow, better meal grouping, clearer macro display.
- [ ] **Usability rough edges** — Find confusing flows, missing feedback, awkward transitions. Fix them.
- [ ] UI changes must NOT break existing functionality. Visual-layer refactoring only.

### Test Coverage Improvement (always ongoing)
Ship quality. Coverage is a forcing function for finding bugs and understanding code.

- [ ] **Run coverage-check.sh** — Identify files below 80% (logic) or 50% (services) threshold. Fix them.
- [ ] **Write tests for uncovered paths** — Focus on error paths, edge cases, empty states, boundary conditions. Not just happy paths.
- [ ] **AI eval harness expansion** — Add test cases for every new capability. Target: every tool has 10+ eval queries.
- [ ] **Integration-style tests** — Test multi-step flows (parse → resolve → log → confirm) end-to-end.

### Bug Hunting (always ongoing)
Proactively find bugs before users do.

- [ ] **Find and fix bugs** — Run the app mentally through edge cases. Check error paths, empty states, boundary conditions, data corruption scenarios.
- [ ] **Regression prevention** — When fixing a bug, add a test that would have caught it.

### Food Database Enrichment (always ongoing)
Better the DB, more people will come and log. Benchmark: MyFitnessPal has 14M+ foods.

- [ ] **Correct existing entries** — Find foods with wrong macros, missing data, bad serving sizes. Fix them.
- [ ] **Add missing foods** — Indian foods, regional dishes, restaurant items, branded products. Cross-reference with USDA/reliable sources.
- [ ] **Improve search** — Better aliases, spelling corrections, partial matches. "paneer" should find all paneer dishes.

### Ongoing: Code Improvement Loop
Autonomous refactoring. Run `code-improvement.md`. Principles in `Docs/principles/`. Log in `Docs/code-improvement-log.md`.

- [x] **Continue file decomposition** — GoalSetupView, LabsAndScans, Sleep, TemplatePreviewSheet extracted. Only 3 files over 700 remain (AIChatView, FoodTabView, ActiveWorkoutView) — these need ViewModel extraction.
- [ ] **Deeper refactoring** — Extract logic from fat functions (AIChatView.sendMessage 491 lines). Move business logic out of views into ViewModels/Services.
- [ ] **DDD violations** — Direct DB calls in views, business logic in UI layer.

## Done (this sprint)
- [x] P0: Supplement/Sleep Confirmation Cards — Status card with taken/remaining, sleep card with HRV/recovery/readiness.
- [x] P0: Glucose + Biomarker Confirmation Cards — Glucose avg/range/spikes/zone, biomarker optimal/out-of-range.
- [x] P1: AIChatView ViewModel Extraction — Separated state+logic from rendering. @Observable class + extensions.
- [x] P1: Exercise Visual Polish — Muscle group SF Symbol chips on workout cards.
- [x] P1: State.md Update — Build 108, 8 card types documented.
- [x] P0: Bug Hunting — Misleading checkmark on unconfirmed workout card, force unwrap crash.
- [x] P0: Rich Confirmation Cards — Navigation cards (new), activity preview cards (new). All chat actions now have structured visual feedback.
- [x] P0: Workout Split Builder — "build me a PPL split" multi-turn dialogue. 4 split types, template saving. 15 tests.
- [x] Voice Input UX Overhaul — fixed eaten-words bug (partial vs final transcription). Build 107.
- [x] P1: Navigate to Screen from Chat — static overrides + LLM navigate_to tool + tab switching. 16 tests.
- [x] P1: Wire USDA into AI Chat — log_food preHook + food_info handler USDA/OpenFoodFacts fallback. 4 tests.
- [x] P1: Systematic Bug Hunting — tab bounds check, USDA API 5s timeout, Swift 6 concurrency fix.
- [x] P0: Proactive Alerts — workout consistency + logging gap alerts. 6 alert types.
- [x] P0: USDA API Phase 1 — opt-in toggle, rate limiting, searchWithFallback, privacy notice
- [x] #81 WeightTrendService: stale-with-old-entries coverage test
- [x] #82 AIRuleEngine: 11 food-seeded branch tests (yesterdaySummary, caloriesLeft, dailySummary, quickInsight, nextAction, weeklySummary)
- [x] #85 Voice-style eval: 13 InputNormalizer cases (run-on, filler+restart, conjunctions, mixed-case)
- [x] #87 NotificationService + BehaviorInsightService hardening (4-alert composition, sleep boundaries)
- [x] TestFlight build 106, 107
- [x] Build 117 — test coverage improvements committed
