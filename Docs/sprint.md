# Sprint Board

Priority: LLM-first AI chat — remove hardcoded strings, use LLM for intent detection + tool calling.

## In Progress

_(pick from Ready)_

## Ready

### P0: Voice Input Prototype
- [ ] **SpeechRecognizer → chat pipeline** — Add mic button to chat. iOS SFSpeechRecognizer → on-device speech-to-text → feed text into existing chat input. Don't build separate speech pipeline — reuse existing AI pipeline. Test with real spoken input (messy, partial sentences, "um", corrections). Branch first, merge when working. Go/no-go at Review #14.

### P0: Color & Visual Harmony Pass
- [ ] **Fix color coordination app-wide** — The dark blue/purple palette with bright ring colors feels disjointed. Research Whoop, Apple Fitness, Strava palettes. Pick 6 decisions: background, cards, accents, ring colors, text hierarchy, status colors. Keep premium, warm, not cold. Apply via `.card()` ViewModifier + Theme constants across ALL views in one cycle. Not iterative.

### P1: Chat UI Evolution
- [ ] **Message bubbles** — Replace plain text with user/AI message bubbles. Pure view-layer change.
- [ ] **Typing indicator** — Animated dots during AI thinking/classification phase.
- [ ] **Tool execution feedback** — Show "Looking up food...", "Checking workout history..." during Tier 2-3 execution. Needs state machine integration.

### P1: Food DB Enrichment to 1,500
- [ ] **Add ~300 foods** — Focus on most-searched-but-not-found. Indian restaurant meals, fast food combos, common branded items. Cross-reference USDA. JSON-only, zero code risk.

### P2: Meal Planning Dialogue
- [ ] **"Plan my meals for today"** — Iterative suggestion flow: suggest breakfast → confirm → suggest lunch. Needs `awaitingMealPlan` phase in ConversationState. Top failing query.

### P2: AIChatView ViewModel Extraction
- [ ] **Extract logic from AIChatView (400+ lines)** — Do alongside chat UI work (bubbles, typing indicators). Move business logic to AIChatViewModel. Not standalone refactoring.

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
- [x] LLM intent classifier + streaming
- [x] LLM presentation layer for info queries
- [x] Parallel tool execution
- [x] bestQuery flows through pipeline
- [x] Plant points: NOVA, aliases, processed exclusion, spice blends, 75 dishes
- [x] Data model: saved_food rename, source column, meal_log flattened, calorie target deduplicated
- [x] Food diary: sort chips, reorder, copy all, edit time/macros, detail view
- [x] Hevy import, workout share, save button, warmups
- [x] Weight: 90-day trend, outlier detection, gap guard, staleness nudges, manual entry priority
- [x] Weight: unit preference respected, WeightTrendService consolidation
- [x] Workout: finish sheet fix, rest timer
- [x] Profile fields in goal page + dashboard nudge
- [x] Code improvement: 12 cycles, 12 files decomposed, ~2800 lines redistributed
- [x] 743 tests
