# Drift Product Roadmap

## Vision

Two equally important pillars:
1. **AI chat that handles 90% of interactions** — type what you did, AI does the rest
2. **Beautiful, fast, opinionated health tracking UI** — charts, diary, insights that are world-class

Neither is secondary. Every improvement should advance one or both pillars.

Privacy-first: everything on-device, no cloud, no accounts. This is non-negotiable.

## Current Phase: Polish & Depth (Phase 3c)

What's working: core tracking across all domains, AI chat foundation, 19 tools, dual-model pipeline, 886 tests, 1,201 foods, state machine, structured chat cards.

What's not: Color palette feels disjointed (dark blue/purple + bright rings), no voice input (3 reviews deferred), chat is still mostly text-only, food DB is 0.006% of MFP's 20M.

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

### Next
- ~~**USDA API Phase 1**~~ DONE — Opt-in toggle, rate limiting, searchWithFallback, privacy notice. Behind toggle (default OFF).
- ~~**Workout split builder**~~ DONE — "Build me a PPL split" → multi-turn workout design. 4 split types, exercise suggestions, template creation.
- Photo food logging (Core ML classifier → DB match → chat confirmation) — deferred until on-device accuracy improves for Indian/mixed dishes

### Later
- Fine-tuned SmolLM on Drift tool-calling dataset
- Grammar-constrained sampling for reliable JSON
- Conversation memory across sessions
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

### Next
- Predictive "you'll reach goal by" based on adaptive trend
- Body recomposition tracking (muscle vs fat trends over time)
- Goal milestones and celebrations

## Food

### Now
- ~~**DB enrichment to 1,500**~~ DONE — 1,500+ foods. Chinese, Middle Eastern, American classics, sandwiches, soups, healthy options. Manual enrichment paused — next investment should be USDA API or search quality.
- ~~**Search quality (P1)**~~ DONE — Synonym expansion (40+ regional/colloquial terms), spell correction hardened. Prefix matching works via substring SQL (`%word%` matches "chick" → "chicken"). 3 verification tests added.
- Ingredient persistence for recipe rebuilding
- **South Indian cuisine expansion (P1, bug #188)** — Target 20–30 dishes: idli variants, dosa types, sambar, rasam, kuzhambu, thoran, aviyal, puliyogare, Kerala/Tamil/Andhra/Karnataka specifics. User feedback: app lags MFP here and Indian users feel it.
- ~~**Composed-food calorie audit (P1, bug #195)**~~ DONE — Zero-calorie composed-food bug fixed (build 163). "Coffee with milk" now returns correct kcal. Additive calories were being dropped in USDA fallback path.

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
