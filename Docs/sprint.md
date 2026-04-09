# Sprint Board

Priority: AI chat quality — natural conversation, better tool calling, insightful responses.

## In Progress

_(pick from Ready)_

## Ready

### P0: Chat Response Quality
- [x] **Presentation prompt tuning** — Added time-of-day context, example response, "warm and brief" tone. Tuned for Gemma 4 2B.
- [x] **Include user query in presentation context** — bestQuery (normalizer output) now flows through Phase 3 tool execution + LLM presentation.
- [x] **Richer tool data for presentation** — food_info has progress status indicator, weight_info has total change + weekly trend.
- [x] **SmolLM fallback templates** — addInsightPrefix() adds "Looking good —" / "Heads up —" based on data content.

### P1: Tool Calling Accuracy
- [x] **Tool routing verification** — 12 new eval cases verifying removed StaticOverrides queries route correctly. daily summary→food_info, sleep trend→sleep_recovery, weight progress→weight_info.
- [ ] **LLM eval on tool routing** — Run 40+ queries through Gemma 4 tool-calling path on device. Requires LLM eval (not unit test).
- [x] **Normalizer → tool pick chain** — bestQuery flows from normalizer through Phase 3 tool execution.
- [x] **Tool param extraction quality** — food_info gets yesterday/weekly/suggest context. sleep_recovery gets period=week. General queries pass raw query for LLM context.
- [x] **Anti-keyword tuning** — Verified: "how much does chicken weigh" suppressed by "how" anti-keyword on log_weight. "reduce fat" caught by diet advice handler.

### P2: Latency & Streaming
- [ ] **Measure end-to-end latency** — Time each pipeline stage for 10 common queries. Where is time spent? Normalizer? Tool execution? LLM presentation? Find the bottleneck.
- [ ] **Progressive multi-item disclosure** — For "rice and dal", show each found item as it's discovered, don't batch.
- [ ] **Normalizer cache** — If the same query was normalized before (same session), skip the 3s normalizer call.

### P3: Conversation Feel
- [ ] **Vary response openings** — LLM tends to start every response the same way. Add variety hints in the presentation prompt (time of day, performance vs goal).
- [ ] **Multi-turn meal planning** — "plan my meals for today" → iterative macro-aware suggestions. Gemma 4 only.
- [ ] **Conversation memory** — Pass previous tool results to next turn so LLM can reference them ("you mentioned protein was low earlier").

### P0: UI Bugs & Features (human-reported)
- [x] **BUG: Recent foods missing macros** — Fixed: added macro columns to food_usage, trackFoodUsage() stores macros, fetchRecentEntryNames() reads directly. Migration v21 backfills.
- [ ] **Copy to today from past day** — When viewing a past day's food log, show a "Copy to today" option per item. Don't show when viewing today. Brief toast confirms without navigating. Files: `FoodTabView.swift`, `FoodLogViewModel.swift`.
- [x] **Plant points date awareness** — Fixed: shows "Today" or actual date (e.g. "Apr 5") based on selectedDate.

### P1: Plant Points Accuracy
Current: keyword-matching on food names only. Fix: every food gets an `ingredients` JSON array. Plant points counts unique plant ingredients, not food names. No ML model needed — precompute for seeded foods, inherit from recipe builder, default to `[self]` for simple items.

- [ ] **Add `ingredients TEXT` column to `food` + `saved_food`** — JSON array of ingredient names. Migration. Simple foods: `["banana"]`, `["egg"]`. Dishes: `["rice", "onion", "tomato", "turmeric", "cumin"]`. Default: `[food.name]` (self). Precompute for all 1000+ seeded foods in `foods.json` — simple items = self, top ~200 composite dishes = hardcoded ingredient list.
- [ ] **Recipe builder saves ingredients** — `saveAndLogRecipe()` stores `items.map(\.name)` as `ingredients` JSON on the saved entry. Already has the data, just needs to persist it.
- [ ] **Barcode scan saves ingredients** — OpenFoodFacts API returns ingredient list. Parse and store as `ingredients` JSON when saving scanned food.
- [ ] **Custom entry ingredients** — Default to `[name]`. If built via recipe builder, gets real ingredients automatically.
- [ ] **PlantPointsService reads ingredients** — Change from `fetchUniqueFoodNames()` to reading `ingredients` JSON from each food_entry. Flatten all ingredient arrays → count unique plants. Falls back to `[food_name]` if ingredients is null (old entries).
- [ ] **Six-category alignment** — Classify each ingredient into Super Six: Vegetables, Fruits, Whole Grains, Legumes, Nuts/Seeds, Herbs/Spices (¼ pt). Use Food.category field + keyword matching.
- [ ] **Avocado + edge case audit** — Ensure avocado (fruit), coconut (fruit), quinoa (seed), tofu (legume) all classify correctly. Audit non-plant overrides list.
- [ ] **Spice blend expansion** — "Garam Masala" ingredients: `["cumin", "coriander", "cardamom", "cloves", "pepper"]`. Hardcode top 10 spice blends.
- [ ] **No ML model needed** — Precomputed ingredients in DB + recipe builder + OpenFoodFacts covers ~95% of cases. Tiny model evaluation deferred — revisit only if custom entries without ingredients are common.

### P1.5: Data Model Cleanup
- [ ] **Rename `favorite_food` → `saved_food`** — Table holds favorites, recipes, and (soon) saved custom entries. `FavoriteFood` model → `SavedFood`. Migration: `ALTER TABLE favorite_food RENAME TO saved_food`. Update all references: model, AppDatabase queries, FoodLogViewModel, QuickAddView, DefaultFoods, FoodService, StaticOverrides, AI tools, tests. `isRecipe` flag stays. Consider adding `isFavorite` bool alongside it.
- [ ] **Unify user-created food storage** — Currently: DB foods in `food`, recipes in `favorite_food`, manual entries in neither (only `food_entry` + `food_usage`). After rename, `saved_food` becomes the single table for all user-created foods: recipes, manual "save for future" entries, barcode scans (move from `food`?). The seeded `food` table stays read-only.

### P2: Salad Bowl / Custom Meal Builder
Goal: let users build Sweetgreen-style salads without fatigue. Existing recipe builder is the foundation.

- [ ] **Salad base templates** — 5-8 pre-built starting points: "Green Salad Base" (spinach + lettuce), "Grain Bowl" (quinoa + greens), "Protein Bowl" (chicken + rice). User picks base → customizes. Lives in recipe builder flow.
- [ ] **Recent ingredients in picker** — Show recently used ingredients at top of ingredient picker (already tracked via food_usage). Reduces fatigue for repeat builders.
- [ ] **Category tabs in ingredient picker** — Show tabs (Greens, Proteins, Toppings, Dressings) alongside search. Pre-filter by Food.category for faster browsing.
- [ ] **Ingredient persistence** — Use the `ingredient_names` JSON column (from plant points task) — already stores ingredient list. For salad rebuilding, also store per-ingredient macros in `favorite_food.ingredients_json` (full RecipeItem data). Enables: recipe rebuilding, "what's in this?" via AI chat. No new table.

## Done

### This sprint
- [x] **LLM presentation layer** — Info queries route through tool execution → Gemma 4 streaming presentation instead of data dumps
- [x] **Parallel tool execution** — TaskGroup-based parallel info tool execution
- [x] **ToolRanker keyword expansion** — food_info, weight_info, sleep_recovery enriched with summary/yesterday/weekly/suggest/trend keywords
- [x] **Enriched weight_info** — Total change + weekly trend data for LLM presentation
- [x] **Food_info context routing** — yesterday/weekly/suggest queries get specific data paths
- [x] **Sleep_recovery period param** — "sleep trend" routes with period=week

### Previous sprint
- [x] Multi-turn via normalizer context + history detection
- [x] Normalizer accuracy tuning (330+ eval scenarios)
- [x] Multi-turn pronoun resolution
- [x] Eval harness 370+ scenarios
- [x] Multi-item meal continuation
- [x] Gram/unit parsing (200ml, half cup, ranges)
- [x] Food search ranking (singular-first + length tiebreaker)
- [x] All P0/P1 AI parity gaps closed
- [x] All failing queries fixed (except meal planning)
- [x] Cross-domain analysis, weekly comparison, calorie estimation
- [x] Delete/undo food, weight progress, TDEE/BMR, barcode scan from chat
