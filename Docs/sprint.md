# Sprint Board

Focus: **AI Chat LLM-First Pipeline — Revised Architecture.** Address owner feedback on design doc #65, then implement multi-stage LLM pipeline with specialized prompts. Food logging must always confirm before writing.

## Blocker

**Design doc #65 (PR #112) has 3 unaddressed review comments from the owner.** The feedback fundamentally redirects the architecture — not just pipeline reorder, but a redesigned flow with specialized per-domain prompts and proper state transitions. Revising the doc is the #1 priority this sprint.

Owner feedback summary:
1. Remove A/B testing — app is fully local, no telemetry possible
2. The problem isn't the StaticOverrides list, it's the flow design. Need proper states: normalize → intent clarification → specialized extraction → confirmation. Research how production chat systems handle this.
3. Classification + data extraction errors persist even on clear input. Break the single classifier prompt into multiple specialized prompts (food extraction, exercise extraction, etc.) — even if it means multiple LLM passes.

## In Progress

_(pick from Ready)_

## Ready

### SENIOR — Unblock First

- [ ] **#120 Revise design doc #65 (PR #112)** — Address all 3 owner review comments. Remove A/B testing. Research multi-stage LLM pipeline patterns (intent → domain-specific slot extraction → confirmation). Propose specialized per-domain prompts instead of one unified classifier. Update PR #112, reply to each comment. This unblocks the entire sprint.

### SENIOR — Independent (no approval needed)

- [x] **#121 Food logging: confirm-first on all paths** — Fixed all 5 paths. 4 bypass paths fixed in original PR (Log Again + Quick open ManualFoodEntrySheet prefilled, Copy to Today alert, copy-yesterday in chat preview). 5th path (Copy previous day button in empty diary) fixed in follow-up commit 13dbfbe — now shows alert with calorie count before copying.
- [ ] **#122 AI Chat: research multi-stage pipeline patterns** — Research how production LLM chat systems handle intent → extraction → confirmation flows. Look at function-calling patterns, chain-of-thought extraction, multi-prompt architectures. Document findings in design doc #65 revision. This feeds directly into the doc revision.

### SENIOR — Contingent on Revised #65 Approval

These implement the revised design doc #65. Do not start until the revised PR #112 is approved.

- [ ] **#92 AI Chat: Reorder AIToolAgent pipeline (LLM-first)** — Implement the revised multi-stage pipeline per approved design. Run gold set eval before AND after.
- [ ] **#93 AI Chat: Prune StaticOverrides to essential patterns** — Scope TBD by revised design doc.
- [ ] **#94 AI Chat: Retire ToolRanker keyword scoring (Gemma path)** — Scope TBD by revised design doc.
- [ ] **#95 AI Chat: Specialized per-domain extraction prompts** — New: implement domain-specific prompts (food, exercise, weight, health) for slot extraction after intent classification. Multiple LLM passes if needed.

### JUNIOR

- [ ] **#96 Coverage: Pipeline refactor tests** — After pipeline changes land, ensure coverage targets hold (80% logic, 50% services).
- [ ] **#97 Bug hunting: Voice + chat end-to-end** — Exercise the new pipeline with voice transcription output. Focus on food logging confirmation flow.
- [x] **#123 Docs: Update state.md** — Verified: build 120, foods 1641 (json count), tests 1321+ (35 files), pipeline description current. Pipeline section update deferred until refactor lands.

### Design Docs (pending review)
- #65 Design: How should we structurally fix AI chat? — PR #112, `doc-ready`, **3 review comments unaddressed → revision needed**
- #66 Design: How to enrich images and youtube in exercises — `doc-ready`
- #74 Feature: Improve lab reports upload + LLM parsing — `doc-ready`

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

- [x] #121 (follow-up) Copy-previous-day button in empty diary now shows confirmation alert (13dbfbe)
- [x] #123 state.md verified accurate: build 120, foods 1641, tests 1321+ (35 files)

## Done (previous sprint)

- [x] #118 Food DB: +30 voice-friendly foods (1541→1571, commit c4aa9f0)
- [x] #116 AI Chat: Expand gold set eval to 55 queries (100% baseline accuracy)
- [x] #117 AI Chat: Voice input edge case hardening (10 new tests)
- [x] Food DB: +25 voice-friendly foods (1571→1596, commit 7d42b5f)
- [x] Food DB: +20 voice-friendly foods (1596→1616, commit 1cf1d78)
- [x] P0 #119: Show prefilled review form before logging food from chat (commit 2ce944f)
- [x] Fix: Route workout-set queries to AI pipeline (commit 2b25687)
- [x] TestFlight build 120 (commit 4d714bd)
