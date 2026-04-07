# Sprint Board

## In Progress

_(pick from Ready)_

## Ready

### P0: AI Chat Quality — NEVER DONE (highest priority, always improve)
- [x] **Harness compensates for 1.5B model** — Fixed: non-food blocklist, double-execution bug, eval test tool names updated
- [ ] **Eval harness 97→150+** — Add: ambiguous queries ("I had something light"), typos ("log chiken"), multi-turn ("also add rice"), tool-call format validation, response quality scoring, Indian food coverage, workout conversation flows.
- [x] **Improve intent detection** — "log exercise"→workout, "what should I eat"→food suggestions in Swift (LLM scores 40% on these)
- [x] **Better context injection** — Base context already compact (4 lines). Tool consolidation reduced prompt from 12→6 tools. Sufficient for now.
- [x] **Response quality gate v2** — Done: catches refusals, mangled JSON, question-repeating, context regurgitation
- [ ] **Test on real conversations** — Create 20 realistic multi-turn conversation scripts. Run through the system. Log where it fails. Fix the worst failures.
- [x] **Improve fallback responses** — Done earlier: data-aware fallbacks use FoodService/WeightServiceAPI/ExerciseService

### P1: Enrich Tools + Improve AI Tool Use
- [x] **Spell correction from food DB** — Done: Levenshtein distance matching against 1004 food names + hardcoded fallback
- [x] **Tool confirm-before-action** — log_food opens FoodSearchView (already confirms), log_weight now asks "Say yes to confirm"
- [x] **Enrich food tools** — food_info now shows macro balance vs targets + top protein when protein is low
- [x] **Enrich exercise tools** — exercise_info now shows last weight + streak alongside progressive overload
- [x] **Enrich weight tools** — weight_info includes trend + goal + body comp from describeTrend()
- [x] **Tool response formatting** — All tools now return user-friendly text with suggestions, not raw data
- [x] **Log food from tool result** — food_info already shows "Say 'log [name]' to add it" after nutrition lookup
- [x] **Eval: tool-call accuracy** — 144 eval tests + 100-query LLM eval (food 100%, questions 40%, exercise 13%, weight 20%)

### P2: AI Chat Quality
- [x] **Better system prompt** — Done: LOGGING/QUESTION/CHAT framework, 7 examples, 6-tool limit
- [ ] **Conversation context in tool calls** — Pass recent conversation to tool handlers
- [x] **Handle tool failures** — Done: data-aware fallbacks using actual services
- [ ] **Reduce hallucination** — Post-response check: verify numbers match tool output

### P3: Traditional UI Improvements
- [ ] **Saved meals (one-tap re-log)** — Save multi-item meals as a group for quick re-logging.
- [x] **Workout streak display** — Flame icon + "X week streak" + "Best: Yw" above consistency chart
- [x] **Time-of-day food search boost** — FoodSearchView now uses FoodService.searchFood (includes time boost + spell correction)
- [ ] **Quick-add raw calories** — "Just enter 500 cal" button for eating out.

### Next: Run Qwen3 eval and compare
- [x] **Qwen3-1.7B eval** — Food Logging: 30% (vs Qwen2.5 100%). Qwen3 is WORSE. Keeping Qwen2.5.

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
