# Sprint Board

Focus: **Per-Component Gold Sets + LLM Eval Quality (60%) + Features (40%).** Human feedback: AI chat is buggy, regressions happen, we evaluate poorly. This sprint: every pipeline stage gets its own isolated gold set. Then run end-to-end LLM eval, fix failures, expand coverage. AI chat is the entire product — evaluation is our immune system.

## Regression Gate

**All pipeline gold sets at 100% baseline.** Any AI change MUST run BOTH before AND after:
1. `xcodebuild test -only-testing:DriftTests/FoodLoggingGoldSetTests` (deterministic, ~2s)
2. `xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'` (LLM-loaded, ~5min — requires models at `~/drift-state/models/`, run `bash scripts/download-models.sh` first)

## In Progress

_(pick from Ready)_

## Ready

### P0 — Per-Component Gold Sets (NEW — human feedback priority)

- [x] **#161 Per-component isolated gold sets** — IntentClassifierGoldSetTests (22 cases: parseResponse/mapResponse JSON parsing + StaticOverrides routing), FoodSearchGoldSetTests (20+ cases: exact, Indian foods, synonyms, spell correction, partial match), SmartUnitsGoldSetTests (20+ cases: eggs, flatbreads, oils, proteins, liquids, grains, meats, vegetables). All deterministic, <1s, 1,577 tests pass. Commit baa492a.

### P0 — AI Chat Quality

- [x] **#158 LLM-loaded macOS eval: expand routing gold set** — 100% on all 27 test groups. Commit 7a0fbd0.
- [x] **#160 AI chat: expand eval gold set and fix routing gaps** — +5 new test groups (delete, exercise edge cases, Indian food slang, health negatives, multi-turn continuations). ~120 cases total (up from ~95). Key learning: Gemma 2B Q4 prompt capacity limit ~1 extra example before supplement/nav routing degrades. Commit 7a0fbd0.

### P1 — Voice + Features

- [ ] **#159 Voice input: investigate remaining bugs** — Silence timeout fixed (15s→30s). Race condition in forceStop/gracefulStop fixed (idle set before cleanup). Test on device: natural pauses, edit-after-stop, multi-sentence dictation. Fix any remaining issues found.
- [x] **#162 AIChatView.sendMessage refactor** — sendMessage extracted to AIChatViewModel (AIChatView+MessageHandling.swift, extension AIChatViewModel). 491-line monolith decomposed into 20+ private handlers. AIChatView.swift is now pure SwiftUI view code.

### P1 — Junior Tasks

- [x] **Food DB enrichment: +20 foods** — 2,167→2,187: Burger King Whopper Jr., Double Whopper, Crispy Chicken, Medium Fries, Crispy Veg (India), Paneer Royale (India); Subway Veggie Delite, Chicken Teriyaki, Tuna Sub; Domino's Margherita/Farmhouse slices, Garlic Breadstick; Gathiya, Surti Locho, Sev Mamra; Fage Total 0%, Two Good Vanilla; L-Glutamine, Collagen Peptides; Chipotle Burrito Bowl.

### P1 — Senior Implementation

- [x] **#151 Implement LLM-first lab report parsing (#74)** — Shipped (cycle 5228). Gemma 4 primary extractor with chunked inference, confidence scoring (≥0.85 LLM wins, ≥0.6 LLM-only included), regex validation layer, report date extraction (regex → LLM fallback), AI-parsed badge, accuracy warning banner. SmolLM fallback to regex-only path. Files: `Services/LabReportOCR.swift`, `Services/LabReportOCR+Biomarkers.swift`.

### P1 — Junior Tasks

- [x] **#156 Smart Units: cross-interface consistency audit** — 4 bugs fixed (Butter Chicken/tbsp, Chicken Parmesan/tbsp, Vindaloo/serving, Chicken Stock/serving). 5 regression tests added. All 3 interfaces verified consistent. Commit b237f4e.
- [x] **#157 Food DB enrichment: +20 foods** — 2067→2087: Sev Puri, Dahi Bhalla, Sprouts Chaat, Mini Idli, Masala Vada, Kotambri Vada, Kande Pohe, ON Gold Standard Whey, ONE Bar, KIND Protein Bar, Creatine Monohydrate, MyProtein Impact Whey, Isopure Zero Carb, Baked Oats, Shakshuka with Feta, Quiche, Breakfast Frittata, Gujiya, Basundi, Patishapta. Commit 51912a1.
- [x] **Food DB enrichment: +20 foods** — 2087→2107: Ragi Mudde, Sol Kadi, Tindora Sabzi, Gavar Sabzi, Vazhakkai Fry, Surmai Curry, Rawas Fish, Bangda Curry, Bombil Fry, Squid Stir Fry, Koliwada Prawn, Malvani Chicken Curry, Kombdi Vade, Saoji Chicken Curry, Amboli, Karanji, Undi, Tisrya Masala, Pathande, Masala Crab.
- [x] **#153 Test coverage** — All files pass thresholds (100% green). No fixes needed.
- [x] **#140 Exercise visual enrichment research** — Research complete. Doc at `Docs/designs/133-exercise-enrichment.md`: GO decision, free-exercise-db (MIT) for GIFs, YouTube manual curation for top 50. SENIOR impl task needed.

### Design Docs (approved — pending implementation slot)
- #66 Design: Exercise image/video enrichment — `doc-ready`, `approved`
- #133 Design-impl: Exercise image/video enrichment — research task (= #140 above)

---

## Permanent Tasks (never remove — always pick from these when nothing else is queued)

**AI chat quality is the product's core value. Every session must improve it. No sprint is complete without AI chat being better than when it started.**

**Before picking a task, read `Docs/roadmap.md` → "Now" items in the relevant domain. Work on what advances the current phase.**

### Auto-Research Loop (every sprint — automated, run at sprint start AND end)
The optimizer finds the best pipeline config, applies it, and pushes if regression-free. See `Docs/ai-autoresearch.md`.

- [ ] **Sprint start — record baseline:**
  ```
  xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
    -only-testing:AutoResearchTests/testBaseline
  ```
  Record score in sprint notes (routing %, params %, response %, per-category).

- [ ] **Run optimization loop (~40 min, gated):**
  ```
  DRIFT_AUTORESEARCH=1 xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
    -only-testing:AutoResearchTests/testAutoResearch
  ```
  Auto-applies winner if held-out ≥+1% with zero IntentRoutingEval regressions. Auto-reverts otherwise. Auto-pushes.

- [ ] **Eval enrichment (manual, separate PR):**
  Add 3–5 new `HardCase` entries to `DriftLLMEvalMacOS/HardEvalSet.swift` (isTrainSet: true).
  Sources: weakest perCategory from last run, new capability gaps observed in practice.
  Run `testHardEvalSetSanity` to confirm structure, then commit.

### LLM Eval Quality Loop (50% of every sprint — non-negotiable)
The eval is the product's immune system. It must grow every sprint or regressions will silently accumulate.

- [ ] **Every sprint: run → fix → expand → audit**
  1. **Run** `xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'` — any failure is a P0, fix it now
  2. **Fix via prompt first** — change an example, reorder, tighten the RULES line. StaticOverride only if prompt tuning fails twice
  3. **Expand** — add 3+ new test cases from real user phrasings (not keywords). Pick a domain with <5 cases and add variants
  4. **Audit** — pick one domain (sleep, exercise, supplements, etc.) and add 3 edge-case variants: messy spelling, implicit intent, slang. Run eval after each
  5. **Retire** — check if any StaticOverride is now handled by the LLM at 100%. Remove it if so
  6. **Track** in PR description: cases added this sprint, failures fixed, overrides removed. Eval case count must never decrease

### AI Chat Architecture & Quality (always ongoing)
Equally important pillar. Prefer architectural improvements over keyword additions.

- [ ] **State machine refactor** — Replace scattered pendingMealName/pendingWorkout state vars with a proper conversation state machine. States: idle -> classifying -> executing_tool -> confirming -> logging. Clear transitions, no dangling state.
- [ ] **Prompt consolidation** — Single source of truth for tool schemas, examples, context injection. Measure token count, compress.
- [ ] **Multi-turn reliability** — Eliminate bugs where context is lost between turns. Test: 3-turn meal logging, 3-turn workout building, topic switching mid-conversation.
- [ ] **Natural freeform logging** — "log for breakfast 2 eggs and spinach and bread and coffee with 2% milk with protein powder and creatine" or "log chipotle bowl with 800 calories" -> AI parses everything, asks clarifying questions, does macro calculations, logs it.
- [ ] **Meal planning** — "plan my meals for today" -> iterative suggestions based on remaining macros + history.
- [ ] **Workout split builder** — "build me a PPL split" -> multi-turn designing across sessions.
- [ ] **Navigate to screen** — "show me my weight chart", "go to food tab". Needs navigation tool.
- [ ] When no obvious gap: stress-test with 10 real-world queries per domain in IntentRoutingEval.swift, run eval, fix what fails.

### UI Overhaul (always ongoing)
Equally important pillar. Bold changes encouraged — a full theme redesign overnight is fine. New card styles, new color palette, new typography — go for it. The only rule: app-wide consistency.

- [ ] **Theme overhaul** — Pick a direction and execute across ALL views in one cycle. Dark+accent, light+minimal, glassmorphism — any coherent vision. Touch every view.
- [ ] **Dashboard redesign** — Better information hierarchy, scannable at a glance, clearer progress indicators.
- [ ] **Chat UI polish** — Message bubbles, typing indicators, tool execution feedback, streaming UX.
- [ ] **Food diary UX** — Faster logging flow, better meal grouping, clearer macro display.
- [ ] **Usability rough edges** — Find confusing flows, missing feedback, awkward transitions. Fix them.
- [ ] UI changes must NOT break existing functionality. Visual-layer refactoring only.

### Test Coverage Improvement (always ongoing)
Ship quality. Coverage is a forcing function for finding bugs and understanding code.

- [ ] **Run coverage-check.sh** — Identify files below 80% (logic) or 50% (services) threshold. Fix them.
- [ ] **Write tests for uncovered paths** — Focus on error paths, edge cases, empty states, boundary conditions. Not just happy paths.
- [ ] **AI eval harness expansion** — Add test cases for every new capability. Target: every tool has 10+ eval queries.
- [ ] **Integration-style tests** — Test multi-step flows (parse -> resolve -> log -> confirm) end-to-end.

### Bug Hunting (always ongoing)
Proactively find bugs before users do.

- [ ] **Find and fix bugs** — Run the app mentally through edge cases. Check error paths, empty states, boundary conditions, data corruption scenarios.
- [ ] **Regression prevention** — When fixing a bug, add a test that would have caught it.

### Food Database Enrichment (always ongoing)
Better the DB, more people will come and log. Benchmark: MyFitnessPal has 14M+ foods.

- [ ] **Correct existing entries** — Find foods with wrong macros, missing data, bad serving sizes. Fix them.
- [ ] **Add missing foods** — Indian foods, regional dishes, restaurant items, branded products. Cross-reference with USDA/reliable sources.
- [ ] **Improve search** — Better aliases, spelling corrections, partial matches. "paneer" should find all paneer dishes.

### Ongoing: Code Improvement Loop
Autonomous refactoring. Run `code-improvement.md`. Principles in `Docs/principles/`. Log in `Docs/code-improvement-log.md`.

- [x] **Continue file decomposition** — GoalSetupView, LabsAndScans, Sleep, TemplatePreviewSheet extracted. Only 3 files over 700 remain (AIChatView, FoodTabView, ActiveWorkoutView) — these need ViewModel extraction.
- [ ] **Deeper refactoring** — Extract logic from fat functions (AIChatView.sendMessage 491 lines). Move business logic out of views into ViewModels/Services.
- [ ] **DDD violations** — Direct DB calls in views, business logic in UI layer.

## Done (this sprint)

- [x] **#151 LLM-first lab report parsing** — Shipped (cycle 5228). Gemma 4 primary extractor, chunked inference, confidence scoring (≥0.85 LLM wins), regex validation layer, AI-parsed badge.
- [x] **#156 Smart Units cross-interface consistency** — 4 bugs fixed, 5 regression tests added.
- [x] **#157 Food DB enrichment: +20 foods** — 2,067→2,087.
- [x] **Food DB enrichment: +20 foods** — 2,087→2,107 (Maharashtrian/Goan/seafood batch).
- [x] **#153 Test coverage** — All files pass thresholds._

## Done (previous sprint — AI Chat P0 Fixes + Smart Units Audit)

- [x] #147 Bug: "Daily summary" tries to log food named "daily summary" — intent routing fixed, regression test added.
- [x] #148 Bug: "Weekly summary" query broken — same class fix, test added.
- [x] #149 Bug: "Log 2 eggs" adds egg benedict — food search ranking + SmartUnits egg rules fixed, test added.
- [x] #150 Bug: AI chat regressed broadly — LLM eval lite run, failure modes identified and restored. Gold set at 100%.
- [x] #154 AI eval: gold set at 100% verified post P0 fixes.
- [x] #152 Food DB enrichment: +20 foods (2,047→2,067): Bedmi Puri, Sooji Halwa, Anda Paratha, Churma Ladoo, Rajma Rice, Poha Cutlet, Ghevar, Imarti, Green Moong Dal, Sheer Khurma, Tawa Pulao, Methi Matar Malai, Oats Upma, Navratan Korma, Kathal Ki Sabzi, Lobia, Aloo Baingan, MuscleBlaze Biozyme Whey, Ghost Whey Protein, Masala Chai Powder.
- [x] #137 Smart Units: Complete audit of all 2,046 foods — serving count at ~65 (intentional nuts/canned). Eggs plural, bhaji, ras malai, kulfi, scone, cashew/pesto ordering, whey word-boundary, sambhar variant, rogan josh/sorpotel/rista/methi malai/balchao → bowl, orange chicken → bowl, sub/6-inch sandwiches → piece, biltong → strip, dressing → tbsp, half and half → tbsp, crab meat → cup, crab → piece, karela/bitter gourd → piece, lobia → cup, frosty → scoop.

## Done (two sprints ago — Multi-Stage LLM Pipeline)

- [x] #129 Stage 0+1: Wire pipeline skeleton in AIToolAgent
- [x] #92 Stage 2: Intent classifier (classification-only prompt)
- [x] #95 Stage 3: Domain-specific extraction prompts
- [x] #93 Prune StaticOverrides to ~10 essential patterns (Gemma path)
- [x] #94 Retire ToolRanker keyword scoring (Gemma path)
- [x] #96 Coverage: Pipeline refactor tests
- [x] Smart Units: rice→cup, protein powder→scoop, pasta/noodles→cup, dal/beans→cup
- [x] Smart Units: portionText fixes (bread→slices, pizza→slices, soup→bowls, momos→pieces)
- [x] Food DB: 1,641→1,927 (+286 foods across 5 junior cycles)
- [x] Synonym expansion: +24 South Indian, Middle Eastern, Bengali, Tamil terms
