# Failing Queries — AI Chat Fix Backlog

Real queries that don't work well. Fix systematically, then move to Fixed.

**Rules for fixing:**
- Fix the CATEGORY, not just the exact query
- Tier 0 (instant rules/parsers) is best — no latency
- Tier 1 (normalizer) handles messy variants — ~3s latency
- Add eval harness tests for the query AND 3+ variants
- Test both model paths before marking fixed

## Failing

### Normalizer / Natural Language
- [x] **"I had 2 to 3 bananas"** — FIXED: extractAmount now handles ranges "X to Y" by taking higher number.
- [x] **"I ate three biryani"** — FIXED: extractAmount already handles "three"→3. Verified with eval test.
- [ ] **"set my goal to one sixty"** — Word number "one sixty" = 160. Normalizer should rewrite.
- [ ] **"I did yoga for like half an hour"** — "like half an hour" = 30 min. Normalizer should rewrite.

### Multi-Turn
- [x] **Second meal item after recipe builder** — "Log dinner" → "rice and dal" → recipe opens. Then "also add broccoli" doesn't continue the meal. FIXED: meal continuation handler prepends to pendingRecipeItems.
- [x] **"what about protein?" after food chat** — Normalizer needs to resolve from history. 2B model may not reliably infer. FIXED: topic continuation in StaticOverrides.
- [x] **"and yesterday?" after today's data** — FIXED: Added to StaticOverrides as topic continuation pattern.
- [ ] **"plan my meals for today"** — Should be iterative: suggest breakfast → confirm → suggest lunch. Currently single response.

### Exercise
- [x] **"Tell me my workout history"** — FIXED: exercise_info now shows recent workouts from HealthKit.

### Sleep
- [x] **"How is my sleep quality last week"** — FIXED: sleep_recovery now accepts period param, fetches 7-day sleep average from HealthKit.

### Data Accuracy
- [ ] **"Daily summary"** — Reports wrong weight. AI service reads weight from different source than UI. Should use same service/query as the weight display on screen.

### Intent Misclassification
- [x] **"I want to reduce fat"** — FIXED: StaticOverrides catches diet/fitness advice queries. Returns personalized macro advice instead of falling through to LLM.

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
