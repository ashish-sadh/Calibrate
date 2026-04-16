# Sprint Board

Focus: **Smart Units Saturation + Pipeline Wrap-Up.** Multi-stage pipeline is shipped (6/8 tasks complete). This sprint: fix the P0 bug, merge remaining pipeline work, and saturate Smart Units per product focus. Smart Units is the #1 user complaint — every food needs natural default units (dosa→piece, milk→ml, rice→cup, eggs→piece).

## Regression Gate

**55-query gold set at 100% baseline.** Any AI change MUST run gold set eval before AND after.

## In Progress

_(pick from Ready)_

## Ready

### P1 — Pipeline Wrap-Up (finish the old sprint)

- [ ] **#130 Merge PR #136** — Swift validation between stages is implemented (branch `130-swift-validation-between-stages`, PR #136). Review, merge, close issue.

### P1 — Smart Units Saturation (product focus)

- [ ] **Smart Units in AI chat** — Verify AI chat uses smart units when logging. "log 2 dosas" should use pieces, not grams. "log a bowl of dal" should use cups. Test across food categories and fix any gaps in the extraction/confirmation pipeline.

### P2 — Design Docs

- [x] **#74 Design doc: Lab reports + LLM parsing** — Done. Branch `design/74-lab-reports-llm`, doc at `Docs/designs/74-lab-reports-llm.md`, PR #114 open for review.

### Design Docs (approved — not this sprint)
- #66 Design: How to enrich images and youtube in exercises — `doc-ready`, `approved`
- #133 Design-impl: Exercise image/video enrichment — research task

---

## Permanent Tasks (never remove — always pick from these when nothing else is queued)

**Before picking a task, read `Docs/roadmap.md` → "Now" items in the relevant domain. Work on what advances the current phase.**

### AI Chat Architecture & Quality (always ongoing)
Equally important pillar. Prefer architectural improvements over keyword additions.

- [ ] **State machine refactor** — Replace scattered pendingMealName/pendingWorkout state vars with a proper conversation state machine. States: idle -> classifying -> executing_tool -> confirming -> logging. Clear transitions, no dangling state.
- [ ] **Prompt consolidation** — Single source of truth for tool schemas, examples, context injection. Measure token count, compress.
- [ ] **Multi-turn reliability** — Eliminate bugs where context is lost between turns. Test: 3-turn meal logging, 3-turn workout building, topic switching mid-conversation.
- [ ] **Natural freeform logging** — "log for breakfast 2 eggs and spinach and bread and coffee with 2% milk with protein powder and creatine" or "log chipotle bowl with 800 calories" -> AI parses everything, asks clarifying questions, does macro calculations, logs it.
- [ ] **Meal planning** — "plan my meals for today" -> iterative suggestions based on remaining macros + history.
- [ ] **Workout split builder** — "build me a PPL split" -> multi-turn designing across sessions.
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
- [ ] **Integration-style tests** — Test multi-step flows (parse -> resolve -> log -> confirm) end-to-end.

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

- [x] #135 Bug: "How many calories left" answers food search — fixed isDiaryQuery guard in food_info handler. Regression test added.
- [x] #142 P0 Bug: Fiber always shows 0g in diary — RecentEntry was missing fiberG field; SQL queries omitted fiber_g; FoodSearchView hardcoded fiberG: 0. Fixed all three.
- [x] #131 Update state.md + roadmap — 6-stage pipeline documented, build 123, 1424+ tests, food count updated. AI Chat reliability marked DONE in roadmap.
- [x] Smart Units audit: 340 foods improved — Indian flatbreads, chaat, condiments, curries, beverages, burgers/wraps, large fruits, berries, whole vegetables now get natural units. 1,311→971 foods at "serving".
- [x] Food DB enrichment: 1,913→1,927 (+14 foods) — kanda bhaji, mooli paratha, ribbon pakoda, seedai, shikanji, egg paratha, chicken paratha, akki roti, makki di roti, pyaaz kachori, stuffed capsicum, lauki sabzi, arbi masala, bajra khichdi.

## Done (previous sprint — Multi-Stage LLM Pipeline)

- [x] #129 Stage 0+1: Wire pipeline skeleton in AIToolAgent
- [x] #92 Stage 2: Intent classifier (classification-only prompt)
- [x] #95 Stage 3: Domain-specific extraction prompts
- [x] #93 Prune StaticOverrides to ~10 essential patterns (Gemma path)
- [x] #94 Retire ToolRanker keyword scoring (Gemma path)
- [x] #96 Coverage: Pipeline refactor tests
- [x] Smart Units: rice→cup, protein powder→scoop, pasta/noodles→cup, dal/beans→cup
- [x] Smart Units: portionText fixes (bread→slices, pizza→slices, soup→bowls, momos→pieces)
- [x] Food DB: 1,641→1,927 (+286 foods across 5 junior cycles)
- [x] Synonym expansion: +24 South Indian, Middle Eastern, Bengali, Tamil terms
