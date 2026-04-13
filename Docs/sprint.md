# Sprint Board

Priority: LLM-first AI chat — remove hardcoded strings, use LLM for intent detection + tool calling.

## In Progress

_(pick from Ready)_

## Ready

### P0: Bug Hunting on Recent Features
- [ ] **Systematic analysis of workout split builder + voice UX + confirmation cards** — Run analysis agent on new code. Find silent issues before testers do.

### P1: AIChatView ViewModel Extraction
- [ ] **Extract ViewModel from AIChatView** — File has 4 card types, voice state, conversation state. Extract before adding more card types.

### P1: Supplement/Sleep Confirmation Cards
- [ ] **Extend card pattern to remaining actions** — Supplement logging, sleep queries, glucose readings should show structured cards. Do after ViewModel extraction.

### P2: Food DB Quality
- [ ] **Search miss analysis + targeted additions** — Identify most-searched missing foods. Cross-reference with USDA. Every "not found" = user opens MFP.

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
- [x] P0: Rich Confirmation Cards — Navigation cards (new), activity preview cards (new). All chat actions now have structured visual feedback.
- [x] P0: Workout Split Builder — "build me a PPL split" multi-turn dialogue. 4 split types, template saving. 15 tests.
- [x] Voice Input UX Overhaul — fixed eaten-words bug (partial vs final transcription). Build 107.
- [x] P1: Navigate to Screen from Chat — static overrides + LLM navigate_to tool + tab switching. 16 tests.
- [x] P1: Wire USDA into AI Chat — log_food preHook + food_info handler USDA/OpenFoodFacts fallback. 4 tests.
- [x] P1: Systematic Bug Hunting — tab bounds check, USDA API 5s timeout, Swift 6 concurrency fix.
- [x] P0: Proactive Alerts — workout consistency + logging gap alerts. 6 alert types.
- [x] P0: USDA API Phase 1 — opt-in toggle, rate limiting, searchWithFallback, privacy notice
- [x] TestFlight build 106, 107
- [x] 981 tests
