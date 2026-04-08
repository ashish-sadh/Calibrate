# Sprint Board

Priority: improve AI chat architecture and close remaining parity gaps.

## In Progress

_(pick from Ready)_

## Ready

### P0: AI Pipeline Improvements
- [x] **Multi-turn via normalizer context** — Replace `pendingMealName`/`pendingWorkoutLog` state vars with normalizer + history context hints. Second "broccoli, quinoa and daal" should continue the meal without re-saying "log dinner".
- [x] **Normalizer accuracy tuning** — Test normalizer on 50+ messy queries. Tune prompt for Gemma 4 2B. Add eval cases for: "2 to 3 bananas", "one sixty lbs", "half an hour yoga".
- [x] **Multi-turn pronoun resolution** — "what about protein?" after food chat → normalizer resolves to protein query. Requires history context in normalizer prompt.
- [x] **Eval harness 300+** — Cross-domain, multi-turn, normalizer accuracy, tool ranking accuracy, streaming quality.

### P1: Food Logging Quality
- [x] **Multi-item meal continuation** — After "Log lunch" → "rice and dal" builds recipe, user should be able to say "also add broccoli" without re-triggering "Log lunch".
- [x] **Gram/unit parsing improvements** — "100 gram of rice" works (new NUMBER UNIT of FOOD pattern). Test: "200ml milk", "2 scoops protein", "half cup oats".
- [x] **Food search ranking** — Singular-first search added. Test that "bananas" → plain Banana, not "TJ's Gone Bananas". Consider name-length tiebreaker.

### P2: Streaming & Latency
- [ ] **Tool-first streaming** — For "how am I doing", execute food_info + weight_info in parallel, then stream presentation with real data. First token in ~2s.
- [ ] **Parallel rule check + normalize** — While normalizer runs (~3s), also check rules on raw input. If rules match, cancel normalizer.
- [ ] **Progressive multi-item disclosure** — For "rice and dal", show each found item as it's discovered, don't batch.

### P3: UI Polish
- [ ] **Saved meals (one-tap re-log)** — Save multi-item meals for quick re-logging from UI.
- [ ] **Accessibility pass** — VoiceOver labels on key screens.
- [ ] **Multi-turn meal planning** — "plan my meals for today" → iterative macro-aware suggestions. Gemma 4 only.

## Done

### Architecture (this sprint)
- [x] **Tiered pipeline** — Tier 0 (instant rules) → Tier 1 (normalizer) → Tier 2 (rule pick) → Tier 3 (tool-first+stream) → Tier 4 (pure stream)
- [x] **ToolRanker** — Keyword-based tool scoring with 19 profiles, `tryRulePick()`, `normalizePrompt()`, `extractParamsForTool()`
- [x] **AIToolAgent rewrite** — Single-pass streaming, then two-tier, then tool-first architecture
- [x] **Universal StaticOverrides** — Removed `isLargeModel` gate. All deterministic handlers work for both models.
- [x] **Handler ordering fix** — Moved view-state handlers, multi-turn handlers, food/weight/activity parsers BEFORE Gemma pipeline
- [x] **20s LLM timeout** — All LLM calls have timeout, fallback to screen-appropriate text
- [x] **Early JSON termination** — Bracket-counting in LlamaCppBackend stops generation as soon as JSON is complete
- [x] **Spell correction in findFood()** — SpellCorrectService.correct() added to food search chain
- [x] **Singular-first food search** — "bananas" searches "banana" first for better matches
- [x] **extractAmount "NUMBER UNIT of FOOD"** — Handles "100 gram of rice", "2 cups of dal"
- [x] **Bulk food "piece" filtering** — Nuts, grains, powder, dal, rice don't get misleading "piece" unit
- [x] **food_info macro focus** — query:"protein"/"carbs"/"fat" returns focused response
- [x] **Body fat/BMI validation** — bf >= 3 && <= 60, bmi >= 12 && <= 60
- [x] **Tool name parens fix** — `parseToolCallJSON` strips `()` from tool names
- [x] **Empty placeholder removal** — UI action responses don't leave empty chat bubbles
- [x] **"log exercise" handler** — Added before Gemma pipeline, triggers pendingWorkoutLog

### Previous sprints
- [x] Dual-model architecture (SmolLM + Gemma 4)
- [x] Screen bias removal
- [x] 19 consolidated tools with JSON tool-calling
- [x] Gemma 4 integration (xcframework, Metal GPU)
- [x] Meal/exercise logging flows
- [x] Gram-based food logging
- [x] Body composition tracking
- [x] 212+ eval tests + 100-query LLM eval
- [x] All P0/P0.5/P2 parity gaps closed
