# Sprint Board

Focus: **AI Chat Quality (every sprint until excellent).** AI chat is the entire product. Every session must improve it. Primary: per-component eval gold sets + LLM-loaded macOS eval + voice reliability. Secondary: Smart Units cross-interface + food DB enrichment.

## Regression Gate

**All pipeline gold sets at 100% baseline.** Any AI change MUST run BOTH before AND after:
1. `xcodebuild test -only-testing:DriftTests/FoodLoggingGoldSetTests` (deterministic, ~2s)
2. `xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'` (LLM-loaded, ~5min — requires models at `~/drift-state/models/`, run `bash scripts/download-models.sh` first)

## In Progress

_(pick from Ready)_

## Ready

### P0 — AI Chat Quality (pick first, every sprint)

- [ ] **#158 LLM-loaded macOS eval: expand routing gold set** — `DriftLLMEvalMacOS` target is wired and builds. Download models (`bash scripts/download-models.sh`), run eval, find any routing failures, fix them in the pipeline (IntentClassifier prompt or validateExtraction). Target: 100% on IntentRoutingEval tests. Run after every IntentClassifier/AIToolAgent change.
- [ ] **#159 Voice input: investigate remaining bugs** — Silence timeout fixed (15s→30s). Race condition in forceStop/gracefulStop fixed (idle set before cleanup). Test on device: natural pauses, edit-after-stop, multi-sentence dictation. Fix any remaining issues found.
- [ ] **#160 AI chat: expand eval gold set and fix routing gaps** — Run `DriftLLMEvalMacOS` eval. For each failure: fix in IntentClassifier prompt first (preferred), fall back to StaticOverrides only if LLM cannot be taught. Add regression test to IntentRoutingEval.swift. Target 100% routing accuracy. Do NOT grow StaticOverrides unless prompt engineering fails after 2 attempts.

### P1 — Senior Implementation

- [ ] **#151 Implement LLM-first lab report parsing (#74)** — Per `Docs/designs/74-lab-reports-llm.md`. Gemma 4 as primary extractor (chunked, ~500 tokens/chunk), regex as validation layer. Add: confidence scoring, report date extraction (regex → LLM fallback → date picker), AI-parsed badge in biomarker history, accuracy warning banner in preview. SmolLM devices use existing regex-only path. Files: `Services/LabReportOCR.swift`, `Services/LabReportOCR+Biomarkers.swift`, `Models/BiomarkerResult.swift`. Tests required.

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

_(empty — sprint just started)_

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
