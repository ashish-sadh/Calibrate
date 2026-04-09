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
- [ ] **BUG: Recent foods missing macros** — When a manual entry (quick-add) is saved, it doesn't copy calories/macros to the recent foods list. Re-logging from recents shows 0 cal. Investigate `trackFoodUsage()` in `AppDatabase+FoodUsage.swift` — likely stores name but not nutrition. Fix: pass macros through to usage tracking.
- [ ] **Copy to today from past day** — When viewing a past day's food log, show a "Copy to today" option per item. Don't show when viewing today. Brief toast confirms without navigating. Files: `FoodTabView.swift`, `FoodLogViewModel.swift`.
- [ ] **Plant points date awareness** — "Today" label in `PlantPointsCardView.swift` doesn't update when viewing a different date. Show actual date (e.g. "Apr 5") when not today. Week/month fine.

### P1: Plant Points Accuracy
Current implementation is keyword-matching on food names only. Composite foods like "Chicken Biryani" count as 0-1 points instead of decomposing into rice + onion + spices = 2.25 points. Avocado may be excluded. Design: count by ingredients, not recipe names.

- [ ] **Ingredient-level plant counting** — Add `ingredient_names TEXT` column (JSON array) to `food_entry` and `favorite_food` tables. When recipe is saved in `saveAndLogRecipe()`, store `["rice", "dal", "onion"]` from `items.map(\.name)`. Plant points reads `ingredient_names` if present, falls back to `food_name`. No new table needed — just a column + migration. For seeded FavoriteFoods, precompute ingredient lists.
- [ ] **Six-category alignment** — Match the "Super Six": Vegetables, Fruits, Whole Grains, Legumes, Nuts/Seeds, Herbs/Spices (¼ pt each). Use Food.category field from DB (exists, currently unused by PlantPointsService). Map: "Fruits"→Fruits, "Vegetables"→Vegetables, "Nuts & Seeds"→Nuts/Seeds, "Indian Staples" with dal/lentil→Legumes, "Grains & Cereals"→Whole Grains.
- [ ] **Avocado + edge case audit** — Avocado is a fruit (should count). May be blocked by non-plant overrides. Audit: coconut (fruit), quinoa (seed), tofu (legume-derived). Ensure all "Fruits"/"Vegetables" category foods pass classification.
- [ ] **Tiny model for ingredient inference + plant classification** — Evaluate if a ≤500M model is needed or if rules + DB precomputation suffice. Decision tree:
  1. **Try rules-only first:** For the 1000+ seeded foods, precompute a `food_plant_ingredients` column in the DB at seed time using keyword decomposition (e.g. "Chicken Biryani" → rice, onion, spices from a hardcoded recipe map). If 80%+ of logged foods are seeded, this may be enough.
  2. **If rules aren't enough:** Pick a tiny model (≤500M, Q4/Q8). Candidates: SmolLM2-135M, Qwen2.5-0.5B, TinyLlama-1.1B (too big). Must be small enough to load/unload in <2s. The existing SmolLM 360M could work if already downloaded — but don't assume it's present (it's the small-model tier, user may have Gemma instead).
  3. **Load/unload pattern:** Do NOT keep loaded — async task that loads model → runs inference → unloads. Triggered on food_entry insert. Cache result in `food_plant_ingredients` table so inference runs once per unique food. ~50-100 token prompt: "List the plant ingredients in {food_name}. Only plants, no meat/dairy."
  4. **Ship path:** Start with rules + precomputed DB (no model needed). Add model inference later for unknown/custom foods only. This keeps memory footprint zero for plant points. Fine-tune the tiny model later on our food→ingredients training data.
  5. **Consider:** The main AI model (SmolLM or Gemma) could also do this if it's already loaded when the user is in chat. But if they log from the Food tab (no chat), no model is loaded. A dedicated tiny model solves this but adds download size.
- [ ] **Herbs/spices composite expansion** — "Garam Masala" = cumin + coriander + cardamom + cloves + pepper (1.25 pts, not 0.25). Expand known spice blends. This is rules-only, no model needed.

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
