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
- Voice input (iOS 26 SpeechAnalyzer → on-device speech-to-text → chat)
- Photo food logging (Core ML classifier → DB match → chat confirmation)

### Later
- Fine-tuned SmolLM on Drift tool-calling dataset
- Grammar-constrained sampling for reliable JSON
- Conversation memory across sessions
- On-device embeddings for semantic food/exercise search

## UI & Design

### Now
- **Theme overhaul** — Coherent visual language across ALL views. Colors, spacing, typography, card styles. Pick a direction and commit app-wide. Not tied to dark-only.
- **Dashboard** — Scannable at a glance. Clear progress indicators, better hierarchy, less clutter.
- **Chat UI** — Message bubbles, animated typing indicators, tool execution feedback, streaming UX.
- **Food diary** — Faster logging flow, better meal grouping, clearer macro display.

### Next
- Macro rings (Apple Fitness-style concentric rings)
- iOS widgets (calories remaining, recovery score)
- Saved meals (one-tap re-log of multi-item meals)
- Inline diary editing (tap number to edit directly)
- **Live Activities** — Remaining macros/calories on lock screen, Dynamic Island during active workout

### Later
- Apple Watch companion
- Accessibility audit (VoiceOver, Dynamic Type throughout)

## Weight

### Now
- ~~**LB/KG unit switching**~~ ✅ DONE — Fixed stale preference pattern, extended to all exercise/workout views. DB in canonical units, conversion at view boundaries.
- ~~**Adaptive TDEE**~~ ✅ DONE — EMA-smoothed adaptive estimation from weight trend data. 3-point ramp-up, 0.4 dampening. Persists in TDEEConfig.
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
- **Coverage recovery (P0)** — 8 files below threshold. Critical: AIToolAgent 0%, IntentClassifier 36%, AIRuleEngine 25%, FoodService 30%. Write tests before any AI refactoring. *3 reviews have flagged this — must be addressed before state machine refactor.*
- Coverage targets: **80%** logic, **50%** services — find and fix gaps
- **Code quality maintenance** — File decomposition largely complete (13 refactoring cycles, 3200+ lines reorganized). Shift focus from file splitting to: test coverage, DDD violations (business logic in views), dependency injection, protocol abstractions.
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
| Biomarkers | Whoop | Insight quality, recovery analysis, women's health biomarker panels |
| AI chat | None (unique advantage) | Push further — MFP bought Cal AI but still cloud-only |

---

## Phase History

- **Phase 1: Core Health Tracking** (DONE) — Weight, food, exercise, sleep, supplements, body comp, glucose, biomarkers, cycle tracking.
- **Phase 2: AI Chat Foundation** (DONE) — On-device inference, dual-model, 19 tools, eval harness.
- **Phase 3a: Tiered Pipeline** (DONE) — ToolRanker, AIToolAgent, StaticOverrides, LLM normalizer.
- **Phase 3b: Parity Gaps** (DONE) — All high-impact chat features implemented.
- **Phase 3c: Polish & Depth** (CURRENT) — UI overhaul, AI reliability, test coverage, food DB.
- **Phase 4: Input Expansion** (NEXT) — Voice (SpeechRecognizer, highest ROI), photo, widgets, Apple Watch.
- **Phase 5: Deep Intelligence** (FUTURE) — Fine-tuned models, conversation memory, training programming.
