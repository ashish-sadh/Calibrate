# Drift Product Roadmap

## Vision

Two equally important pillars:
1. **AI chat that handles 90% of interactions** — type what you did, AI does the rest
2. **Beautiful, fast, opinionated health tracking UI** — charts, diary, insights that are world-class

Neither is secondary. Every improvement should advance one or both pillars.

Privacy-first: everything on-device, no cloud, no accounts. This is non-negotiable.

## Current Phase: Polish & Depth (Phase 3c)

What's working: core tracking across all domains, AI chat foundation, 19 tools, dual-model pipeline, 743+ tests.

What's not: UI feels rough and unpolished compared to competitors, AI chat drops context in multi-turn, test coverage has gaps, food DB is incomplete, exercise has no visual aids.

---

## AI Chat

### Now
- **Prompt consolidation (P1)** — Single source of truth for tool schemas, examples, context injection. Measure and compress token count. Context window is tight (2048 tokens, 1776 max prompt) — every wasted token hurts response quality.
- **State machine refactor** — Replace scattered pendingMealName/pendingWorkout state vars with a proper conversation state machine (idle → classifying → executing → confirming → logging). Clear transitions, no dangling state. *Blocked by: AIToolAgent test coverage.*
- **Multi-turn reliability** — Eliminate context loss bugs. Test: 3-turn meal logging, 3-turn workout building, topic switching mid-conversation.
- ~~**Natural freeform logging**~~ DONE — "log for breakfast 2 eggs and spinach and bread and coffee with 2% milk" → AI parses, splits "with" items, resolves each, opens recipe builder.

### Next
- Meal planning dialogue — "plan my meals today" → iterative suggestions based on remaining macros + history
- Workout split builder — "build me a PPL split" → multi-turn designing
- **Voice input (P1 research)** — iOS SpeechRecognizer → on-device speech-to-text → chat. Higher ROI than photo. Evaluate feasibility this phase.
- Photo food logging (Core ML classifier → DB match → chat confirmation) — deferred until on-device accuracy improves for Indian/mixed dishes

### Later
- Fine-tuned SmolLM on Drift tool-calling dataset
- Grammar-constrained sampling for reliable JSON
- Conversation memory across sessions
- On-device embeddings for semantic food/exercise search
- **AI Health Coach mode** — Proactive suggestions based on cross-domain patterns (not just reactive Q&A). Requires conversation memory + background analysis. Aspirational vision.

## UI & Design

### Now
- **Theme overhaul (P0)** — Coherent visual language across ALL views in ONE cycle. Colors, spacing, typography, card styles. Pick a bold direction and commit app-wide. *29 cycles without visual progress — this is overdue.*
- **Dashboard redesign (P1)** — Better information hierarchy, scannable at a glance, macro rings (Apple Fitness-style), clearer progress indicators.
- **Chat UI** — Message bubbles, animated typing indicators, tool execution feedback, streaming UX.
- **Food diary** — Faster logging flow, better meal grouping, clearer macro display.

### Next
- Macro rings (Apple Fitness-style concentric rings)
- iOS widgets (calories remaining, recovery score)
- Saved meals (one-tap re-log of multi-item meals)
- Inline diary editing (tap number to edit directly)

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
- **DB enrichment** — Correct serving sizes, add missing foods. Indian, regional, restaurant items. Cross-reference with USDA.
- **Search quality** — Better aliases, spelling corrections, partial matches. "paneer" finds all paneer dishes.
- Ingredient persistence for recipe rebuilding

### Next
- USDA API integration for verified nutrition data
- Restaurant menu items (Chipotle bowl builder, etc.)
- Barcode coverage expansion

### Benchmark: MyFitnessPal
- MFP has 14M+ foods. We have ~1000. Close the gap on common foods first.
- MFP logging is ~3 taps. Match or beat this with AI chat.

## Exercise

### Now
- Workout history polish
- Progressive overload tracking improvements

### Next
- **Exercise presentation** — Images, muscle group icons, exercise instructions. Match Boostcamp quality.
- **Muscle group heatmaps** — Visualize which muscle groups were hit this week based on workout history. Data exists in exercise DB muscle tags.
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

### Next
- **Behavior insights v2** — Add sleep duration vs recovery correlation (4th insight), extend window from 14→30 days
- Expanded correlations (glucose spikes after specific foods, supplement adherence vs biomarkers)
- User-configurable insight tracking ("tell me how X affects Y")

## Quality & Testing

### Now
- **Coverage recovery (P0 SPRINT)** — AIToolAgent 20% (target 50%, ~15 more tests), IntentClassifier 36% (target 50%, ~10 more tests), AIRuleEngine 25% (target 50%), FoodService 30% (target 50%). *6 consecutive reviews have flagged this — BLOCKING state machine refactor. Must resolve in next 3 cycles.*
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

| Domain | Benchmark App | What to match |
|--------|--------------|---------------|
| Food logging | MyFitnessPal | DB breadth, logging speed, photo scanning (Cal AI acquired) |
| Exercise | Boostcamp | Visual exercise presentation, muscle engagement viz |
| Workout logging | Strong | Clean, fast set/rep entry UX, muscle heat map |
| Macro coaching | MacroFactor | ~~Adaptive calorie/macro targets~~ MATCHED (adaptive TDEE shipped) |
| Biomarkers | Whoop | Insight quality, recovery analysis, AI coaching from bloodwork, healthspan framing |
| AI workout parsing | Whoop | AI Strength Trainer — text/photo → structured workout plan with muscular load tracking |
| AI chat | None (unique advantage) | Push further — competitors adding cloud AI coaching (Whoop) and photo AI (MFP) but none do on-device conversational tracking |

---

## Phase History

- **Phase 1: Core Health Tracking** (DONE) — Weight, food, exercise, sleep, supplements, body comp, glucose, biomarkers, cycle tracking.
- **Phase 2: AI Chat Foundation** (DONE) — On-device inference, dual-model, 19 tools, eval harness.
- **Phase 3a: Tiered Pipeline** (DONE) — ToolRanker, AIToolAgent, StaticOverrides, LLM normalizer.
- **Phase 3b: Parity Gaps** (DONE) — All high-impact chat features implemented.
- **Phase 3c: Polish & Depth** (CURRENT) — UI overhaul, AI reliability, test coverage, food DB.
- **Phase 4: Input Expansion** (NEXT) — Voice (SpeechRecognizer, highest ROI), photo, widgets, Apple Watch.
- **Phase 5: Deep Intelligence** (FUTURE) — Fine-tuned models, conversation memory, training programming.
