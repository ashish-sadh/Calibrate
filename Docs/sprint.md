# Sprint Board

Priority: LLM-first AI chat — remove hardcoded strings, use LLM for intent detection + tool calling.

## In Progress

_(pick from Ready)_

## Ready

### P0: Unit Switching (LB/KG) Broken + Missing Units
- [x] **LB/KG setting doesn't update UI** — Fixed: WeightViewModel.loadEntries() now refreshes weightUnit from Preferences. Test added.
- [x] **Support all unit options across the app** — Fixed: exercise weights, workout detail, volume, 1RM, body comp all respect LB/KG preference. DB stays in lbs, conversion at view boundaries.

### P0: LLM-Driven Intent + Tool Calling (CORE REDESIGN)

**Goal:** Replace ~1500 lines of hardcoded string matching with LLM-driven intent detection. The 2B model (Gemma 4) should decide intent and call tools via JSON — not keyword scoring.

**Architecture: Intent → SubIntent → Tool → Action**

```
User: "Log breakfast with 2% milk, eggs and toast"
  ↓
LLM classifies: intent=food_logging, subintent=multi_item_meal
  ↓  
LLM tool call: {"tool": "log_food", "items": [{"name": "2% milk"}, {"name": "eggs"}, {"name": "toast"}], "meal": "breakfast"}
  ↓
Execute: find each food → show confirmation UI → log
```

- [x] **LLM intent classifier prompt** — IntentClassifier.swift implemented with Gemma 4.
- [x] **Streaming intent detection** — Token streaming with word-by-word generation.
- [x] **Synthetic training data** — 16 test methods, 50+ assertions covering all tools, edge cases, LLM quirks. Fixed empty tool bug.
- [x] **Unified tool schema prompt** — 12 tools with compact function signatures (~250 tokens). 16 examples. delete_food + body_comp added.
- [x] **Remove StaticOverrides for intent routing** — Migrated all info queries (TDEE, protein, macros, calories, workout count, weekly comparison, workout suggestions) to ToolRanker/IntentClassifier. StaticOverrides 533→421 lines. Remaining handlers are deterministic commands (undo, delete, regex-parsed entries) that don't benefit from LLM.
- [x] **Multi-item food logging via LLM** — Comma-separated items from LLM now open recipe builder with all items pre-populated + DB macros.
- [x] **Confirmation UI for actions** — log_food opens FoodSearchView/RecipeBuilder (user confirms there), log_weight opens WeightEntry, start_workout opens ActiveWorkoutView. Delete has undo. No extra confirmation needed — existing UIs serve as confirmation gates.

### P1: Tool Quality + Prompt Engineering
- [x] **Tool calling accuracy eval** — 42 queries across all tools, 80%+ accuracy thresholds. 4 test methods by domain (food, weight, exercise, other).
- [x] **Prompt compression** — IntentClassifier prompt compressed 50% (35→17 lines). Tool list on one line, shorter examples.
- [x] **Multi-turn context** — streamPresentation receives conversation history (300 chars). LLM can reference prior responses.
- [x] **Error recovery** — Friendly error messages + tool name sanitization (strips "()" LLM quirk).
- [x] **Latency optimization** — Added pipeline timing instrumentation (logTiming per phase). Phase 1 rules are instant. Actual on-device measurement requires LLM eval.

### P1: Workout History & Editing
- [x] **Manual workout entry** — "Log Past Workout" button on workout tab. Opens ActiveWorkoutView with date picker, no timer. TemplatePreviewSheet extracted to unblock type checker.
- [x] **Edit existing workout** — Tap any set → edit weight/reps alert. WorkoutService.updateSet(). Handles duration exercises.
- [x] **Edit workout name & notes** — Menu option in detail view, alert with pre-populated fields, WorkoutService.updateWorkout().
- [x] **Delete individual sets** — Swipe-to-delete on sets in detail view. WorkoutService.deleteSet().

### P2: Presentation Quality
- [x] **LLM presentation for ALL responses** — Gemma: streaming LLM presentation. SmolLM: enhanced addInsightPrefix with 8 patterns. No more raw data dumps.
- [x] **Streaming everywhere** — Gemma: all info responses stream via respondStreamingDirect. SmolLM: instant prefixed data (can't stream reliably). "Thinking..." only shows during classification phase.
- [x] **Context-aware responses** — Tone hints in presentation prompt: morning=motivating, daytime=practical, evening=summary.

### P2: Salad Bowl / Custom Meal Builder
- [x] **Salad base templates** — 5 templates seeded with ingredients.
- [x] **Recent ingredients in picker** — Already implemented.
- [x] **Category tabs in ingredient picker** — Horizontal chips for browsing.
- [x] **Ingredient persistence** — Store per-ingredient macros for recipe rebuilding.

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
