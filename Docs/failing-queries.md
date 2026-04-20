# Failing Queries — AI Chat Fix Backlog

Real queries that don't work well. Fix systematically, then move to Fixed.

**Rules for fixing:**
- Fix the CATEGORY, not just the exact query
- Tier 0 (instant rules/parsers) is best — no latency
- Tier 1 (normalizer) handles messy variants — ~3s latency
- Add eval harness tests for the query AND 3+ variants
- Test both model paths before marking fixed

## Failing

### Micronutrient Queries
- **"how much fiber did I eat today"** — CATEGORY: micronutrient queries (fiber, sodium, sugar, vitamins). `food_info` handler exposes cal/protein/carbs/fat per entry but fiber_g is only used in the nutrition estimation flow (Gemma 4 food lookup), not stored per logged entry. Query routes to `food_info(query:"fiber today")` but the handler returns a daily macro summary that omits fiber — user gets a non-answer. Fix tier: 2 (store fiber_g on FoodEntry, surface in `food_info` daily summary). Variants: "did I get enough fiber this week", "how much sodium today", "what's my sugar intake".

### Informal Corrections / Replacements
- **"No, I had the other chicken instead"** — CATEGORY: correction-as-replacement. The word "instead" (and "no, i had") is absent from `IntentClassifier.deleteEditTriggers`, so `needsRecentEntries()` returns false and the recent-entries context block is not injected. Without that block, the LLM sees "I had the other chicken" naked, classifies it as `log_food("the other chicken")`, and creates a duplicate entry rather than replacing the prior one. Fix tier: 0 (add "instead", "no, i had", "actually i had" to `deleteEditTriggers`). Variants: "Actually I had salmon, not chicken", "Wait, it was 2 eggs not 3", "No, that was lunch not dinner".

### Non-Weight Goal Setting
- **"set my calorie goal to 2000"** — CATEGORY: macro/calorie goal setting. `set_goal` tool is weight-only (`target` = kg or lbs). The LLM calls `set_goal(target:"2000", unit:"kcal")` but the handler converts to kg and rejects because 2000 kg fails the `targetKg < 20 || targetKg > 200` guard → error message. User receives a confusing "outside valid range" error. Same failure for "set my protein goal to 150g", "set my step goal to 10000". Fix tier: 2 (extend set_goal or add calorie_goal/macro_goal tool; teach the IntentClassifier to distinguish weight vs. macro goals). Variants: "I want to eat 1800 calories a day", "set my protein target to 120g".

### Historical Date Queries
- **"how many calories did I eat last Tuesday"** — CATEGORY: specific past-date lookups. `food_info` handler only has two date windows: today ("daily summary") and this week ("weekly summary"). A query like "last Tuesday" or "two days ago" routes to `food_info(query:"last Tuesday")` but the handler has no date-parsing logic — it returns today's macros or an empty/wrong result. Fix tier: 2 (add date parsing to `food_info` handler — convert "last Tuesday", "yesterday", "two days ago" to an absolute date before querying FoodEntry records). Variants: "what did I log two days ago", "calories on Saturday", "last week Monday".

### Macro Goal Progress Queries
- **"am I hitting my protein goal"** — CATEGORY: macro goal tracking / goal-vs-actual comparison. There is no protein goal in the data model (`WeightGoal` stores only target weight). The system prompt routes protein queries to `food_info`, which shows today's protein intake, but there is no goal to compare against — so the response is just "you had X g protein" with no benchmark. User question goes half-answered. Fix tier: 3 (add macro targets to user prefs; expose them in `food_info` so it can compare intake vs. goal). Variants: "did I hit my fat goal today", "am I on track for carbs", "how far off am I from my protein target".

### Normalizer / Natural Language
- [x] **"I had 2 to 3 bananas"** — FIXED: extractAmount now handles ranges "X to Y" by taking higher number.
- [x] **"I ate three biryani"** — FIXED: extractAmount already handles "three"→3. Verified with eval test.
- [x] **"set my goal to one sixty"** — FIXED: resolveWordNumbers() converts "one sixty"→160 before regex matching.
- [x] **"I did yoga for like half an hour"** — FIXED: trailing duration parser handles "for like half an hour" → 30 min.

### Multi-Turn
- [x] **Second meal item after recipe builder** — "Log dinner" → "rice and dal" → recipe opens. Then "also add broccoli" doesn't continue the meal. FIXED: meal continuation handler prepends to pendingRecipeItems.
- [x] **"what about protein?" after food chat** — Normalizer needs to resolve from history. 2B model may not reliably infer. FIXED: topic continuation in StaticOverrides.
- [x] **"and yesterday?" after today's data** — FIXED: Added to StaticOverrides as topic continuation pattern.
- [x] **"plan my meals for today"** — FIXED: planningMeals state phase with iterative suggestions, number selection, "more" for pagination, topic switch detection.

### Exercise
- [x] **"Tell me my workout history"** — FIXED: exercise_info now shows recent workouts from HealthKit.

### Sleep
- [x] **"How is my sleep quality last week"** — FIXED: sleep_recovery now accepts period param, fetches 7-day sleep average from HealthKit.

### Data Accuracy
- [x] **"Daily summary"** — FIXED: dailySummary() was using .last (oldest) on DESC-sorted array. Changed to .first (most recent).

### Intent Misclassification
- [x] **"I want to reduce fat"** — FIXED: StaticOverrides catches diet/fitness advice queries. Returns personalized macro advice instead of falling through to LLM.
- [x] **"I want to estimate calories for samosa"** — FIXED: StaticOverrides nutrition estimation handler extracts food name and looks up in DB.

### Food Search Quality
- [x] **"I had couple of bananas"** — FIXED: singular-first search + LENGTH tiebreaker ranks plain Banana first.
- [x] **Kirkland Rotisserie Chicken for "100 gram of rice"** — FIXED: pendingMealName before food parsers. Verified, no regression.

## Fixed

- [x] "suggest me workout" — Hardcoded handler, 12 phrasings
- [x] "I did yoga today" — Activity parser with duration
- [x] "how many workouts this week" — Rule engine + streak
- [x] "what's healthy for dinner" — suggestMeal + macros
- [x] "I had a cheat meal" — pendingMealName flow
- [x] "how much sugar today" — Shows carbs + note
- [x] "am I making progress" — fullDayContext
- [x] "should I eat more today" — Cross-domain
- [x] "I feel tired" — Cross-domain sleep+food
- [x] "how is my protein" — StaticOverride + food_info tool with query:"protein"
- [x] "body fat is 3" — Validation fixed (>3 → >=3)
- [x] "log exercise" → "Logging food..." — Added exercise trigger before Gemma pipeline
- [x] "100 gram Rice and 2 cups of daal" after "Log lunch" → Kirkland Chicken — pendingMealName moved before food parsers, prefix stripping, per-item extractAmount
- [x] "Unknown tool: sleep_recovery()" — parseToolCallJSON strips `()` from tool names
