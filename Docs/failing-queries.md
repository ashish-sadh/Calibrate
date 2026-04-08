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
- [ ] **"I had 2 to 3 bananas"** — extractAmount doesn't handle ranges. Normalizer should rewrite to "log 3 banana". Test normalizer on-device.
- [ ] **"I ate three biryani"** — Word number + food. extractAmount has "three"→3 but may not work in all phrasings. Normalizer backup.
- [ ] **"set my goal to one sixty"** — Word number "one sixty" = 160. Normalizer should rewrite.
- [ ] **"I did yoga for like half an hour"** — "like half an hour" = 30 min. Normalizer should rewrite.

### Multi-Turn
- [ ] **Second meal item after recipe builder** — "Log dinner" → "rice and dal" → recipe opens. Then "also add broccoli" doesn't continue the meal.
- [ ] **"what about protein?" after food chat** — Normalizer needs to resolve from history. 2B model may not reliably infer.
- [ ] **"and yesterday?" after today's data** — Same pronoun resolution issue.
- [ ] **"plan my meals for today"** — Should be iterative: suggest breakfast → confirm → suggest lunch. Currently single response.

### Exercise
- [ ] **"Tell me my workout history"** — Should show recent workouts. Doesn't route correctly.

### Sleep
- [ ] **"How is my sleep quality last week"** — Should route to sleep_recovery and show weekly sleep data. Variants: "sleep last week", "how did I sleep this week", "sleep trend".

### Data Accuracy
- [ ] **"Daily summary"** — Reports wrong weight. AI service reads weight from different source than UI. Should use same service/query as the weight display on screen.

### Intent Misclassification
- [ ] **"I want to reduce fat"** — Should be food_info (diet advice). Currently misclassified as food logging, returns "log greek yogurt (0% fa)\<start_of_turn\>". Also leaks Gemma chat template tokens. Variants: "how to lose fat", "tips to cut fat", "I need to burn fat".

### Food Search Quality
- [ ] **"I had couple of bananas"** — "couple of" (no "a") should extract (2, "bananas"). Fixed in extractAmount but search may return wrong food if DB has "Gone Bananas" type entries. Singular-first search helps.
- [ ] **Kirkland Rotisserie Chicken for "100 gram of rice"** — Fixed by moving pendingMealName before food parsers. Verify no regression.

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
