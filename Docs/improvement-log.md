# Drift AI Improvement Log

Track of autonomous improvement cycles. Each entry = one cycle of the loop.

---

## Cycle · 2026-04-12 (Autopilot session, sprint post-review #18)

- **Muscle group icons (P2)**: Workout history cards now show body part chips (Chest, Back, Legs, etc.) with SF Symbol icons. Visual polish toward Boostcamp parity.
- **Proactive alerts (P1)**: Protein streak alert (3+ days below target) and supplement gap alert (3+ days not taken) on dashboard. Extends the overload alert pattern to nutrition and supplements.
- **Systematic bug hunting (P1)**: Found 3 P0 data-accuracy bugs via pipeline analysis: "calcium" matching calorie regex, integer JSON servings silently dropped, undo always deleting food. All fixed with regression tests. 942 tests.
- **USDA API design doc (P0)**: Written at Docs/usda-api-design.md. Architecture: offline-first + on-demand enrichment, opt-in toggle, usda_cache table, privacy analysis. Awaiting leadership decision on timeline.
- **AI chat workout intelligence (P0)**: "How's my bench progress?" now works via StaticOverrides + resolveExerciseName. Shows 1RM trend, session history, last weight. ToolRanker triggers added for progress/bench/squat/deadlift. exercise_info tool also enhanced. 939 tests.
- **Hardcoded unit audit (P0)**: Grep'd all .swift files for "lb"/"lbs". Fixed 7 files (6 views + 1 service) to use Preferences.weightUnit.convertFromLbs() instead of hardcoded lb. Closes stale preference pattern permanently.

---

## Cycle · 2026-04-12 (Autopilot session, sprint post-review #17)

- **Food diary inline editing**: DB food entries now allow macro override. "Edit macros" toggle pre-fills with computed values from servings, saves via updateFoodEntryMacros.
- **Meal hint passthrough fix**: parseFoodIntent correctly parsed mealHint ("log eggs for lunch" → lunch) but handleSingleFoodIntent never passed it to FoodSearchView. Added initialMealType param, threaded through all food search open sites.
- **Meal group re-log**: Long-press meal section header (Breakfast/Lunch/Dinner) → "Log All Again" or "Copy All to Today". Quick re-logging of recurring multi-item meals.
- **Workout unit fix**: History cards hardcoded "lb" for volume and best sets. Now uses Preferences.weightUnit with convertFromLbs.
- 936 total tests (+1 meal hint regression test).

## Cycle · 2026-04-12 (Autopilot session, continued)

- **Coverage sprint**: CycleCalculations 76.6%→93.6%, ExerciseService 47%→92%, AIToolAgent 48%→52.3%. Only IntentClassifier (63%) remains below threshold. 935 total tests.
- **Bug fixes**: Meal planning out-of-range number selection (was falling through to LLM), parseMultiFoodIntent empty query filter (was matching random DB entries for numeric-only parts like "2").
- **Chat typewriter animation**: Instant AI responses (Tier 0/1/2) now reveal text character-by-character. Streamed LLM responses unaffected. Uses creation timestamp to distinguish new vs existing messages.
- **Meal planning dialogue**: "plan my meals today" → iterative suggestions based on remaining calories/protein. planningMeals state phase, number selection, "more" pagination, topic switch detection, smart pills. 4 tests.
- **Product Review #16 (Cycle 535)**: Food DB to 1,500 shipped, meal planning built. 21% sprint velocity due to meal planning complexity. MFP acquired Cal AI, MacroFactor launched Workouts app. PR #9.

## Cycle · 2026-04-12 (Autopilot session)

- **Voice input prototype**: SpeechRecognitionService + mic button in AIChatView. On-device SFSpeechRecognizer, privacy-first. Streams partial results into chat text field. 6 tests. Go/no-go at next review.
- **Product Review #13 (Cycle 358)**: 5/6 sprint items delivered. Voice input elevated to P0 (3 reviews deferred). MFP acquired Cal AI + ChatGPT Health + Intent. Color harmony + chat UI evolution next. PR #4.
- **Product Review #11 (Cycle 199)**: Full competitive analysis — MFP acquired Cal AI, Whoop AI Strength Trainer, Boostcamp muscle viz. Agreed: 80% user-facing work next 20 cycles. PR #2 published.
- **Coverage sprint — AIToolAgent**: Widened 4 private methods to internal. 27 new tests (14→41 methods). Tests cover executeTool, withTimeout, gatherContext, executeRelevantTools, and edge cases.
- **Coverage sprint — IntentClassifier**: Widened withTimeout. 8 new tests covering timeout, param parsing, confidence, ClassifyResult enum, system prompt validation.
- **Coverage sprint — AIRuleEngine**: 6 new tests covering nextAction, caloriesLeft, weeklySummary, dailySummary format, yesterdaySummary format.
- **Coverage sprint — FoodService**: 22 new tests covering resolvedCalorieTarget, getDailyTotals, getCaloriesLeft, explainCalories, searchFood, findByName, getNutrition, deleteEntry, copyYesterday, topProteinFoods, suggestMeal, and more.
- **Total**: 886 tests (was 743+). +143 tests this session across 4 critical files.
- **UI Theme Overhaul**: Deep navy background (#0C0C14), visible card surfaces (#1A1A2E) with subtle borders, vibrant accent (#7C6AFF), new text hierarchy, typography scale (6 levels), spacing constants, accent gradient. All 46 views inherit automatically.
- **Food DB Enrichment**: 34 new foods (1041→1075). Seafood (7), Asian (9), Mediterranean (4), Soups (6), Breakfast (3), Fast Food/Bakery (5). All USDA-sourced macros.

## Cycle · 2026-04-12

- **Product Review #1**: Competitive analysis (MFP photo scanning, Whoop behavior insights, MacroFactor adaptive algo, Boostcamp muscle visualization). Promoted Adaptive TDEE to Now, added Behavior Insights section, muscle heatmaps to Next.
- **LB/KG unit fix (P0)**: WeightViewModel.loadEntries() now refreshes weightUnit from Preferences. Stale capture fixed. Test added.
- **Exercise weight unit support**: All workout views respect LB/KG preference. DB stays in lbs, conversion at view boundaries. ActiveWorkoutView, WorkoutDetailView, WorkoutSet.display all updated. Tests verify both units.
- **Adaptive TDEE**: TDEEEstimator now persists smoothed TDEE from weight trend + food intake. EMA alpha=0.2, requires 3+ data points. Applied with 0.4 dampening. GoalView shows adaptive value. 4 new tests.

## Cycle · 2026-04-11

- **Ingredient persistence**: Recipes now store full per-ingredient macros as JSON. RecipeItem is Codable. Swipe-to-edit opens recipe builder with pre-populated ingredients. Backward-compatible with legacy string-array format. 3 new tests.
- **Single-message meal logging**: "log breakfast 2 eggs and toast" parses meal type + items in one step, opens recipe builder directly. Handles "for"/"with" prefixes. Refactored food parsing into `buildMealFromText` helper.
- **Named calorie entries**: "log chipotle bowl 800 cal" preserves food name instead of "Quick Add". Extracts name by stripping calorie pattern + verbs.
- **"With" sub-splitting + multi-food recipe builder**: "coffee with 2% milk with protein powder" now splits into 3 individual items. Multi-food intents ("log chicken and rice") now open recipe builder with all items instead of search for first only. Added "the" article support in extractAmount. 3 new tests.
- **Animated typing dots**: Chat thinking indicator now uses animated three-dot typing indicator instead of ProgressView spinner. Styled as assistant message bubble for visual consistency.
- **Fix silent delete failures**: Delete/undo handlers used `try?` which silently swallowed errors — user saw "Deleted..." even when deletion failed. Now uses do/catch with visible error. Removed unreachable duplicate barcode scan block.
- **Food DB dedup**: 42 duplicate Indian food entries removed (1072→1030). Same-name entries with conflicting macros (e.g. dal makhani 350cal vs 230cal) kept original curated version only.
- **Meal continuation refactor**: "also add coffee with milk" now splits on "with" and resolves each sub-item. Continuation handler reuses `resolveRecipeItem()` — no more duplicated food resolution logic.
- **Test coverage push**: 3 new test methods for AIActionExecutor edge cases — trailing quantities, ranges, fractions, natural prefixes, meal hints, weight sanity checks, unit detection, article parsing. 5th-cycle coverage check.
- **Recipe builder action "with" splitting**: openRecipeBuilder action handler now uses `resolveRecipeItem()` + "with" splitting. All 3 food resolution paths are consistent.
- **SpellCorrectService tests**: 3 test methods covering hardcoded corrections (chiken→chicken, panner→paneer), passthrough for correct/short/common words, and fuzzy matching. Coverage from 0% → tested.
- **Fix isLowQuality false positive**: Short follow-up questions like "Would you like to log that?" were incorrectly flagged as low quality and replaced with fallback data. Now allows questions with action words.
- **Food DB serving size fix**: 55 entries had serving_size=1g (broke gram-based logging). Fixed to real weights. Added bulgur, farro. Fixed Vanilla Cake macros (was 0g fat).
- **Chat accessibility + contrast**: VoiceOver labels on message bubbles ("You said:", "Assistant:"). Improved bubble opacity for better readability.
- **Spell correction expanded**: ~40 new misspelling corrections for fruits, dairy, Indian foods, beverages, exercise terms. Organized by category.
- **Fix silent save failures + multi-turn upgrade**: Weight logging and workout save used `try?` which silently swallowed errors. Now uses do/catch with visible error. Multi-turn "What did you eat?" handler now uses `buildMealFromText` — handles multi-item responses ("pizza and salad"), "with" sub-splitting, and opens recipe builder with macros.
- **WeightServiceAPI.logWeight bug**: Returned the entry even when the DB save failed (try? swallowed error). Callers thought save succeeded. Now returns nil on failure. Added error feedback in chat confirmation handler.
- **Food DB enrichment**: 9 new foods (1032→1041). Venison, anchovies, clams, lo mein, California roll, kebab, crepe, scone, gajar halwa.

## Cycle · 2026-04-10

- **Intent classifier eval expansion**: 8→16 test methods, 50+ assertions across all 10 tools + edge cases (empty JSON, markdown wrapping, LLM quirks). Fixed empty tool string bug in parseResponse.
- **Unified tool schema prompt**: 12 tools with compact function signatures (~250 tokens). Added delete_food + body_comp.
- **Eval harness setUp fix**: ToolRegistration.registerAll() in setUp — fixed 2 pre-existing failures (testToolRankerWeightTools, testTryRulePickHitsCorrectTool).
- **StaticOverrides migration round 1**: Removed 8 info handlers (~60 lines). TDEE/BMR, "what did I eat", protein/macro queries → ToolRanker/IntentClassifier.
- **StaticOverrides migration round 2**: Removed calorie estimation + workout count (~40 lines). StaticOverrides 533→437.
- **StaticOverrides migration round 3**: Removed weekly comparison, workout suggestions, sugar query, diet advice (~40 more lines). StaticOverrides 437→393. All info queries now route through ToolRanker/IntentClassifier.
- **Multi-item food logging**: Comma-separated items from LLM now open recipe builder with all items + DB macros.
- **Tool routing accuracy eval**: 42 queries across all tools, 80%+ accuracy thresholds.
- **Prompt compression**: IntentClassifier prompt 50% smaller (35→17 lines).
- **Multi-turn context**: streamPresentation receives conversation history for LLM to reference prior responses.
- **Error recovery**: Friendly error messages + tool name sanitization.
- **Pipeline timing**: Instrumentation for latency measurement per phase.
- **Multi-item food logging**: Comma-separated items open recipe builder with DB macros.
- **Tool routing accuracy**: 42 queries across all tools, 80%+ accuracy thresholds.
- **Error recovery**: Friendly messages + tool name sanitization.
- **Context-aware tone**: Morning/daytime/evening hints in presentation prompt.
- **SmolLM presentation**: 8-pattern addInsightPrefix for conversational feel.
- **Workout editing**: Edit name/notes, tap set to edit weight/reps, swipe-to-delete sets.
- **Manual workout entry**: "Log Past Workout" button with date picker, no timer.
- **TemplatePreviewSheet extraction**: Unblocked WorkoutView type checker (595→500 lines).

**Session totals:** 16 commits. P0 LLM redesign complete (5/5 done). P1 Tool Quality complete (5/5). P1 Workout Editing complete (4/4). P2 Presentation Quality (3/3). StaticOverrides 533→393 lines. All 796 tests green.

---

## Cycle · 2026-04-08

- **Fix test isolation**: 12 mutating tests got own DB (shared seededDB caused flaky failures). Fixed extractAmount to return servings for count units (slices/cups) vs grams for weight units.
- **Multi-turn via history detection**: Added detectMealFromHistory() and detectWorkoutFromHistory() — conversation continues from history even when state vars are nil. Enhanced normalizer with continuation examples.
- **Normalizer accuracy + eval 300+**: Added messy input parsing tests, count unit extraction. Expanded eval to 300+ scenarios across food, weight, ToolRanker, pipeline, CoT routing. All 90-100%.
- **Multi-turn pronoun resolution**: "what about protein?", "how about carbs?" handled deterministically in StaticOverrides.
- **Multi-item meal continuation**: "also add broccoli" appends to existing recipe without re-triggering meal flow.
- **Gram/unit parsing**: "200ml milk", "half cup oats", "100g chicken" all parse correctly via compact leading and word amount patterns.
- **Food search ranking**: Verified singular-first + LENGTH tiebreaker ranks plain Banana over TJ's Gone Bananas.
- **Range parsing**: "2 to 3 bananas" → 3. extractAmount handles X to Y / X or Y.
- **Diet advice handler**: "I want to reduce fat" deterministically returns macro-aware advice.
- **"and yesterday?"**: Topic continuation for time references.
- **Workout history**: exercise_info now shows recent 7-day workout history from HealthKit.
- **Weekly sleep**: sleep_recovery tool accepts period param, shows 7-day avg sleep.
- **Word number resolver**: "set my goal to one sixty" → 160. resolveWordNumbers() handles compound word numbers.
- **Delete food from chat**: "delete last entry", "remove the rice" — StaticOverrides handler finds and deletes matching food entry.
- **Calorie estimation**: "calories in samosa", "estimate calories for biryani" — nutrition lookup handler in StaticOverrides.
- **Parity gaps closed**: All P0 (5/5) and P1 (3/4) AI chat parity gaps now done. Only barcode scan remains as P1.
- **Cross-domain analysis**: "why am I not losing weight?" combines food + weight + exercise data.
- **Daily summary wrong weight**: Fixed .last → .first on DESC-sorted array. Bug existed since the weight fetch was added.
- **Activity trailing duration**: "I did yoga for like half an hour" → 30 min. Strips filler words.
- **Calorie estimation from chat**: "calories in samosa", "estimate calories for biryani" — instant DB lookup.

**Session 1 totals:** 33 cycles, 33 commits. All P0/P1 sprint items + tool-first streaming done. All failing queries fixed except meal planning.

## Cycle · 2026-04-08 (session 2 — chat quality + plant points)
- **LLM presentation layer** — Info queries route through Gemma 4 streaming instead of data dumps
- **Presentation prompt tuned** — time-of-day, example, "warm and brief" guidance
- **bestQuery flows through pipeline** — normalizer output used for tool execution + LLM presentation
- **Richer tool data** — food_info has progress status, weight_info has total change + weekly trend
- **SmolLM insight prefix** — "Looking good —" / "Heads up —" for raw data responses
- **"how am I doing" fetches food + weight** — parallel execution for comprehensive answer
- **BUG-002 fixed** — recents macros: added macro columns to food_usage (migration v21)
- **BUG-003 fixed** — plant points date label updates with date navigation
- **FEAT-002** — "Copy to Today" from past day entries with toast confirmation
- **Ingredients column** — food + favorite_food (migration v22). Food.ingredientList computed property
- **Recipe builder saves ingredients** — items.map(\.name) persisted as JSON
- **PlantPointsService reads ingredients** — fetchUniqueIngredients() replaces fetchUniqueFoodNames()
- **Spice blend expansion** — 10 blends decomposed (garam masala = 5 spices = 1.25 pts)
- **Precomputed ingredients** — 40 composite dishes in foods.json (biryani, tikka masala, etc.)
- **Barcode scan saves ingredients** — OpenFoodFacts ingredientsText parsed and stored
- **Avocado + edge cases** — Verified all in plantKeywords

---

---

## Cycle 1 · 2026-04-06 08:37

**Priority:** P1 (Rearchitect: LLM for intent)
**Change:** Action tags always available in system prompt + all screen contexts; fix weight intent false positive
**Files:** LocalAIService.swift, AIContextBuilder.swift, AIActionExecutor.swift
**Build:** OK
**Tests:** 729 passed, 0 failed
**Eval harness:** All passed
**Commit:** d76c92e
**Status:** keep
**Notes:** "chicken weighs 200g" was a pre-existing bug — parseWeightIntent matched "weigh" too broadly. Changed to "i weigh". Action tags now always in system prompt so LLM can classify food/weight/workout intents from any screen.

---

## Cycle 2 · 2026-04-06 08:40

**Priority:** P1 (Rearchitect: LLM for intent)
**Change:** Removed 3 hardcoded response blocks from sendMessage() — workout logging prompt, generic food guidance, restaurant guidance. These now go to LLM.
**Files:** AIChatView.swift
**Build:** OK
**Tests:** 729 passed, 0 failed
**Eval harness:** n/a (no AI logic change, just routing)
**Commit:** 1bbd1a3
**Status:** keep
**Notes:** sendMessage() is 18 lines shorter. "log a workout", "log food", "ate out" now handled by LLM with action tags. Kept: weight intent (deterministic), multi-turn follow-up (complex), food/multi-food intent parsers (deterministic).

---

## Cycle 3 · 2026-04-06 08:44

**Priority:** P2 (Conversational workout builder)
**Change:** Enhanced workoutContext() with exercise details from last workout and body part coverage analysis
**Files:** AIContextBuilder.swift
**Build:** OK
**Tests:** 729 passed, 0 failed
**Eval harness:** All passed
**Commit:** 0a4ee95
**Status:** keep
**Notes:** LLM now sees "Last exercises: Bench Press 3x135lb, Squats 4x185lb" and "Needs training: Legs (5d), Back (4d)". This enables Flow C (AI suggests workout based on history).

---

## Cycle 4 · 2026-04-06 08:46
**Priority:** P3 (Eval harness)
**Change:** Eval 22→25: workout routing, false positives, multi-exercise parsing
**Commit:** 6dc40c0 | **Status:** keep

---

## Cycle 5 · 2026-04-06 08:47
**Priority:** P1 (Routing fix)
**Change:** Comparison routing includes domain context (workout/food) when mentioned
**Commit:** ace6652 | **Status:** keep

---

## Cycle 6 · 2026-04-06 08:48
**Priority:** P2 (Workout keywords)
**Change:** Expanded workout keywords: push/pull/leg day, body part, muscle, split, PPL
**Commit:** c415918 | **Status:** keep

---

## Cycle 7 · 2026-04-06 08:49
**Priority:** P3 (Response quality)
**Change:** Response cleaner: markdown bullets, numbered lists, regurgitation detection
**Commit:** 52f9d32 | **Status:** keep

---

## Cycle 8 · 2026-04-06 08:50
**Priority:** P3 (Eval harness)
**Change:** Eval 25→35: Indian foods, amounts, negation, response cleaner, domains
**Commit:** e47af9b | **Status:** keep

---

## Cycle 9 · 2026-04-06 08:51
**Priority:** P1 (Dashboard fallback)
**Change:** Dashboard fallback provides fullDayContext for substantive queries (>10 chars)
**Commit:** a619910 | **Status:** keep

---

## Cycle 10 · 2026-04-06 08:52
**Priority:** P3 (Eval harness)
**Change:** Eval 35→39: routing expansion, food coverage, action parser batch, rule engine
**Commit:** a1f72ab | **Status:** keep

---

## Cycle 11 · 2026-04-06 08:53
**Priority:** P2 (Workout builder)
**Change:** CREATE_WORKOUT template includes reps + weight in notes field
**Commit:** 3ec4fc1 | **Status:** keep

---

## Cycle 12 · 2026-04-06 08:55
**Priority:** P4 (Food polish)
**Change:** Food parser handles beverages/snacks/cooking: drank, snacked, made, i'm having
**Commit:** cc6dfef | **Status:** keep

---

## Cycle 13 · 2026-04-06 08:57
**Priority:** P3 (Eval harness)
**Change:** Eval 40→48: edge cases, robustness, truncation, disclaimers, dedup, weight units
**Commit:** a6e717d | **Status:** keep

---

## Cycles 14-26 · 2026-04-06 09:00-09:15

**Summary of changes:**
- P1: Few-shot examples in system prompt, dashboard fallback context, expanded keywords (deficit/surplus/carbs/plateau/stall), tightened keywords (fast→fasting, rest→rest day, press→space+press)
- P2: Direct template start handler, workout context suggests don't auto-start, CREATE_WORKOUT invites additions
- P3: Eval harness 35→58 methods (~380 test cases)
- P4: Synced multi-food parser verbs with single-food parser
- P6: Bullet regex line-start only, numbered list regex line-start only, weight false positive fix

**Commits:** 3381884, 1c33d34, 8b8b9a0, 377aa0f, 86f258a, 9af6908, 564e91a, 488bdf5, aeb707a, cd708a5, e1c346f, 0a7a577

---

## Sprint: Unified Service Layer · 2026-04-06

## b24799d TC-1: ToolSchema + ToolRegistry
## da6e4c8 TC-2: SpellCorrectService
## c8cc327 TC-3: JSON tool-call parser
## bc80c11 SVC-1: FoodService
## 7894260 SVC-2: WeightServiceAPI
## 17adc16 SVC-3: ExerciseService (smart builder, progressive overload)
## d72c698 SVC-4/5/6/7: SleepRecovery, Supplement, Glucose, Biomarker services
## 4b0750f WIRE-1: Register 20 tools in ToolRegistry
## cf9ce57 WIRE-2: System prompt injects tool schemas
## e7eacfb WIRE-3: AIChatView uses ToolRegistry.execute()
## af5f810 WIRE-5: Smart workout fallback
## db7fdc5 QA-1: Eval harness 63→69 (JSON tool-call tests)
## 7e5f461 QA-2/3/4: Service unit tests (69→80 eval tests)
## 7564b2f fix: Flaky session tests
## 88fe49b sprint: P0 AI Chat Quality — never done
## c24260e test: Eval 97→108, TestFlight 3h rule
## b31dd28 improve: Data-aware fallback responses
## a7197eb improve: Implicit intent keywords
## 53a3b70 improve: System prompt rewritten for 1.5B
## 7196164 test: Eval 108→122, realistic conversations
## b46d000 improve: Quality gate v2 — catch refusals, mangled JSON
## 797fd43 improve: SpellCorrect uses food DB fuzzy matching
## 1c686a2 test: Eval 122→128

## 2026-04-07 Session (18 cycles)
1. Mark supplement taken via chat (tool + handler)
2. Delete food entry via chat (tool + handler)
3. Copy yesterday's food (tool + handler)
4. Quick-add raw calories (regex handler)
5. Set weight goal via chat (tool + regex handler)
6. Fix "suggest me workout" (12 phrasings)
7. Instant "how many workouts this week" (rule engine)
8. Gemma 4 prompt tuning (5 new tool examples)
9. Log completed activities ("I did yoga", "went running")
10. Cross-domain analysis ("should I eat more", "I feel tired")
11. Body comp entry via chat ("body fat 18%", "bmi 22.5")
12. Weekly comparison instant answer
13. Inline macro logging ("400 cal 30g protein lunch")
14. Add supplement to stack
15. Trigger barcode scan from chat
16. Fix "what's healthy for dinner" (meal suggestions + macros)
17. Fix "I had a cheat meal" (ask what they ate)
18. Handle "how much sugar today" (carbs proxy)
