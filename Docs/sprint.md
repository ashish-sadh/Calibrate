# Sprint Board

Priority: LLM-first AI chat — remove hardcoded strings, use LLM for intent detection + tool calling.

## In Progress

_(pick from Ready)_

## Ready

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
- [ ] **Multi-turn context** — Pass last 2-3 tool results in history so LLM can reference prior data.
- [ ] **Error recovery** — Detect wrong tool/bad params, show "could you rephrase?" instead of wrong action.
- [ ] **Latency optimization** — Target: first token in <2s for info queries, <1s for logging confirmations.

### P1: Workout History & Editing
- [ ] **Manual workout entry** — "Add Past Workout" button on workout tab. Pick date, name exercises, enter sets/reps/weight.
- [ ] **Edit existing workout** — Tap workout in history → edit sets, reps, weight, exercise order.
- [ ] **Edit workout name & notes** — Allow renaming from detail view.
- [ ] **Delete individual sets** — Swipe-to-delete on individual sets.

### P2: Presentation Quality
- [ ] **LLM presentation for ALL responses** — Every response conversational. No raw data dumps.
- [ ] **Streaming everywhere** — Tokens appear as LLM generates. No "thinking..." delays.
- [ ] **Context-aware responses** — Time of day, progress vs goal influence tone.

### P2: Salad Bowl / Custom Meal Builder
- [x] **Salad base templates** — 5 templates seeded with ingredients.
- [x] **Recent ingredients in picker** — Already implemented.
- [x] **Category tabs in ingredient picker** — Horizontal chips for browsing.
- [ ] **Ingredient persistence** — Store per-ingredient macros for recipe rebuilding.

### Ongoing: Code Improvement Loop
Autonomous refactoring. Run `code-improvement.md`. Principles in `Docs/principles/`. Log in `Docs/code-improvement-log.md`.

- [ ] **Continue file decomposition** — Files over 700 lines still need splitting (CycleView 633, GoalView 557, StaticOverrides 533, ToolRanker 530).
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
