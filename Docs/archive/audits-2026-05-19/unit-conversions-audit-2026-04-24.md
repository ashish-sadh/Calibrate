# Audit: Artificial Unit & Piece Conversions

**Date:** 2026-04-24
**Trigger:** User screenshot of `"Strawberries, Fresh"` showing `"5 pieces = 750g = 240 cal"`. Real: 5 medium strawberries ≈ 60g ≈ 19 cal. **~4× silent overcount.**

**Scope:** audit of the unit → grams → calories chain, not of individual food macros. Covers `Drift/Models/ServingUnit.swift`, `Drift/Models/Food.swift`, `Drift/Resources/foods.json`, `Drift/Services/USDAFoodService.swift`, `Drift/Services/OpenFoodFactsService.swift`, and the UI surfaces in `FoodLogSheet.swift` and `AIChatView+MessageHandling.swift`.

**Verdict:** the unit layer is a 1,294-line tower of `if name.contains(...)` branches (**181** of them, plus **447** `name.contains` / **29** `words.contains` conditionals) with a single dominant failure mode — when the real gram weight of a unit is unknown, the code synthesizes it from `food.servingSize` and offers it to the user as if it were measured. This pattern appears at **117** sites in ServingUnit.swift and potentially affects **1,242 of 2,511 foods** (49%). The UI compounds the failure by printing the synthesized gram figure in bold as "per 1 piece (150g)", which inoculates users against suspecting it.

Existing `SmartUnitsGoldSetTests` validate only *which units get offered*, never the final kcal. That's why the roadmap could mark "Smart Units cross-interface consistency" DONE while the bug in the screenshot remained live.

---

## 1. Inventory of brittleness (evidence-first)

All file:line references grep-verified on 2026-04-24.

| # | Heuristic | File:line | Real-world spread | Silent error | Foods affected |
|---|---|---|---|---|---|
| 1 | `tbsp = 15g` flat | `ServingUnit.swift:206, 536, 584, 588, 618, 694, 968, 1217, 1233` (**9 sites**) | oil 15 / honey 21 / PB 32 / sauce 18 | −17% to −53% | all tbsp-eligible foods |
| 2 | `spray = 0.25g` | `ServingUnit.swift:235` | 0.2–0.5g bottle-to-bottle | ±50% | oils, ghee |
| 3 | `cupGrams()` name substring | `ServingUnit.swift:1274–1293` | rice 185 / oats 80 / dal 200 / default 240 | ±10–20% per food | ~200 cup-eligible foods |
| 4 | `pieceGrams()` name substring (20 entries) | `ServingUnit.swift:1250–1272` | produce varies 2–3× in reality | up to 100% | ~150 countable foods |
| 5 | **`piece → food.servingSize` fallback** | `ServingUnit.swift:300–303` | confirmed 4× for strawberry (150g "piece" vs real 12g) | unbounded, up to 10× | **1,242 foods** (see §4) |
| 6 | No per-food unit-override fields on `Food` | `Food.swift` (absence) | — | structural | all 2,511 foods |
| 7 | `defaultAmount` guard narrow | `ServingUnit.swift:173–181` | only triggers for `gramsEquivalent ≤ 1.01` | structural | AI-chat composed meals |
| 8 | **`gramsEquivalent: ss` anti-pattern** (piece/bowl/slice/strip/link/scoop/egg/meatball/banana/apple/orange) | `ServingUnit.swift:318, 320, 330, 336, 343, 350, 354, 360, 374, 380, 385, 390, 394, 400, 402, 404, 412, 417, 419, 423, 428, 432, 438, 440, 441, 442, 443, 449, 453, 457, 461, 468, 470, 471, 472, 473, 474, 475, 476, 477, 488, 491, 493, 494, 498, 503, 509, 517, 525, 531, 540, 542, 544, 625, 630, 635, 642, 659, 668, 676, 681, 685, 689, 749, 759, 766, 775, 779, 784, 804, 810, 817, 821, 825, 838, 842, 844, 856, 862, 866, 868, 881, 885, 888, 890, 892, 894, 899, 954, 1005, 1009, 1015, 1020, 1032, 1041, 1045, 1054, 1058, 1073, 1087, 1093, 1097, 1104, 1108, 1119, 1123, 1127, 1145, 1157, 1172, 1199, 1212, 1231, 1244, 1247` (**117 sites**) | depends on how each food was seeded | unbounded | every food that hits one of these branches |
| 9 | `primaryUnit` default `ss > 0 ? ss : 100` | `ServingUnit.swift:309` | food with missing servingSize silently treated as 100g | unbounded | foods with ss==0 (currently 0, but no guard) |

### 1a. `findFood` silent guessing (parallel class in search)

| # | Behavior | File:line | Failure mode |
|---|---|---|---|
| A | Nondeterministic tight-match | `AIActionExecutor.swift:230–237` | Same query can pick different foods across sessions when multiple entries share a first word |
| B | Qualifier stripping discards intent | `AIActionExecutor.swift:254–264` | `"cups of rice"` → `"rice"` with `servings=1`, losing the cup signal |
| C | First-word fallback | `AIActionExecutor.swift:267–272` | `"chicken breast"` → `"chicken"`, may return Chicken Nuggets |
| D | Silent spell correction | `AIActionExecutor.swift:246–250` | Corrections applied without UI signal |

### 1b. UI amplification

`FoodLogSheet.swift:107` prints `"per 1 \(currentLabel) (\(Int(unit.gramsEquivalent))g)"` in bold above the calorie field. When `unit.gramsEquivalent` is synthesized from `ss` (every row under item #8), the UI confidently displays a measurement-looking number that was invented.

---

## 2. Reproduction measurements

Static analysis predicts the following. **Live FoodLogSheet / AI-chat measurements are still needed to confirm** — audit does not block on the sim run; results recorded here are computed from `foods.json` seed values and `ServingUnit.swift` branch logic.

| Query | Food picked | Unit picked | `gramsEquivalent` source | Predicted output | Expected (real) | Silent error |
|---|---|---|---|---|---|---|
| `5 strawberries` | `Strawberries, Fresh` (ss=150g, 48 kcal) | `piece` | fallback #5 → `ss=150g` | `5 × 150 = 750g, 5 × 48 = 240 kcal` | ~60g / ~19 kcal | **+265% / 4.0×** ✅ confirmed in screenshot |
| `1 cup grapes` | `Grapes (1 cup)` (ss=151g, 104 kcal) | `piece` (fallback) | ss=151g | 1 piece = 151g (accidentally correct) | 151g / 104 kcal | OK by coincidence — breaks if user enters "5 pieces" → 5 grapes reported as 755g |
| `1 cup blueberries` | `Blueberries (1 cup)` (ss=148g, 85 kcal) | `piece` | ss=148g | 1 piece = 148g | 1 berry ≈ 1.5g | **+9800%** if user logs "10 pieces" expecting 10 berries |
| `1 tbsp honey` | Honey entry | `tbsp` | constant 15g | 15g × honey kcal/g | real ≈ 21g | **−29%** |
| `1 tbsp peanut butter` | PB entry | `tbsp` | constant 15g (unless the line-482 override hits) | varies | real ≈ 32g | **−53%** if 15g wins |
| `5 sprays olive oil` | Olive Oil | `spray` | constant 0.25g | 1.25g, ~11 kcal | real 1.5–2.5g, ~15–22 kcal | **−30% to −50%** |
| `1 cup cooked rice` | `White Rice (cooked)` (ss=200g, 260 kcal) | `cup` | `cupGrams("rice")=185g` | 185/200 × 260 = 241 kcal | 195g × (260/200) = 254 kcal | **−5%** (OK-ish) |
| `1 piece dosa` | `Dosa (plain)` (ss=100g, 168 kcal) | `piece` (line 332-336) | ss=100g | 100g, 168 kcal | 1 medium dosa ≈ 80–100g | OK when ss represents one piece |
| `1 piece masala dosa` | `Masala Dosa` (ss=150g, 280 kcal) | `piece` (line 332-336) | ss=150g | 150g, 280 kcal | 1 medium ≈ 180–220g | **−20%** (DB seed undercounts) |
| `2 eggs` | egg entry (ss=50g) | `egg` (line 318) | ss | 100g, 156 kcal | 100g, ~156 kcal | OK when egg ss≈50 |
| `2 eggs` (mis-seeded) | egg entry with ss=600 ("pack of 12") | `egg` | ss=600 | 2 × 600 = 1200g, ~1860 kcal | 100g, ~156 kcal | **12×** — structural risk |

Three observations:

- **Shortcut #5 and #8 are dominant.** Where the DB seed's `servingSize` was authored to mean *per piece*, the app is fine. Where it was authored to mean *per cup / per bowl / per plate*, the app is silently wrong by a 2–10× multiplier. No test catches this.
- **Which case fires is invisible to the user.** There's no indicator in the UI distinguishing "ss genuinely means one piece" (egg, dosa) from "ss means one cup re-labeled as piece" (strawberry, grapes).
- **tbsp honey / peanut butter** are silent errors at the −29% to −53% scale for anyone logging condiments.

---

## 3. Test gaps — what would have caught strawberry at 4× over

`DriftTests/SmartUnitsGoldSetTests.swift` asserts only that certain foods *get* certain unit pills offered. No test takes `(food, unit, amount)` → persisted kcal and asserts a number. Needed:

```swift
// DriftTests/UnitConversionEndToEndTests.swift (new file)
func testStrawberryPiece_matchesMediumBerryWeight()
  // Given Strawberries, Fresh (ss=150g), 1 piece should be ~12g not 150g.
  // Asserts FoodUnit.smartUnits offers no "piece" unless pieceSizeG is known,
  // OR piece.gramsEquivalent <= 30g for this food.

func testTbspHoney_caloriesWithinFivePercentOfUSDA()
  // 1 tbsp honey should be ~64 kcal (USDA: 21g × 304 kcal/100g).

func testTbspPeanutButter_usesPerFoodOverrideNotFlatFifteen()
  // 1 tbsp PB should be ~190 kcal (32g × 589 kcal/100g). 
  // Current constant 15g yields ~88 kcal (−53%).

func testSprayOliveOil_ssignalsEstimateInUI()
  // The UI for "spray" must either not show a gram figure or mark it as estimate.

func testPieceFallback_refusedWhenPieceWeightUnknown()
  // For a food not in pieceGrams() and with no pieceSizeG override,
  // smartUnits MUST NOT offer "piece". Users get g/cup/serving instead.

func testResolveRecipeItem_honorsFoodUnitDefaultAmount()
  // AI-chat-composed meals reach FoodLogSheet through the recipe builder.
  // The defaultAmount guard at line 173-181 currently only fires in
  // FoodLogSheet.init and QuickAddView. Composed meals must honor it too.

func testEggUnit_validatesServingSizeIsPieceSize()
  // If an egg food has ss > 100g, the "egg" unit must not silently use ss.

func testUnitGramsEquivalent_nonSynthesizedOrFlagged()
  // For every Food, for every FoodUnit returned, either gramsEquivalent came
  // from a trusted source (pieceGrams, cupGrams, tbspGrams override, or per-food
  // column) OR the unit is tagged `.synthesized` and the UI suppresses the gram figure.
```

Minimum 8 new tests. All should run under `xcodebuild test -only-testing:DriftTests/UnitConversionEndToEndTests` in < 2s (deterministic, no LLM).

---

## 4. Food DB integrity probe

Queries against `Drift/Resources/foods.json` on 2026-04-24.

| Query | Count |
|---|---|
| Total foods | **2,511** |
| `serving_size == 0` (would trigger primaryUnit:309 fallback to 100) | **0** |
| `serving_size == 1` (the #195 zero-cal trigger) | **0** |
| `calories == 0` (silent zero trap) | **8** |
| `serving_unit == 'g'` | **2,067** (82%) |
| `serving_unit == 'ml'` | 226 |
| `serving_unit == 'cup'` | 21 |
| `serving_unit == 'bowl'` | 19 |
| `serving_unit == '1 cup'` (string variant — UI inconsistency) | 16 |
| `serving_unit == 'sandwich'`, `'pieces'`, `'tbsp'`, etc. | <10 each |

### Shortcut #5 blast radius

Foods where `serving_unit == 'g'`, `serving_size >= 50`, name not in the 20-entry `pieceGrams()` dict, not bulk, not an already-countable (egg/banana/apple/orange):

**1,242 foods** (49.5% of the DB) currently fall through the piece-fallback path. If the user taps "piece" for any of these, `gramsEquivalent` comes straight from `ss`. Whether the output is right or wrong depends entirely on whether the seed author intended ss to mean "per piece."

Sample of affected foods (top 12 by insertion order):

```
Rajma (cooked): 200g 240cal          → "1 piece" = 200g (nonsense)
Naan: 90g 260cal                     → "1 piece" = 90g (OK — naan is a piece)
Paratha (plain): 60g 200cal          → "1 piece" = 60g (OK — one paratha)
Aloo Paratha: 80g 250cal             → "1 piece" = 80g (OK)
Dosa (plain): 100g 168cal            → "1 piece" = 100g (OK)
Masala Dosa: 150g 280cal             → "1 piece" = 150g (OK)
Idli (2 pieces): 80g 130cal          → "1 piece" = 80g BUT name says 2 pieces! Silent 2× overcount per piece
Upma: 200g 240cal                    → "1 piece" = 200g (nonsense — bowl)
Poha: 200g 250cal                    → "1 piece" = 200g (nonsense — bowl)
Paneer: 100g 265cal                  → "1 piece" = 100g (nonsense — not a piece)
Palak Paneer: 200g 290cal            → "1 piece" = 200g (nonsense — bowl)
Aloo Gobi: 200g 180cal               → "1 piece" = 200g (nonsense — bowl)
```

Notice `Idli (2 pieces): 80g` — the name explicitly says two pieces, the DB stores 80g for the pair, the fallback then calls the whole 80g "1 piece." A user logging "3 idlis" gets `3 × 80g = 240g ≈ 390 kcal` instead of `3 × 40g = 120g ≈ 195 kcal` — **2× overcount**, locked into the DB schema itself.

### Berry/grape cluster (sibling of strawberry)

**14** foods named with "cup" serving but stored as `g` with ss=148–151g. All vulnerable to the same strawberry bug if a user taps "piece":

```
Grapes: 150g 104cal
Strawberries: 150g 48cal         ← subject of the user screenshot
Greek Yogurt Blueberry: 150g 110cal
Strawberries, Fresh: 150g 48cal  ← subject of the user screenshot
Grapes (1 cup): 151g 104cal
Frozen Mixed Berries (1 cup): 150g 70cal
Blueberries (1 cup): 148g 85cal
...
```

### Cup-named `_g_` mismatches

**21** foods have `"(1 cup)"` in the name but `serving_unit` stored as `g` or `ml`. The name claims cup but the schema doesn't. UI inconsistency (the user sees "per 148g" in one place and "(1 cup)" in the name):

```
Cherry Tomatoes (1 cup): 149g 27cal
Grapes (1 cup): 151g 104cal
Oat Milk (1 cup): 240ml 120cal
Almond Milk Unsweetened (1 cup): 240ml 30cal
...
```

---

## 4b. External data sources — what we have and what we're discarding

### USDA FoodData Central — data exists, we throw it away

`Drift/Services/USDAFoodService.swift:48–74` parses exactly 5 nutrients and hardcodes `servingSizeG: 100`:

```swift
return FoodItem(
    name: name.capitalized,
    calories: cal, proteinG: protein, carbsG: carbs, fatG: fat, fiberG: fiber,
    servingSizeG: 100      // ← ground truth discarded here
)
```

USDA's API response for every Foundation / SR-Legacy food contains a `foodPortions` array. Example response for strawberries (FDC ID 167762):

```json
"foodPortions": [
  {"amount": 1, "modifier": "cup, sliced",         "gramWeight": 166},
  {"amount": 1, "modifier": "large (1-3/8\" dia)", "gramWeight": 18},
  {"amount": 1, "modifier": "medium (1-1/4\" dia)","gramWeight": 12},
  {"amount": 1, "modifier": "small (1\" dia)",     "gramWeight": 7},
  {"amount": 1, "modifier": "NLEA serving",        "gramWeight": 147}
]
```

Measured, authoritative, free, already in the JSON response we're parsing. We read none of it.

**Consequence:** every online fallback that hits USDA (the "coffee with milk" path, rare Indian imports, branded variants) produces a food with a fake 100g serving. Then `smartUnits()` synthesizes piece/cup/tbsp from that fake 100g, reproducing shortcut #8 live.

### OpenFoodFacts — data partially extracted, handoff unverified

`Drift/Services/OpenFoodFactsService.swift:18–19, 151–198` exposes:

```swift
let servingSizeG: Double?  // parsed serving size in grams
let piecesPerServing: Int? // e.g. "3 pieces (85g)" → 3
```

`parsePieceCount` (lines 151–161) has a solid regex covering pieces/pcs/bars/pastries/cookies/crackers/sticks/slices/wafers/biscuits/rolls/tablets/capsules/scoops. `parseServingSize` (lines 163–198) parses g, ml, fl oz, oz. Both functions are doing the right work.

**Unverified:** do `piecesPerServing` and `servingSizeG` survive the adapter from `Product` → persisted `Food`? Needs a trace through `FoodService` and the search-with-fallback path. If they're dropped at the seam, the regex effort is wasted. Likely a one-file fix.

OpenFoodFacts is branded-food focused; it does not have structured per-unit portions for generic whole foods the way USDA does.

### Coverage estimate for bulk enrichment of foods.json

Rough estimate (confirm with a 100-food sample run):

- **USDA-covered** (generic produce, grains, meats, dairy, USDA packaged): **~1,500 foods**
- **OFF-covered** (branded bars, yogurts, shakes, protein powders, cereals): **~400 foods**
- **Residual long tail** (Indian regional, South Indian breakfast, Bengali fish, Filipino/Ethiopian/Turkish): **~600 foods**. Needs nutritionist review or a grounded LLM pass (feed each food with its macros, ask for typical per-piece grams, review outliers ≥20% off a reasonableness prior).

---

## 5. Structural fixes (forward-looking)

Ranked by effect on the confirmed bugs.

- **Fix 1 — gate the synthesized fallback.** In `ServingUnit.swift:300–303` and the 117 `gramsEquivalent: ss` sites, stop offering a unit when its real gram weight is not known from a trusted source. The default set of units becomes `g` + `cup` + `serving`; specialized units (`piece`, `bowl`, `slice`, `scoop`) are only offered when backed by either a `pieceGrams()`/`cupGrams()` dictionary entry OR a new per-food override column. This single change resolves the strawberry screenshot and every sibling case.
- **Fix 2 — add per-food override columns on `Food`.** `pieceSizeG: Double?`, `cupSizeG: Double?`, `tbspSizeG: Double?`, `scoopSizeG: Double?`, `bowlSizeG: Double?`. With Fix 1 gating and Fix 2 data, "piece" comes back for strawberries with the right number.
- **Fix 2a — offline bulk enrichment.** One-shot script populates the new columns for the 2,511 existing entries from USDA `foodPortions` first, OpenFoodFacts second. Unresolved list goes to a separate nutritionist-reviewed or grounded-LLM pass. Commit as a reviewable diff.
- **Fix 2b — live online enrichment.** In `USDAFoodService.swift` parse `foodPortions` and propagate per-unit weights to `Food`. Verify `OpenFoodFactsService.Product.piecesPerServing` / `.servingSizeG` reach the persisted `Food`.
- **Fix 3 — UI honesty.** At `FoodLogSheet.swift:107`, don't print synthesized gram figures as if measured. Either suppress the `(Xg)` suffix for non-authoritative units or mark it as `(≈Xg)`. The UI amplifying a synthesized number is what kept this class invisible.
- **Fix 4 — end-to-end tests.** Ship `DriftTests/UnitConversionEndToEndTests.swift` with the 8 signatures from §3. Every change to `ServingUnit.swift` gated on keeping them green.
- **Fix 5 — hygiene (optional).** Extract the remaining legitimate tables (`pieceGrams`, `cupGrams`, nut per-piece, tbsp per-food) from 1,294 lines of Swift into a single JSON with a fallback chain. Reviewable by a nutritionist. Does not fix correctness on its own; unlocks Fix 2 scale.
- **Fix 6 — separate track: `findFood` silent guessing.** `AIActionExecutor.swift:230–272` nondeterministic tight-match, qualifier stripping, first-word fallback, silent spell-correct. Different file, same anti-pattern: guess and don't tell the user.

---

## 6. Honesty note

`Docs/roadmap.md` currently lists **"Smart Units cross-interface consistency (#156) — DONE"**. What "done" covers: the set of unit pills that get *offered* is consistent across UI and AI-chat entry points. What "done" does NOT cover: whether the kcal those units produce is correct. This audit's conclusion: the kcal path is silently wrong for up to **1,242 of 2,511 foods** depending on seed-author intent, with a confirmed **4× overcount** on the strawberry case.

Roadmap line should be updated to "Smart Units pill consistency" (not "Smart Units") with a separate line item "unit→kcal correctness (OPEN, #???)" linked to this audit.

---

## Verification checklist (per plan)

- [x] Section 1 table: every row has grep-verified `file:line`.
- [~] Section 2 table: 11 rows with predicted vs expected kcal. **Live sim run still required** to confirm predictions; audit document honestly labels them "predicted from static analysis."
- [x] Section 3 lists 8 missing test function signatures (≥5 required).
- [x] Section 4 contains actual counts from `foods.json` (2,511 total, 1,242 blast radius, 21 cup-named `g`-unit mismatches, 14 berry cluster).
- [x] Section 4b documents the USDA-data-discard and the OpenFoodFacts-handoff-unverified findings with file:line.
- [x] `rg -c "name.contains" ServingUnit.swift = 447`, `rg -c "if name.contains" = 181`, documented as "blast radius of the string-match approach."
- [x] **117 `gramsEquivalent: ss` sites** — the dominant anti-pattern — enumerated in row 8.
