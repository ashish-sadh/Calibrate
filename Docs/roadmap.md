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

### Next
- USDA API integration for verified nutrition data
- Restaurant menu items (Chipotle bowl builder, etc.)
- Barcode coverage expansion

### Benchmark: MyFitnessPal
- MFP has 14M+ foods (acquired Cal AI Mar 2026). We have 1,500. Close gap via USDA API, not manual entry.
- MFP logging is ~3 taps. Match or beat this with AI chat.

## Exercise

### Now
- ~~Workout history polish~~ DONE — Weight unit preference respected in history cards.
- ~~**Progressive overload alerts (P0)**~~ DONE — Stalling/declining exercises shown with weight suggestions in workout tab.
- ~~**Hardcoded unit audit (P0)**~~ DONE — 7 files fixed. All weight display paths now use Preferences.weightUnit.

### Now
- **Muscle group heatmaps (P0)** — Visualize which muscle groups were hit this week. Data exists in exercise DB muscle tags. Deferred 3 sprints — ships this sprint.
- **Exercise instructions via chat** — "How do I do a deadlift?" → form tips + muscles targeted from existing exercise DB.

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
- **Proactive push notifications (P0)** — Passive dashboard alerts → active nudges. Protein streak, supplement gap, workout gap. On-device scheduling, no cloud.

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
