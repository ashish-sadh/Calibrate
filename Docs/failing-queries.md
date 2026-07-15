# Failing Queries — AI Chat Fix Backlog

Real queries that don't work well. Fix systematically, then move to Fixed.

**Rules for fixing:**
- Fix the CATEGORY, not just the exact query
- Tier 0 (instant rules/parsers) is best — no latency
- Tier 1 (normalizer) handles messy variants — ~3s latency
- Add eval harness tests for the query AND 3+ variants
- Test both model paths before marking fixed

## Failing

## Fixed

### Cycle (2026-05-03)
- [x] **"when did I last take my ozempic shot"** — Added `medication_info` tool backed by `MedicationService.lastDoseTime`/`recentDoseHours`. ToolRanker profile beats `log_medication` on history-framed queries ("when did", "last dose", "last time i took") via high-score phrase triggers + antiKeywords ("when", "last", "did", "time") on `log_medication`. Router prompt updated. 7/7 routing cases pass. Variants: "last time i took insulin", "when did i inject ozempic", "how often do i take mounjaro", "medication history".

### Cycle (2026-05-03)
- [x] **"did I miss any magnesium doses"** — `supplement_insight` routing fix. Added `("did i miss", 5.5)`, `("did i forget to take", 5.5)`, `("forget to take", 4.0)`, `("miss any", 3.5)`, `("miss", 2.0)` triggers. Net score 4.5 beats `mark_supplement` 2.0 even with -1 logBoost from "did" being in logVerbs. Variants: "did I forget to take magnesium", "miss any zinc doses".

### Cycle 8666–8789
- [x] **"how much fiber did I eat today"** — `food_info` handler now checks `query.contains("fiber")` and returns `n.fiberG` from the daily nutrition summary, with a 25g default target. `02b6c27`. Variants: "how much sodium today", "what's my sugar intake".
- [x] **"am I hitting my protein goal"** — `food_info` handler compares today's protein against `goal.proteinGoal` (user-set) or macro-breakdown target, showing a % progress line with suggestions for top protein foods. `31be180` (#284), `eeab10b` (#441). Variants: "did I hit my fat goal today", "how far off am I from my protein target".

### Cycle 8581 (builds 196–197)
- [x] **"of" connector in unit parsing** — "100g of oats", "200ml of milk", "8oz of chicken" returned food="of oats/of milk". Skip leading "of" after extracting unit. `d265f85` (#497)
- [x] **Decimal Nx multiplier phrases** — "1.5x rice", "0.5x oats", "2.5x whey" now parsed as serving multipliers in extractAmount. `14b6bb9` (#559)
- [x] **Food-aware cup/tbsp/tsp conversion** — "1.5 cups of rice" → 277.5g (185g/cup), "half cup oats" → 40g (80g/cup). Uses RawIngredient.gramsPerCup density table instead of flat 240g. `d034ab5` (#552)

### Earlier cycles
- [x] "No, I had the other chicken instead" — `IntentClassifier.deleteEditTriggers` + recent-entries context on correction turns. Variants: "Actually I had salmon, not chicken".
- [x] "set my calorie goal to 2000" — StaticOverrides matches calorie/caloric/cal goal/target/limit/budget → `WeightGoal.calorieTargetOverride`. Variants: "calorie budget 2000", "my calorie limit is 1500".
- [x] "how many calories did I eat last Tuesday" — `AIRuleEngine.weekdayDateString` parses last/past/on weekday refs → `historicalDaySummary`. Variants: "what did I eat on Monday", "calories last Saturday".
- [x] "I had 2 to 3 bananas" — extractAmount handles "X to Y" ranges (takes higher).
- [x] "I ate three biryani" — extractAmount word→number already handled.
- [x] "set my goal to one sixty" — resolveWordNumbers() converts "one sixty"→160.
- [x] "I did yoga for like half an hour" — trailing duration parser handles "for like X".
- [x] Second meal item after recipe builder — meal continuation handler prepends to pendingRecipeItems.
- [x] "what about protein?" after food chat — topic continuation in StaticOverrides.
- [x] "and yesterday?" after today's data — StaticOverrides topic continuation.
- [x] "plan my meals for today" — planningMeals state phase with suggestions/pagination.
- [x] "Tell me my workout history" — exercise_info shows recent workouts from HealthKit.
- [x] "How is my sleep quality last week" — sleep_recovery accepts period param, 7-day average.
- [x] "Daily summary" — dailySummary() was using .last on DESC array; changed to .first.
- [x] "I want to reduce fat" — StaticOverrides catches diet/fitness advice, personalized macro advice.
- [x] "I want to estimate calories for samosa" — StaticOverrides nutrition estimation handler.
- [x] "I had couple of bananas" — singular-first search + LENGTH tiebreaker.
- [x] "100 gram Rice and 2 cups of daal" → Kirkland Chicken — pendingMealName before food parsers.
- [x] "suggest me workout" — Hardcoded handler, 12 phrasings.
- [x] "I did yoga today" — Activity parser with duration.
- [x] "how many workouts this week" — Rule engine + streak.
- [x] "what's healthy for dinner" — suggestMeal + macros.
- [x] "I had a cheat meal" — pendingMealName flow.
- [x] "how much sugar today" — Shows carbs + note.
- [x] "am I making progress" — fullDayContext.
- [x] "should I eat more today" — Cross-domain.
- [x] "I feel tired" — Cross-domain sleep+food.
- [x] "how is my protein" — StaticOverride + food_info tool with query:"protein".
- [x] "body fat is 3" — Validation fixed (>3 → >=3).
- [x] "log exercise" → "Logging food..." — Added exercise trigger before Gemma pipeline.
- [x] "Unknown tool: sleep_recovery()" — parseToolCallJSON strips `()` from tool names.
- [x] "what('s) my weight trend" → weight_trend_prediction — tool RENAMED goal_weight_eta (2026-07-15); the literal name captured trend-info questions. Old name aliased → weight_info in parseResponse.
- [x] "Hello how are you" / "How are you doing" / "Good morning" — burned a 1.5-38s LLM/presentation turn per greeting (field telemetry). StaticOverrides greeting set broadened + normalized.
- [x] "How is my sleep" → log_sleep (hallucinated tool, field 2026-04-28) — aliased → sleep_recovery.
- [x] "I plan to have idli tomorrow" → {"tool":"chat"} — OUR OWN prompt example taught a nonexistent tool (3 field failures). Example rewritten as plain text.
- [ ] "how much did I bench" → start_workout (want exercise_info) — deterministic misroute, greedy decode.
- [ ] "remove rice from lunch" → delete_food (want edit_meal) — despite verbatim few-shot example.
- [ ] supplement status vs insight boundary ("show my supplement adherence" → supplements, want supplement_insight) — 4 cases, adjacent tools.
- [ ] "open supplements"/"open biomarkers"/"go to glucose" → data tool (want navigate_to) — "open X" rule loses to tool-name match.
- [ ] cycle_biomarker_correlation captured by cross_domain_* on 5 phrasings despite verbatim example ("does my iron drop during my period").
