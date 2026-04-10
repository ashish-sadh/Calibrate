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

- [ ] **LLM intent classifier prompt** — Design a compact (~100 token) system prompt for Gemma 4 that classifies user message into: `food_log`, `food_query`, `weight_log`, `weight_query`, `exercise_start`, `exercise_log`, `exercise_query`, `health_query`, `chat`. Returns JSON: `{"intent": "food_log", "sub_intent": "multi_item"}`. Test on 50+ synthetic queries.
- [ ] **Synthetic training data** — Generate 200+ realistic user messages across all intents. Include: "Log breakfast with 2% milk, egg and toast", "had a salad with chicken and avocado", "can you help me log my lunch", "I ate out at Chipotle", "how's my protein looking", "did I hit my calorie goal", "start push day", "I did 30 min yoga". Test each through the pipeline.
- [ ] **Unified tool schema prompt** — Design compact tool definitions for the LLM (~200 tokens for all tools). The model should see available tools and return JSON tool calls. Format: `{"tool": "log_food", "params": {"items": [...], "meal": "breakfast"}}`. Test tool selection accuracy on synthetic data.
- [ ] **Remove StaticOverrides for intent routing** — Keep StaticOverrides ONLY for instant commands (undo, delete, copy, barcode scan, greetings). Move ALL intent detection to LLM. Info queries, food logging, exercise — all through LLM.
- [ ] **Streaming intent detection** — Stream the LLM response. If first token is `{` → tool call JSON. If text → direct response. Already partially implemented in Phase 4 — extend to be the PRIMARY path, not fallback.
- [ ] **Multi-item food logging** — LLM parses "rice with dal and chicken" as 3 items. No more hardcoded "and" splitting or compound food exclusion lists. LLM understands context.
- [ ] **Confirmation UI for actions** — After LLM returns tool call, show brief confirmation before executing. "Log 2 eggs, toast, and milk for breakfast? ✓". Tap to confirm. Prevents wrong actions.

### P1: Tool Quality + Prompt Engineering
- [ ] **Tool calling accuracy eval** — Run 100 synthetic queries through Gemma 4. Measure: correct tool picked? Correct params extracted? Track accuracy per tool. Target: 85%+.
- [ ] **Prompt compression** — Current system prompt is ~500 tokens. Compress to ~200. Gemma 4 has 2048 context — every token matters. Remove redundant examples, use terse format.
- [ ] **Multi-turn context** — Pass last 2-3 tool results in history so LLM can reference: "you mentioned protein was low" or "you logged 1200 cal so far". Currently history only has Q/A text, not tool data.
- [ ] **Error recovery** — If LLM picks wrong tool or bad params, detect and retry. Show "I didn't understand, could you rephrase?" instead of wrong action.
- [ ] **Latency optimization** — Measure: intent detection time, tool execution time, presentation time. Target: first token in <2s for info queries, <1s for logging confirmations.

### P2: Presentation Quality
- [ ] **LLM presentation for ALL responses** — Every response should feel conversational. No raw data dumps. Even error messages should be natural.
- [ ] **Streaming everywhere** — User sees tokens appearing as LLM generates. No "thinking..." delays for simple queries.
- [ ] **Context-aware responses** — Time of day, progress vs goal, recent history influence tone. Morning: encouraging. Evening: summary-oriented. Over target: gentle nudge.

### P0: Workout Bugs (human-reported)
- [ ] **BUG: Save as Template skips completion share screen** — When "Save as template" toggle is on, the workout saves and dismisses immediately without showing the "Nice work!" completion sheet with share button.
- [ ] **Rest timer confusing / not optional** — Add a "Rest Timer" toggle at the top of active workout. Default OFF. When on, shows countdown between sets.

### P1: Workout History & Editing
- [ ] **Manual workout entry** — "Add Past Workout" button on workout tab.
- [ ] **Edit existing workout** — Tap a workout in history → edit sets, reps, weight.
- [ ] **Edit workout name & notes** — Allow renaming from detail view.
- [ ] **Delete individual sets** — Swipe-to-delete on individual sets.

### P2: Salad Bowl / Custom Meal Builder
- [x] **Salad base templates** — 5 templates seeded with ingredients.
- [x] **Recent ingredients in picker** — Already implemented.
- [x] **Category tabs in ingredient picker** — Horizontal chips for browsing.
- [ ] **Ingredient persistence** — Store per-ingredient macros for recipe rebuilding.

## Done (this sprint)
- [x] LLM presentation layer for info queries
- [x] Parallel tool execution
- [x] bestQuery flows through pipeline
- [x] Plant points: NOVA, aliases, processed exclusion, spice blends, 75 dishes
- [x] Data model: saved_food rename, source column, meal_log flattened, calorie target deduplicated
- [x] Food diary: sort chips, reorder, copy all, edit time/macros, detail view
- [x] Hevy import, workout share, save button, warmups
- [x] 743 tests
