# Sprint Board

Focus: **AI Chat LLM-First Pipeline.** Flip from rules-first to LLM-first on Gemma 4 devices. Addresses product focus and design doc #65.

## Decision Required

**Design doc #65 (PR #112) needs your approval.** It proposes making IntentClassifier the primary routing path — shrinking StaticOverrides from ~50 hardcoded patterns to ~10 essentials, and retiring ToolRanker keyword scoring on Gemma 4. Every query goes through the LLM instead of brittle regex matching. Latency tradeoff: ~3s correct answer beats instant wrong answer.

Review PR #112 and add `approved` label to unblock the refactor tasks below.

## In Progress

_(pick from Ready)_

## Ready

### SENIOR — Ready Now (no approval needed)

_(all tasks completed)_

### SENIOR — Contingent on #65 Approval

These implement design doc #65. Do not start until PR #112 is approved.

- [ ] **#92 AI Chat: Reorder AIToolAgent pipeline (LLM-first)** — Core pipeline change. Gemma 4 path becomes: normalizer -> thin static (~10 patterns) -> IntentClassifier -> tool execution -> streaming fallback. SmolLM path stays unchanged. Run gold set eval before AND after to measure delta.
- [ ] **#93 AI Chat: Prune StaticOverrides to essential patterns** — Remove all intent-classification rules. Keep only: greetings, thanks, help, undo, barcode scan (~10 patterns). These are interaction patterns, not intent classification. ~40 handlers removed.
- [ ] **#94 AI Chat: Retire ToolRanker keyword scoring (Gemma path)** — Remove `tryRulePick()` and keyword scoring for Gemma 4 devices. Keep `buildPrompt()` for SmolLM fallback and `rank()` for suggestion pill display.
- [ ] **#95 AI Chat: Extend IntentClassifier for primary routing** — Add voice-style examples to system prompt. Implement confidence-based fallback (confused/short responses fall to streaming). Increase history window 200->400 chars for better multi-turn. Add 5+ new in-context examples covering food, exercise, health queries.

### JUNIOR

- [ ] **#96 Coverage: Pipeline refactor tests** — After pipeline changes land, ensure AIToolAgent, IntentClassifier, and StaticOverrides maintain coverage targets (80% logic, 50% services). Write new tests for LLM-first routing path.
- [ ] **#97 Bug hunting: Voice + chat end-to-end** — Exercise the new pipeline with realistic voice transcription output. Focus on food logging (most common action) and multi-turn flows.
- [ ] **#118 Food DB: +30 missing foods (voice-friendly)** — Continue enrichment toward USDA API integration. Focus on commonly spoken foods (voice users say "burger" not "hamburger patty"). Cross-reference search misses.
- [ ] **#99 Docs: Update state.md** — Reflect pipeline architecture changes post-refactor.

### Design Docs (pending review)
- #65 Design: How should we structurally fix AI chat? -- PR #112, `doc-ready`, **awaiting approval**
- #66 Design: How to enrich images and youtube in exercises -- `doc-ready`
- #74 Feature: Improve lab reports upload + LLM parsing -- `doc-ready`

---

## Permanent Tasks (never remove -- always pick from these when nothing else is queued)

**Before picking a task, read `Docs/roadmap.md` -> "Now" items in the relevant domain. Work on what advances the current phase.**

### AI Chat Architecture & Quality (always ongoing)
Equally important pillar. Prefer architectural improvements over keyword additions.

- [ ] **State machine refactor** -- Replace scattered pendingMealName/pendingWorkout state vars with a proper conversation state machine. States: idle -> classifying -> executing_tool -> confirming -> logging. Clear transitions, no dangling state.
- [ ] **Prompt consolidation** -- Single source of truth for tool schemas, examples, context injection. Measure token count, compress.
- [ ] **Multi-turn reliability** -- Eliminate bugs where context is lost between turns. Test: 3-turn meal logging, 3-turn workout building, topic switching mid-conversation.
- [ ] **Natural freeform logging** -- "log for breakfast 2 eggs and spinach and bread and coffee with 2% milk with protein powder and creatine" or "log chipotle bowl with 800 calories" -> AI parses everything, asks clarifying questions, does macro calculations, logs it.
- [ ] **Meal planning** -- "plan my meals for today" -> iterative suggestions based on remaining macros + history.
- [ ] **Workout split builder** -- "build me a PPL split" -> multi-turn designing across sessions.
- [ ] **Navigate to screen** -- "show me my weight chart", "go to food tab". Needs navigation tool.
- [ ] When no obvious gap: stress-test with real queries from `Docs/failing-queries.md` and fix what breaks.

### UI Overhaul (always ongoing)
Equally important pillar. Bold changes encouraged -- a full theme redesign overnight is fine. New card styles, new color palette, new typography -- go for it. The only rule: app-wide consistency.

- [ ] **Theme overhaul** -- Pick a direction and execute across ALL views in one cycle. Dark+accent, light+minimal, glassmorphism -- any coherent vision. Touch every view.
- [ ] **Dashboard redesign** -- Better information hierarchy, scannable at a glance, clearer progress indicators.
- [ ] **Chat UI polish** -- Message bubbles, typing indicators, tool execution feedback, streaming UX.
- [ ] **Food diary UX** -- Faster logging flow, better meal grouping, clearer macro display.
- [ ] **Usability rough edges** -- Find confusing flows, missing feedback, awkward transitions. Fix them.
- [ ] UI changes must NOT break existing functionality. Visual-layer refactoring only.

### Test Coverage Improvement (always ongoing)
Ship quality. Coverage is a forcing function for finding bugs and understanding code.

- [ ] **Run coverage-check.sh** -- Identify files below 80% (logic) or 50% (services) threshold. Fix them.
- [ ] **Write tests for uncovered paths** -- Focus on error paths, edge cases, empty states, boundary conditions. Not just happy paths.
- [ ] **AI eval harness expansion** -- Add test cases for every new capability. Target: every tool has 10+ eval queries.
- [ ] **Integration-style tests** -- Test multi-step flows (parse -> resolve -> log -> confirm) end-to-end.

### Bug Hunting (always ongoing)
Proactively find bugs before users do.

- [ ] **Find and fix bugs** -- Run the app mentally through edge cases. Check error paths, empty states, boundary conditions, data corruption scenarios.
- [ ] **Regression prevention** -- When fixing a bug, add a test that would have caught it.

### Food Database Enrichment (always ongoing)
Better the DB, more people will come and log. Benchmark: MyFitnessPal has 14M+ foods.

- [ ] **Correct existing entries** -- Find foods with wrong macros, missing data, bad serving sizes. Fix them.
- [ ] **Add missing foods** -- Indian foods, regional dishes, restaurant items, branded products. Cross-reference with USDA/reliable sources.
- [ ] **Improve search** -- Better aliases, spelling corrections, partial matches. "paneer" should find all paneer dishes.

### Ongoing: Code Improvement Loop
Autonomous refactoring. Run `code-improvement.md`. Principles in `Docs/principles/`. Log in `Docs/code-improvement-log.md`.

- [x] **Continue file decomposition** -- GoalSetupView, LabsAndScans, Sleep, TemplatePreviewSheet extracted. Only 3 files over 700 remain (AIChatView, FoodTabView, ActiveWorkoutView) -- these need ViewModel extraction.
- [ ] **Deeper refactoring** -- Extract logic from fat functions (AIChatView.sendMessage 491 lines). Move business logic out of views into ViewModels/Services.
- [ ] **DDD violations** -- Direct DB calls in views, business logic in UI layer.

## Done (this sprint)

- [x] #116 AI Chat: Expand gold set eval to 55 queries (cross-domain: food, weight, exercise, navigation, health, multi-turn, negatives. 100% baseline accuracy)
- [x] #117 AI Chat: Voice input edge case hardening (mid-sentence correction handling in InputNormalizer, 10 new tests)

## Done (previous sprint)
- [x] #78 Input normalization pipeline (centralized at sendMessage entry point)
- [x] #79 Food logging gold set eval (13 voice-style tests)
- [x] #80 Multi-turn context hardening (18 multi-turn tests)
- [x] #81 Coverage: WeightTrendService (stale-with-old-entries)
- [x] #82 Coverage: AIRuleEngine (11 food-seeded branch tests)
- [x] #83 Food DB: +20 foods (chana masala, rajma chawal, dal chawal, etc. 1544->1564)
- [x] #84 Bug hunting: AI food logging edge cases (multi-food meal hint fix)
- [x] #85 Eval: Voice-style input test cases (13 InputNormalizer cases)
- [x] #86 UI: Exercise card visual enhancement (muscle group SF Symbol chips)
- [x] #87 Coverage: NotificationService + BehaviorInsightService hardening
- [x] P0 #77: Remove meal category grouping from food diary
- [x] P0 #88: Fix AI food logging (extract food name, macro sanity check)
