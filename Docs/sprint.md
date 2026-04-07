# Sprint Board

## In Progress

_(pick from Ready)_

## Ready

### P0: AI Chat Quality — NEVER DONE (highest priority, always improve)
- [x] **Harness compensates for 1.5B model** — Fixed: non-food blocklist, double-execution bug, eval test tool names updated
- [ ] **Eval harness 97→150+** — Add: ambiguous queries ("I had something light"), typos ("log chiken"), multi-turn ("also add rice"), tool-call format validation, response quality scoring, Indian food coverage, workout conversation flows.
- [x] **Improve intent detection** — "log exercise"→workout, "what should I eat"→food suggestions in Swift (LLM scores 40% on these)
- [ ] **Better context injection** — LLM needs the RIGHT data, not ALL data. Trim context to most relevant info. Include user's recent actions. Show what changed since last message.
- [ ] **Response quality gate v2** — Check: does response actually answer the question? Does it use the data provided? Is it actionable? Score and replace if low quality.
- [ ] **Test on real conversations** — Create 20 realistic multi-turn conversation scripts. Run through the system. Log where it fails. Fix the worst failures.
- [ ] **Improve fallback responses** — When LLM produces garbage, the fallback should be smart: suggest specific actions based on screen + user data, not generic "try asking about...".

### P1: Enrich Tools + Improve AI Tool Use
- [ ] **Spell correction from food DB** — Instead of hardcoded dictionary, build correction candidates from foods.json names (1004 foods). Levenshtein distance matching against actual DB entries. Scalable.
- [ ] **Tool confirm-before-action** — Tools that write data (log_food, log_weight, mark_supplement) should return a confirmation prompt first, not execute immediately. "Log 2 eggs (140 cal)? Say yes to confirm."
- [ ] **Enrich food tools** — Add: get_recent_foods (what user eats often), get_macro_balance (P/C/F ratio vs targets), get_food_history(date) (what was eaten on a specific day).
- [ ] **Enrich exercise tools** — Add: get_last_session(exercise) (sets/reps/weight from last time), get_volume_trend(exercise) (total volume over time), get_body_part_split (which parts trained this week).
- [ ] **Enrich weight tools** — Add: get_weight_history_chart (data points for inline display), compare_weeks (this week vs last week avg).
- [ ] **Tool response formatting** — Tool results should be structured enough that AI chat can present them nicely. Return data + suggested display, not just flat strings.
- [ ] **Log food from tool result** — When get_nutrition returns food info, offer "[LOG_FOOD: name]" so user can say "yes log it" and it opens the sheet.
- [ ] **Eval: tool-call accuracy** — Add 20+ eval tests: given user message, does the right tool get called with right params? Test ambiguous cases.

### P2: AI Chat Quality
- [ ] **Better system prompt for tool selection** — The model needs clearer instructions on WHEN to call a tool vs respond naturally. Add examples of both.
- [ ] **Conversation context in tool calls** — Pass recent conversation to tool handlers so they can give contextual responses (e.g., "you asked about protein earlier, here are high-protein options").
- [ ] **Handle tool failures gracefully** — When a tool returns .error, the AI should explain and suggest alternatives, not just show the error.
- [ ] **Reduce hallucination** — Add post-response check: if LLM mentions specific numbers, verify they match tool output. Flag mismatches.

### P3: Traditional UI Improvements
- [ ] **Saved meals (one-tap re-log)** — Save multi-item meals as a group for quick re-logging.
- [ ] **Time-of-day food search boost** — Morning: coffee/oats, evening: protein/dinner items.
- [ ] **Quick-add raw calories** — "Just enter 500 cal" button for eating out.
- [ ] **Workout streak display** — Show current + longest streak on Exercise tab (logic already in WorkoutService.workoutStreak()).

### Blocked (needs device)
- [ ] **MQ-1: Test tool-calling models** — Hermes-3-Llama-3.2-1B for structured JSON.
- [ ] **MQ-2: Grammar-constrained sampling** — llama.cpp grammar for valid JSON.
- [ ] **Metal GPU acceleration** — b7400 xcframework ready, needs A19 Pro test.

## Done

- [x] TC-1: ToolSchema + ToolRegistry
- [x] TC-2: SpellCorrectService
- [x] TC-3: JSON tool-call parser
- [x] SVC-1-7: All 8 services (Food, Weight, Exercise, SleepRecovery, Supplement, Glucose, Biomarker)
- [x] WIRE-1: 20 tools registered
- [x] WIRE-2: System prompt injects tool schemas
- [x] WIRE-3: AIChatView uses ToolRegistry.execute()
- [x] WIRE-4: Block health questions
- [x] WIRE-5: Smart workout fallback
- [x] TC-11/12: Pre/post tool hooks
- [x] TC-14: Screen-aware tool filtering
- [x] Multi-turn workout accumulation
- [x] Eval harness 97 test methods
- [x] Flaky session tests fixed
- [x] FEAT-001: Calorie estimation
- [x] BUG-001: Calories left
- [x] Workout streak logic
- [x] Docs rewrite
