# Drift Product Roadmap

## Vision

Two equally important pillars:
1. **AI chat that handles 90% of interactions** — type what you did, AI does the rest. Apple Foundation Models is now the on-device intelligence layer powering chat + structured extraction (food parsing, label OCR, workout transcripts, lab reports).
2. **Beautiful, fast, opinionated health tracking UI** — charts, diary, insights that are world-class. V7 (light theme, 3-tab IA, black floating FAB, donut hero, palette retired pink-as-default) is the active design direction.

Neither is secondary. Every improvement should advance one or both pillars.

Privacy-first: everything on-device, no cloud, no accounts. This is non-negotiable. BYOK cloud chat is opt-in and clearly indicated.

## Current Phase: V7 refresh + AI depth (May 2026 — V7 reset)

**Sprint queue reset on 2026-05-19.** All open `sprint-task` issues filed prior to that date were closed as part of the V7 visual refresh; planning starts fresh after this commit. Product focus tenets updated — see Issue #111 — to add tenet #0 (Apple Foundation Models is the on-device intelligence layer; AI chat depth is the next focus) and revise tenet #10 (V6 → V7 visual direction).

**Shipped 2026-05-19 (builds 256+, V7 phases 1/3-partial/4):**
- Theme palette tokens — `Theme.ink` (#0A0A0A) added as the V7 primary CTA color, semantic macro tokens (`macroKcal/Protein/Fiber/Carbs/Fat`), legacy names kept as aliases.
- More tab regrouped into ACTIVITY / HEALTH / APP sections per V7 reference. Photo Log renamed "Bring Your Own Key" and moved under APP. AI Assistant toggle removed (FoundationModels is always-on, no longer requires a download gate).
- 3-tab IA collapse — V6 five tabs (Drift / Weight / Food / Exercise / More) → V7 three (Today / Body / More). Food + Exercise removed from primary tabs; Food lives behind the FAB, Exercise lives under More → Activity. Custom floating white pill tab bar + black "+" FAB (56pt circle, ink fill) to the right.
- Weight chart visibility fix — EMA line + points flipped from `.white.opacity(0.7)` (invisible on white card) to `Theme.accent` (coral on paper-white per reference). X-axis format includes day so a single-day data range doesn't render "May May May".
- WeightInsightsView chip-row contrast — 3d/7d/14d/30d/90d labels + "--" placeholders flipped from `.tertiary` to `Theme.textSecondary` with semibold weight.
- WorkoutView red-button retirement — Start Workout / Coach Me / Browse Exercises / in-progress banner flipped from `Theme.accent` to `Theme.ink`.
- FloatingAIAssistant Simulator skip — `#if targetEnvironment(simulator)` short-circuit shows "AI not available in Simulator" instead of downloading 600 MB of weights that the Sim resets anyway.
- SettingsView pink retirement — 22 `Theme.accent` sub-row icons flipped to `Theme.textSecondary`, toggles re-tinted to `Theme.ink`. Root `.tint(Theme.textPrimary)` so button labels read charcoal instead of inheriting system coral.

**Queued V7 work** (will be filed as sprint-tasks by the next planning cycle):
- **Phase 2 — Today donut redesign.** 3 concentric rings (kcal coral / protein green / fiber blue) with center kcal number, macro grid beneath (kcal/protein/fiber + carbs/fat), Log section with 4 method cards (Snap/Voice/Search/Recent), vertical meal timeline with dot rail, body summary cards (WEIGHT/SLEEP/READINESS), coach nudge card with sun icon.
- **Phase 3 proper — Body screen unification.** Replaces WeightTabView. Merges weight chart + Rhythm (sleep ring + HR/RESP/READINESS) + Glucose chart + Composition row (Body Fat / Lean Mass / Fat Mass) + Biomarkers into one scrolling Body screen.
- **Phase 5 — Sheet redesigns.** Drift Coach sheet (replaces FloatingAIAssistant, with visible model selector for Apple FM / local / BYOK cloud), redesigned Log-a-Meal sheet (4-mode segmented Recent/Search/Voice/Snap), Exercise History sheet with filter pills, Weight Goal clean redesign.
- **Pink retirement remainder.** ~270 `Theme.accent` sites left across dashboard cards, food list, supplements, biomarkers, glucose. Cleaned as each view is rewritten.
- **AI chat depth** (per tenet #0). Multi-turn reliability eval gate, FM-driven extraction surfaces beyond chat (free-text food parsing, exercise transcript, lab report hybrid), per-screen nav-bar chat icon, Drift Coach prompt-suggestions surfaced contextually.

What's *not* working (V7 reset closed the prior open-issue list; this is the new short backlog):
- Today + Body screens still on V6 internals — V7 IA shell wraps them but the inner views haven't been redesigned yet. Pixel mismatch with the reference mocks until Phase 2/3 land.
- Drift Coach is still the V6 floating bubble until Phase 5.
- AI access on Simulator is correctly blocked, but the BYOK cloud-key path doesn't yet surface from the chat sheet (user has to find it under More → Bring Your Own Key).

---

## AI Chat

### Now
- ~~**Voice input (P0)**~~ SHIPPED — Mic button, on-device SpeechRecognizer, streams into chat. Real-device crash fixed (audio engine prepare). Voice UX overhaul fixed eaten-words bug (partial vs final transcription handling). Build 107.
- ~~**Prompt consolidation (P1)**~~ DONE — Dead code removed, token budget safety added.
- ~~**State machine refactor**~~ DONE — ConversationState.Phase enum (idle/awaitingMealItems/awaitingExercises) replaces 5 scattered pending vars.
- ~~**Multi-turn reliability**~~ DONE — Topic switch detection, stale state cleanup. Context preservation across turns.
- ~~**Natural freeform logging**~~ DONE — AI parses, splits "with" items, resolves each, opens recipe builder.
- ~~**Meal planning dialogue (P0)**~~ DONE — "plan my meals today" → iterative suggestions based on remaining macros + history. `planningMeals` phase in state machine.
- ~~**Workout intelligence in chat (P0)**~~ DONE — "How's my bench?" returns trend, last weight, unit-respecting display.
- ~~**AI pipeline bug fixes (P0)**~~ DONE — 3 P0 bugs fixed: integer servings, calcium/calorie regex, undo action tracking.
- ~~**Proactive insight alerts (P0)**~~ DONE — Protein streak alert + supplement gap alert on dashboard.

### Now
- ~~**Chat navigation (P0)**~~ DONE — "Show me my weight chart" switches tabs. Static overrides + LLM tool. Chat collapses on navigate.
- ~~**Wire USDA into AI chat (P1)**~~ DONE — Chat uses searchWithFallback when local food not found. log_food preHook + food_info handler both fall back to USDA/OpenFoodFacts.
- ~~**Rich confirmation cards (P0)**~~ DONE — Navigation cards, activity preview cards, weight/workout cards. All chat actions show structured visual feedback.

### Now
- ~~**AI Chat reliability (P0)**~~ DONE — 6-stage pipeline shipped: input normalization, LLM intent classifier, domain extraction, Swift validation, streaming presentation. 55-query gold set at 100% baseline.
- ~~**AI Chat depth (P0, cycle 341 sprint)**~~ MOSTLY DONE — Time-aware pills, meal-period auto-detect, streamed stage-label indicator, nutrition-lookup card, 25-turn multi-turn regression suite all shipped. Context window doubled 2048→4096 with long-context eval. Prompt token audit 16% compression. Routing +4.3% from simpler intent prompt.
- ~~**AI Chat depth — final three (P0, cycle 1159 sprint)**~~ DONE — #207/#208/#209/#210/#212 all merged. Threading, `edit_meal`, session-persistent state, confidence calibration, per-stage eval harness.
- ~~**AI Chat depth — trust & precision (P0, cycle 2000 sprint)**~~ DONE — #226/#227/#228/#229 all merged. Per-tool gold set at 96% overall, clarification dialogue live, cross-turn entry refs working, prompt compression −20–38% per stage.
- ~~**AI Chat depth — extractor reliability & cross-domain flow (P0, cycle 2605 sprint)**~~ DONE — DomainExtractor 50-query gold set, tool-call auto-retry, cross-domain pronoun resolution, clarification calibration v2 all merged. Food DB to 2,511. Test suite to 1,677+.
- **AI Chat depth — failing-query category closure (P0, cycle 3022 sprint)** — Close 4 known failing-query categories: correction-as-replacement (#253), historical date queries (#254, e.g. 'last Tuesday'), non-weight goal setting (#255, 'set calorie goal to 2000'), micronutrient queries (#257, fiber/sodium persisted). Plus composed-food calorie audit (#256, 'coffee with milk' → 0 kcal bug). Locked behind +20 gold-set cases (#260) and +12 multi-turn regression cases (#259). Opt-in on-device telemetry (#261) to surface real failures beyond gold sets. Food DB +60 (South Indian #258, desserts #262). Goal: every failing-query category from \`Docs/failing-queries.md\` Failing section either fixed or has a test pinned to the root-cause stage.
- ~~**AI Chat depth — reliability infra & discoverability (P0, cycle 3585 sprint)**~~ MOSTLY DONE — #284/#285/#286/#287 all merged. Macro goal %, voice health-term repair, SmolLM↔Gemma parity, latency TTFT CI smoke shipped. Photo Log multi-provider (OpenAI + Gemini added via #298). Telemetry raw-text persistence (#297). Intent classifier 'log X' routing fix (#277).
- **AI Chat depth — Photo Log hardening & telemetry-driven reliability (P0, cycle 3985 sprint)** — Photo Log provider fallback chain (#300 → queue #359). `/debug last-failures` chat command (#301 → queue #360). IntentClassifier per-domain confidence thresholds (#302). PhotoLogTool eval +12 provider-failure cases (#303 → queue #361). Gold-set +15 branded food variants — Chobani/Quest/Kodiak (#304 → queue #362). Multi-turn regression +10 photo-log corrections (#306 → queue #363). Per-stage elapsed indicator (#309). Food DB +60 (Caribbean #305 → queue #364, breakfast cereals #308 → queue #365). failing-queries.md refresh (#307 → queue #366). East Asian home cooking → queue #367. FoodLoggingGoldSet run + fix failures → queue #358.
- **AI Chat depth — pipeline attribution, tie-break, and multi-turn depth (P0, cycle 4247 sprint)** — Per-stage failure attribution on FoodLoggingGoldSet so we know *which* of the 6 stages fails (#312). IntentClassifier tie-break when top-1/top-2 scores are close — handles confusion (distinct from confidence #302) (#313). Multi-turn entry-reference across 3+ turn chains with ordinal + attribute resolution (#314). Context window bump 4096→6144 with per-stage prompt audit so growth goes to conversation, not bloat (#315). Ambiguous-food clarification card — tap-to-choose UI replaces freeform clarify text (#316). First analytical tool: `cross_domain_insight` for correlational queries across food/weight/exercise/glucose (#317). ~~SHIPPED~~. Multi-turn regression +10 entry-ref corrections (#318). Gold-set +15 clarify-correct cases — where asking *is* the right answer (#319). Food DB +30 Korean home cooking (#320). Voice post-transcription repair +10 biomarker/lab terms — A1C, triglycerides, LDL, HDL, TSH, ferritin, B12, cortisol (#321).
- **AI Chat depth — analytical tools + telemetry-driven quality (P0, cycle 4487 sprint)** — `glucose_food_correlation` analytical tool: "do I spike after rice?" — correlates glucose readings with foods logged ±2h (#324). DomainExtractor Stage 3 isolated 50-query gold set — closes last eval infra gap (#325). Telemetry-driven intent classifier prompt refresh — analyze persisted telemetry, update examples, add 5+ eval cases (#326). FoodLoggingGoldSet +15 analytical query cases (#328). Food DB +30 South Asian/Pakistani specialties (#327). Settings → Feedback row — close 5-cycle feedback vacuum (#329). PhotoLog BYOK first-use onboarding tip (#331). failing-queries.md refresh cycle 3985→4487 (#330).
- **AI Chat depth — analytical breadth & cross-session context (P0, cycle 4815 sprint)** — `supplement_insight` analytical tool: adherence %, streak, gaps per supplement (#369). `food_timing_insight` analytical tool: meal timing patterns, avg time per meal period, late-night eating detection (#370). Cross-session conversation context: persist last 5 turns to disk, inject at session start for continuity (#371). LLM prompt quality audit from telemetry: cluster top failure modes, improve Stage 1/3 prompts with targeted few-shot examples, add 10+ eval cases (#372). Food DB +30 German/Austrian/Swiss cuisine (#373). Food DB +30 Greek & Balkan cuisine (#374). FoodLoggingGoldSet +12 informal portion language cases (#375). MultiTurnRegression +8 log→wrong-amount→correct chains (#376). Dashboard active calories burned ring (#377). failing-queries.md refresh cycle 4774→4815 (#378).
- **AI Chat depth — hydration, multi-intent & smart reminders (P0, cycle 4933 sprint)** — Hydration tracking via AI chat: `log_water` tool + daily hydration in summary (#383). Multi-intent splitting: "log lunch and update weight" executes both tools sequentially (#384). Smart meal reminder notifications: contextual "Did you log X?" based on meal timing patterns (#385). FoodLoggingGoldSet +15 hydration, multi-intent, and non-English food name cases (#386). Food DB +30 Indian protein staples (dal varieties, paneer, egg curries) (#387). Food DB +30 American fast food chains (McDonald's, Burger King, Taco Bell) (#388). Dashboard food variety score insight card (#389). MultiTurnRegression +8 analytical query follow-up chains (#390). failing-queries.md refresh cycle 4877→4910 (#391). Planning service stall-on-exit fix (#382).
- ~~**AI Chat depth — eval quality, tie-break & analytical expansion (P0, cycle 4949 sprint)**~~ PARTIALLY DONE — Telemetry-driven Stage 1/3 prompt refresh (#399) ✅. `weight_trend_prediction` analytical tool (#402) ✅ shipped build 169. Remaining in queue: State.md refresh (#410), FoodLoggingGoldSet run (#411), IntentClassifier tie-break (#396), Food DB +30 Middle Eastern (#397), Food DB +30 Mexican (#398), MultiTurnRegression +5 (#400), failing-queries.md refresh (#412). Queue cap of 70 sprint tasks enforced — no new tasks until queue drops below 70.
- **AI Chat depth — analytical tools & eval hygiene (P0, cycle 5351 sprint)** — `supplement_insight` analytical tool: adherence %, streak, gaps per supplement (#417). `food_timing_insight` analytical tool: meal timing patterns, avg time per meal period, late-night eating detection (#418). FoodLoggingGoldSet run cycle 5351 (#411). State.md refresh to build 169 (#410). failing-queries.md refresh cycle 4975→5351 (#412). Food DB +30 Indian protein staples (#413). Food DB +30 American fast food chains (#414). Queue hygiene: re-validate stale tasks #253–#258 (#415). MultiTurnRegression +8 hydration + multi-intent correction chains (#416).
- **AI Chat depth — sleep correlation, prompt quality & eval freshness (P0, cycle 5590 sprint)** — `sleep_food_correlation` analytical tool: last meal time vs sleep quality (#426). LLM prompt quality audit cycle 5590 — telemetry-driven Stage 1/3 refresh (#427). FoodLoggingGoldSet run cycle 5590 (#420). State.md refresh to build 171 (#421). failing-queries.md refresh cycle 5351→5590 (#422). MultiTurnRegression +8 supplement/hydration follow-up chains (#425). FoodLoggingGoldSet +10 hydration/supplement edge cases (#428). Food DB +30 American brunch & diner (#423). Food DB +30 international breakfast (#424). Queue pruned 113→81 (32 stale/superseded tasks closed).
- **AI Chat depth — unit integrity, cross-session context & eval freshness (P0, cycle 5899 sprint)** — FoodLoggingGoldSet run cycle 5899 (#430). State.md refresh to build 172 (#431). failing-queries.md refresh cycle 5590→5899 (#432). Bulk piece-size enrichment script — USDA/OFF pass for ~2,000 foods (#433). Idli-class multi-piece schema fix (#434). TestFlight build 172 re-archive — clear DerivedData (#435). Cross-session conversation context: persist last 5 turns, inject at session start (#436). Food DB +30 Mediterranean & Levantine cuisine (#437).
- **AI Chat depth — failing-query closure & goal system expansion (P0, cycle 5965 sprint)** — Historical date queries in food_info (#439). Non-weight goal setting — macro/calorie goals (#440). Macro goal progress queries — goal vs actual (#441). Micronutrient per-entry tracking — fiber/sodium/sugar on FoodEntry (#442). FoodLoggingGoldSet +12 for 4 failing categories (#443). MultiTurnRegression +8 goal-setting chains (#444). Food DB +30 East Asian home cooking (#445). Food DB +30 Caribbean & island cuisine (#446). /debug last-failures chat command (#447). PhotoLog eval +12 provider failure cases (#448). IntentClassifier tie-break v2 context-aware (#449). Food DB +30 Southeast Asian cuisine (#450). LLM prompt quality audit cycle 5965 (#451). failing-queries.md refresh cycle 5899→5965 (#452). TestFlight build 173.
- ~~**AI Chat depth — test infra migration & 2 failing-query closures (cycle 7448 review)**~~ DONE — Historical weekday queries fixed (`weekdayDateString()` + `historicalDaySummary()`). Calorie goal setting fixed (`WeightGoal.calorieTargetOverride` via StaticOverrides). DriftCore pure-logic test migration complete: all pure-logic tests in `DriftCoreTests` (`swift test`, 0.1s vs 30s simulator). 5-tier test map in CLAUDE.md. Build 175 on TestFlight.
- ~~**AI Chat depth — prompt quality, gold set & analytical expansion (P0, cycle 7485 sprint)**~~ PARTIALLY DONE — FoodLoggingGoldSetTests run (#457) ✅. LLM prompt audit (#458) ✅. `weight_trend_prediction` tool (#463) ✅ build 176. Micronutrient tracking (#442) ✅. Macro goal progress (#441/#440) ✅. Calorie goal setting ✅. Historical date queries ✅. Still open: State.md refresh (#459), failing-queries.md (#460), Food DB German/Greek (#461/#462), Indian meal combos goldset (#464), USDA Phase 2 (#345).
- ~~**AI Chat depth — eval closure & analytical expansion (P0, cycle 7564 sprint)**~~ PARTIALLY DONE — Food DB West African (#474) ✅, Japanese home cooking (#475) ✅. Still queued: FoodLoggingGoldSetTests run (#468/#481), LLM prompt audit (#469/#483), FoodLoggingGoldSet +12 (#470), MultiTurnRegression +8 (#471), State.md refresh (#472/#482), failing-queries.md (#473/#486). Still open: supplement_insight (#417), food_timing_insight (#418), planning crash fix (#407), USDA Phase 2 (#485 batch import).
- ~~**AI Chat depth — analytical tools, eval coverage & USDA batch import (P0, cycle 7689 sprint)**~~ PARTIALLY DONE — USDA Phase 2 batch import 500+ foods (#484) ✅. FoodLoggingGoldSetTests run + fix failures (#482) ✅. LLM prompt audit cycle 7689 (#483) ✅. IntentClassifier tie-break v2 (#449) ✅. /debug last-failures (#447) ✅. Still open: supplement_insight (#417), food_timing_insight (#418), State.md refresh (#481), failing-queries.md refresh (#485/#486), USDA DEMO_KEY (#488), planning crash fix (#407).
- ~~**AI Chat depth — campaigns: photo logging recovery, remote model prep, zero user math (P0, cycle 7724 sprint)**~~ PARTIALLY DONE — Photo-log recovery complete (editable card #495, free-text correction #496) ✅. Remote backend live (BYOK, 3 providers, SSE streaming, #494) ✅. Photo-attached meal logging with propose_meal card (#518) ✅. Backend toggle + privacy notice fix (#540) ✅. RemoteBackendError fallback + retry (#519) ✅. Zero user math: calories-left + multi-item totals (#502) ✅. Portion scaling gold set (#498) ✅. Still open: unit conversion in food logging (#552 — WIP patch from #497), supplement_insight (#550), food_timing_insight (#551). Build 192 on TestFlight.
- ~~**AI Chat depth — campaign completion + analytical tools (P0, cycle 7784 sprint)**~~ PARTIALLY DONE — Cross-session context (#506) ✅. RemoteLLMBackend streaming integration test (#512) ✅. Photo-log DB-hint matching inline (#505 via #525 shipped in 8274). Still open: supplement_insight (#550), food_timing_insight (#551), State.md refresh (#553), failing-queries.md refresh.
- ~~**AI Chat depth — analytical tools + zero-user-math completion (P0, cycle 8519 sprint)**~~ PARTIALLY DONE — Unit conversion (#552) ✅. Gold set coverage (#554) ✅. USDA DEMO_KEY injectable (#555) ✅. South Indian +30 (#557) ✅. Weight chart tap UX (#558) ✅. Portion multiplier phrases (#559) ✅. Still open: supplement_insight engine (#565), food_timing_insight engine (#566), State.md refresh (#567).
- ~~**AI Chat depth — analytical tool engines + eval quality + food DB depth (P0, cycle 8581 sprint)**~~ MOSTLY DONE — supplement_insight engine (#565) ✅. food_timing_insight engine (#566) ✅. State.md refresh (#567) ✅. failing-queries.md refresh (#570) ✅. FoodLoggingGoldSet run (#571) ✅. Indian branded protein +30 (#572) ✅. Recent foods quick-log (#573) ✅. GLP-1 design doc (#574) ✅. Still open: Fix testPortionScaling_DecimalServings (#568), Fix testRouterPrompt_TokenCeiling (#569).
- ~~**AI Chat depth — GLP-1 tracking, test fixes & feedback loop (P0, cycle 8666 sprint)**~~ MOSTLY DONE — GLP-1 medication tracking (#580) ✅. Fix testRouterPrompt_TokenCeiling (#569) ✅. Food DB +185 across 10 cuisines ✅. Accessibility labels fix ✅. Coverage: ExerciseService 5→67%, TDEEEstimator 29→55% ✅. Still open: Fix testPortionScaling_DecimalServings (#568→#587), Settings → Feedback (#329→#588), Planning crash (#407→#589), Per-stage elapsed indicator (#309→#597), State.md refresh (#591).
- ~~**AI Chat depth — GLP-1 depth, eval quality & test hygiene (P0, cycle 8789 sprint)**~~ PARTIALLY DONE — Food DB +30 Rajasthani/Gujarati/Andhra/German (#596) ✅. supplement_insight routing fix ✅. Pre-existing test failures fixed + StaticOverrides Tier-0 suite ✅. Still open: testPortionScaling (#616), Settings→Feedback (#617), Planning crash (#619), GLP-1 reminders (#620), FoodLoggingGoldSet run (#605), failing-queries refresh (#607), LLM prompt audit (#608), per-stage elapsed (#618), MultiTurnRegression +8 (#609).
- **AI Chat depth — proactive insights, food diary UX & biomarker intelligence (P0, cycle 8945 sprint)** — Protein adherence proactive alert (#627). Workout consistency card (#635). Food diary meal grouping (#629). Food diary inline edit (#630). Glucose spike detection analytical tool (#631). Progressive overload alert (#633). Food DB +30 West African/Ethiopian/Turkish/Persian (#634). AI cross-session context persistence (#636). Dashboard macro rings redesign (#628). INFRA: TestFlight watchdog backoff (#626).
- ~~**Reliability + delivery sprint (P0, cycle 8999 sprint)**~~ DONE — TestFlight unblocked (builds 224, 225, 226 published 2026-05-06/07); 17-build dark stretch ended. All planned tasks shipped: TestFlight hook suppression (#640), version-bumping circuit-breaker (#641), heartbeat batching (#642), State.md pre-commit hook (#643), State.md refresh (#644), command-center TestFlight panel (#645), releases.json reconciliation (#646), AIChatView extraction (#647), proactive-triad verification (#648). Settings → Feedback (#617) shipped after 12-cycle deferral. Plus: launch watchdog defer fix (36f0cb12), photo log JSON extract fix (#650), recipe builder bypass (#651).
- **Activation + quality floor sprint (P0, cycle 9441 sprint)** — TestFlight is unblocked but testers have no signal of what changed. Two flagship-surface regressions (#650 photo log, #651 recipe builder) shipped before catch-tests existed. This cycle: ship the chat smoke test (#655 SENIOR) before more chat features land, build the in-app "What's New" sheet (#656 surfaces 17-build catch-up), surface the proactive-coach narrative in TestFlight release notes (#659). Plus quality floor: fix or gate the 4-review-old test failure #568 (#657), verify heartbeat batching actually shipped correctly (#658), refresh State.md to build 226 (#660). Recurring AI quality: failing-queries.md refresh (#661), FoodLoggingGoldSet run (#663). Competitive response to MacroFactor cookbook scan: Food DB +30 home-cooking favorites (#664). Hold feature work to ≤2 analytical tools or food DB additions until user signal arrives via #617.
- ~~**Crash hunt + analytical breadth + UX refinement sprint (P0, cycle 9688 sprint)**~~ PARTIALLY DONE — Multi-intent splitting (#688) ✅, `cycle_biomarker_correlation` (#689) ✅, smart meal reminders (#690) ✅, crash hunt #687 (NSNull/non-primitive backup filter) ✅. iCloud backup engine: Sections B/C/D + ring buffer + Codable+arrays + allowlist hardening (#674, #675, #676, #700, #701) ✅. Build 235 published. Still open: Settings → Backup UI (#679), South Indian +30 (#691), goal milestone (#692), hydration card (#693), exercise muscle icons (#697), food diary row density (#696), failing-queries refresh (#694), FoodLoggingGoldSet (#695), State.md refresh (#698).
- **Backup-ship + quality-floor-validate sprint (P0, cycle 9760 sprint)** — Surface iCloud backup and dogfood end-to-end (#708, pairs with #679). Expand ChatPathSmokeTests to cover the new analytical tools — cycle_biomarker, multi-intent, smart-reminder paths (#709). TestFlight release notes — coaching narrative for next 2 builds (#710). State.md refresh to build 235 (#711). failing-queries.md refresh 9688→9760 (#712). FoodLoggingGoldSet run cycle 9760 (#713). Process: enforce qa-scope: declaration in new sprint-task bodies (#714, Engineer's debate ask). Active crash hunt on recent backup/restore code (#715, tenet #8). Heartbeat batching audit — investigate persistent log noise (#716). All new tasks declare qa-scope.
- ~~**Surface-and-discipline sprint (P0, cycle 9792/9794)**~~ MOSTLY DONE — Backup surface (#679) + engine + nightly scheduler ALL SHIPPED (#677/#678/#679). qa-tester verdict audit closed (#722). Active crash hunt closed (#723). Senior queue diversified with `protein_consistency_vs_recovery` (#730). Cycle 9794 prompt refresh shipped (#735). `sleep_food_correlation` (#736) and `cross_domain_pattern_detector` (#739) analytical tools shipped. Still open: E2E backup dogfood (#708), #568 portion-scaling (now 7 reviews open), Settings → Feedback null traffic.
- ~~**Validate-and-discipline sprint (P0, cycle 9851 sprint)**~~ MOSTLY DONE — Heartbeat noise root-caused (#758) ✅, #568 procedural loop closed (#757) ✅, Dashboard 7-day Feedback activation banner shipped (#759) ✅. IntentClassifier per-domain calibration (#762) ✅. Still open: #708 backup E2E dogfood (3rd cycle), #743 unified FoodLogIntent (last FM Quick Win), #753 medication Settings tab, #761 East Asian cuisine ship, #763/#764/#765/#766 hygiene tasks.
- ~~**Unblock-and-validate sprint (P0, cycle 10262 sprint)**~~ MOSTLY DONE — TestFlight 243 unblocked (#770) ✅, 6 builds shipped 244-250. FM extractor Tier-3 eval gate (#771) ✅. Crash hunt #772 ✅. CycleBiomarker insight (#778) ✅. V6 visual evolution Elements 1-3 shipped (#782). FoundationModelsBackend chat backend wired (`4f0f1d4f`). Still open: #708 backup E2E dogfood (4th cycle), Settings → Feedback null traffic, FM extractor flag-on cutover pending eval.
- **Activate-and-validate sprint (P0, cycle 10888 sprint)** — Build `human-action.md` register + migrate #708 with named owner + 48h deadline (#789 SENIOR). Diagnose junior cuisine-routing bug — 4 cycles of flat food DB despite queued tasks (#790 SENIOR). `.foundationModels` chat backend Tier-3 parity eval gate (Task 1 PR B, #797 SENIOR). Multi-intent splitting v2 — compound + temporal (#791 SENIOR — non-design-impl diversification). V6 visual evolution audit before Element 4 ships (#792 JUNIOR). Quiet graphify watch noise (#793 JUNIOR). State.md refresh to build 250+ (#794 JUNIOR). failing-queries.md refresh 10262→10888 (#795 JUNIOR). FoodLoggingGoldSet run + #766 cross-stage gate verification (#796 JUNIOR). Human action asks (delivered via #789 register, not sprint-tasked): friend-tester DM for V6 + Feedback banner. **Cycle direction: ship Element 4 only after tester feedback on 1-3; stop carrying #708 as sprint-task indefinitely.**
- **Class-of-bug audit + cadence rewire sprint (P0, cycle 10950 sprint)** — Build 251 was process-only; one-day gap since cycle 10888 review. Three findings filed: Windowed-calculation audit — UI labels must match math evidence (#801 SENIOR; class generalized from 5a3f6eec 2-pt extrapolation fix); Crash hunt cycle 10950 — force-unwraps in code added since cycle 10262 (#802 SENIOR per tenet #8); Review-cadence rewire from cycle count to wall-clock 5-day interval (#803 SENIOR). JUNIOR cycle hygiene: South Indian +30 (#804), state.md refresh to build 251 (#805), failing-queries refresh 10888→10950 (#806), FoodLoggingGoldSet run (#807), Dashboard rings hero tap-target + a11y audit (#808 — UX tenet #7), TestFlight release notes coaching narrative (#809), MultiTurnRegression +8 for FM chat backend (#810), graphify-watch noise suppression (#811). **Cycle direction: drain #789/#790/#797 before more visual shipping; if next build is also process-only, flag in next planning.**

### Next
- ~~**USDA API Phase 1**~~ DONE — Opt-in toggle, rate limiting, searchWithFallback, privacy notice. Behind toggle (default OFF).
- ~~**Workout split builder**~~ DONE — "Build me a PPL split" → multi-turn workout design. 4 split types, exercise suggestions, template creation.
- Photo food logging (Core ML classifier → DB match → chat confirmation) — deferred until on-device accuracy improves for Indian/mixed dishes

### Later
- Fine-tuned SmolLM on Drift tool-calling dataset
- Grammar-constrained sampling for reliable JSON
- ~~**Cross-session conversation context (P1)**~~ → #506 in queue — persist last 5 turns, inject at session start
- Deep conversation memory across sessions (semantic search, long-term recall)
- On-device embeddings for semantic food/exercise search
- **AI Health Coach mode** — Proactive suggestions based on cross-domain patterns (not just reactive Q&A). Requires conversation memory + background analysis. Aspirational vision.

## UI & Design

### Now
- ~~**Color harmony (P0)**~~ DONE — Warmer palette: #0E0E12 background, #1A1B24 cards, #8B7CF6 accent. Domain colors (cyclePink, supplementMint). All views updated.
- ~~**Theme overhaul (P0)**~~ DONE — Premium dark refresh: navy background, accent-driven cards, consistent typography across 46 views.
- ~~**Dashboard redesign (P1)**~~ DONE — Apple Fitness-style macro rings, section headers (Body/Activity/Recovery/Insights), ring legend.
- ~~**Chat food confirmation card (P1)**~~ DONE — Structured card when food is logged (name, calories, macros). First structured chat UI element.
- ~~**Chat UI (P0)**~~ DONE — Message bubbles with asymmetric corners, sparkle avatar, typing indicator with step labels, tool execution feedback ("Looking up food..."). Chat now feels like a real messaging interface.
- ~~**Chat UI polish (P1)**~~ DONE — Typewriter text animation for instant responses, structured confirmation cards for weight/workout logging.
- **Food diary** — ~~Meal grouping~~ DONE. ~~Inline editing~~ DONE (DB food macro override + quick-add editing). ~~Saved meals~~ DONE (meal group re-log via context menu).

### Next
- ~~Macro rings (Apple Fitness-style concentric rings)~~ DONE
- iOS widgets (calories remaining, recovery score)
- ~~Saved meals (one-tap re-log of multi-item meals)~~ DONE
- ~~Inline diary editing (tap number to edit directly)~~ DONE
- ~~Food diary inline editing (tap to edit calories/macros directly)~~ DONE

### Later
- Apple Watch companion
- Accessibility audit (VoiceOver, Dynamic Type throughout)
- **Live Activities** — Remaining macros on lock screen, Dynamic Island during active workout. Requires WidgetKit extension + App Groups. Phase 4 candidate.

## Weight

### Now
- ~~**LB/KG unit switching**~~ ✅ DONE — Fixed stale preference pattern, extended to all exercise/workout views. DB in canonical units, conversion at view boundaries.
- ~~**Adaptive TDEE**~~ ⛔ REVERTED — v1 depended on food logging accuracy, dropped calories dangerously (1960→1400). Original TDEE is stable and accurate. v2 (weight-trend-only, no food log) moved to Later/Phase 5.
- Trend visualization improvements — clearer charts, milestone markers

### Now
- ~~**`weight_trend_prediction` analytical tool (P1, #402)**~~ DONE — "When will I reach my goal weight?" — linear regression on weight log, projected date + weekly rate + confidence. Shipped build 169.

### Next
- Body recomposition tracking (muscle vs fat trends over time)
- Goal milestones and celebrations

## Food

### Now
- ~~**DB enrichment to 1,500**~~ DONE — 1,500+ foods. Chinese, Middle Eastern, American classics, sandwiches, soups, healthy options. Manual enrichment paused — next investment should be USDA API or search quality.
- ~~**Search quality (P1)**~~ DONE — Synonym expansion (40+ regional/colloquial terms), spell correction hardened. Prefix matching works via substring SQL (`%word%` matches "chick" → "chicken"). 3 verification tests added.
- Ingredient persistence for recipe rebuilding
- **South Indian cuisine expansion (P1, bug #188)** — Target 20–30 dishes: idli variants, dosa types, sambar, rasam, kuzhambu, thoran, aviyal, puliyogare, Kerala/Tamil/Andhra/Karnataka specifics. User feedback: app lags MFP here and Indian users feel it.
- ~~**Composed-food calorie audit (P1, bug #195)**~~ DONE — Zero-calorie composed-food bug fixed (build 163). "Coffee with milk" now returns correct kcal. Additive calories were being dropped in USDA fallback path.
- ~~**Unit & piece conversion audit (P0, cycle 5721)**~~ DONE — `Docs/audits/unit-conversions-audit-2026-04-24.md` traced the strawberry "5 pieces = 750g = 240 cal" bug to the `piece → food.servingSize` fallback, 1 of 117 `gramsEquivalent: ss` sites in ServingUnit.swift that silently invents gram weights for 1,242/2,511 foods. Shipped: gated piece fallback (requires `pieceSizeG` override or `pieceGramsIfKnown` dict match, otherwise the unit isn't offered), nullable per-food override columns (`pieceSizeG`/`cupSizeG`/`tbspSizeG`/`scoopSizeG`/`bowlSizeG`) on `Food` via migration v34, USDA `foodPortions` parsing in `USDAFoodService` so online fallbacks stop synthesizing units from a fake 100g, OpenFoodFacts `piecesPerServing`→`pieceSizeG` propagation, UI "≈" prefix for estimated gram figures, 11-case `UnitConversionEndToEndTests` (includes strawberry regression pinned to 19 cal). Berry cluster (strawberries, blueberries, grapes, raspberries, cherries, blackberries, cherry tomatoes — 11 entries) backfilled with USDA-sourced `piece_size_g` in `foods.json`. Follow-up: bulk enrichment script to backfill the remaining ~2,000 foods from USDA/OFF portions; nutritionist-reviewed Indian long tail; `Idli (2 pieces): 80g` schema-level 2× overcount still TODO.

### Next
- **USDA API Phase 2 (P1)** — Phase 1 (fallback-only) is live and free. Phase 2: use USDA FoodData Central as a proactive search source for common verified foods — batch import top foods or add a "verified nutrition" search tier. API is free (1000 req/hour), 400k+ entries. Closes the MFP DB gap via API, not manual curation. (#345 in queue)
- **Caribbean & island cuisine** — 30 foods: jerk chicken, plantains, ackee, doubles, mofongo (#364 in queue)
- **Breakfast cereals & oatmeal brands** — 30 entries: Cheerios, Special K, Quaker, Kashi, overnight oats (#365 in queue)
- **East Asian home cooking** — 30 entries: onigiri, tteokbokki, congee, gyoza, edamame (#367 in queue)
- Restaurant menu items (Chipotle bowl builder, etc.)
- Barcode coverage expansion
- USDA DEMO_KEY → registered API key (required before App Store launch, low urgency for TestFlight)

### Benchmark: MyFitnessPal
- MFP has 20M+ foods (Cal AI + Intent acquisitions, Mar 2026). We have 2,511. Close gap via USDA API Phase 2, not manual entry.
- MFP logging is ~3 taps. Match or beat this with AI chat.

## Exercise

### Now
- ~~Workout history polish~~ DONE — Weight unit preference respected in history cards.
- ~~**Progressive overload alerts (P0)**~~ DONE — Stalling/declining exercises shown with weight suggestions in workout tab.
- ~~**Hardcoded unit audit (P0)**~~ DONE — 7 files fixed. All weight display paths now use Preferences.weightUnit.

### Now
- ~~**Muscle group heatmaps (P0)**~~ DONE — Weekly set counts per group + opacity intensity scaling with volume. Visual body map in exercise tab.
- ~~**Exercise instructions via chat**~~ DONE — "How do I do a deadlift?" returns form tips, muscles, equipment from 873-exercise DB. StaticOverrides routing for instant response.

### Next
- **Exercise presentation** — Images, muscle group icons, exercise instructions. Match Boostcamp quality.
- Training programming across weeks
- Exercise alternatives/substitutions

### Benchmark: Boostcamp
- Boostcamp has exercise videos/GIFs, muscle group diagrams, detailed instructions per exercise.
- We have 873 exercises but text-only. This is a major visual gap.

### Benchmark: Strong
- Strong's workout logging UX is clean and fast. Match their set/rep entry speed.

## Biomarkers & Glucose

### Now
- Trend analysis improvements
- Better glucose spike detection and pattern recognition

### Next
- Correlation with food/exercise (cross-domain insights: "your glucose spikes after rice")
- Lab report comparison over time
- **Cycle-biomarker correlation** — Correlate menstrual cycle phase with iron, vitamin D, and other biomarkers. Unique cross-domain insight (Whoop's panels are separate from cycle tracking).

### Benchmark: Whoop
- Whoop's recovery/strain insights are excellent. Match their insight quality for biomarker trends.

## Behavior Insights

### Now
- ~~**Hardcoded insight cards (3-5)**~~ ✅ DONE — 3 insights on dashboard: workout frequency vs weight, protein adherence, logging consistency. Minimum data thresholds.

### Now
- ~~**Proactive push notifications (P0)**~~ DONE — Local notifications for protein streaks, supplement gaps, workout gaps. Reuses BehaviorInsightService. 6pm daily schedule, settings toggle, permission deferred until data exists.

### Next
- ~~**Behavior insights v2**~~ DONE — 4th insight: sleep vs next-day calories. Protein window extended 14→30 days. Sleep history passed from HealthKit.
- Expanded correlations (glucose spikes after specific foods, supplement adherence vs biomarkers)
- User-configurable insight tracking ("tell me how X affects Y")

## Quality & Testing

### Now
- ~~**Coverage recovery (P0 SPRINT)**~~ DONE — 886 tests (+143). AIToolAgent, IntentClassifier, AIRuleEngine, FoodService all expanded. Coverage gate unblocked state machine refactor.
- Coverage targets: **80%** logic, **50%** services — find and fix gaps
- ~~**Code quality maintenance**~~ DDD COMPLETE — File decomposition (15 cycles, 3500+ lines reorganized) and DDD routing (83+ DB calls eliminated from 18 views → 7 domain services). Only cross-cutting factory reset remains. Architecture is clean.
- ~~**Stale preference audit**~~ PARTIALLY DONE — WeightViewModel fixed, exercise views fixed. Continue auditing remaining view models.
- AI eval harness: every tool gets 10+ eval queries
- Integration tests for multi-step flows (parse → resolve → log → confirm)

### Next
- UI snapshot tests
- Performance benchmarks (chat response time, build time)

---

## Competitive Benchmarks Summary

| Domain | Benchmark App | What to match | 2026 Update |
|--------|--------------|---------------|-------------|
| Food logging | MyFitnessPal | DB breadth, logging speed, photo scanning | Cal AI acquired (15M downloads, $30M ARR). ChatGPT Health integrated. Intent (meal planning) acquired. 20M food DB. |
| Exercise | Boostcamp | Visual exercise presentation, muscle engagement viz | Still the gold standard for exercise content. |
| Workout logging | Strong / MacroFactor | Clean, fast set/rep entry UX | MacroFactor launched Workouts app (Jan 2026) — expanding into exercise. |
| Macro coaching | MacroFactor | ~~Adaptive calorie/macro targets~~ MATCHED | MacroFactor Workouts adds personalized progression. $12/mo. |
| Biomarkers | Whoop | Insight quality, recovery analysis | Behavior Insights now tie habits to Recovery scores. Passive MSK auto-detects muscular load. |
| AI workout parsing | Whoop | AI Strength Trainer — text/photo → structured workout | Now accepts text prompts AND photo/screenshot → structured plan. Cloud-based. |
| AI chat | None (unique advantage) | Push further | MFP + Whoop both adding cloud AI. Our on-device privacy moat is differentiating. |

---

## Phase History

- **Phase 1: Core Health Tracking** (DONE) — Weight, food, exercise, sleep, supplements, body comp, glucose, biomarkers, cycle tracking.
- **Phase 2: AI Chat Foundation** (DONE) — On-device inference, dual-model, 19 tools, eval harness.
- **Phase 3a: Tiered Pipeline** (DONE) — ToolRanker, AIToolAgent, StaticOverrides, LLM normalizer.
- **Phase 3b: Parity Gaps** (DONE) — All high-impact chat features implemented.
- **Phase 3c: Polish & Depth** (CURRENT) — UI overhaul, AI reliability, test coverage, food DB.
- **Phase 4: Input Expansion** (NEXT) — Voice (SpeechRecognizer, highest ROI), photo, widgets, Apple Watch.
- **Phase 5: Deep Intelligence** (FUTURE) — Fine-tuned models, conversation memory, training programming.
