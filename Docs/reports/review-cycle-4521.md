# Product Review — Cycle 4521 (2026-04-22)

## Executive Summary

Since the last review (cycle 4487), Drift shipped Photo Log as a full UX overhaul (builds 159-162: editable macros, AI-returned serving units, ingredients, per-provider model picker), merged the first analytical AI tool (`cross_domain_insight` for correlational queries), and hardened IntentClassifier with domain-aware confidence thresholds from telemetry. The AI pipeline now spans transactional and analytical tools — the next 3 analytical tools will complete the "AI health coach" positioning. Sprint backlog is at 46 pending with heavy SENIOR concentration; drain rate is the primary constraint.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 162 | +7 since review #49 (155) |
| Tests | 1,677+ | +0 documented (stable) |
| Food DB | 2,511 | +0 (queue covers +60 Korean/Caribbean pending) |
| AI Tools | 20 registered | +1 (cross_domain_insight) |
| Coverage | ~50%+ services | Stable |
| P0 Bugs Fixed | 1 (#310 photo logging) | 1 in period |
| Sprint Velocity | ~40% (4/10 of cycle 4247 tasks shipped) | Moderate |

## What Shipped Since Last Review

- **Photo Log UX overhaul (builds 159-162):** Users can now edit macros directly in the review screen before logging, see AI-suggested serving sizes with units (100g, 1 cup), review ingredients, and choose their preferred model per provider (GPT-4o, Gemini 2.0 Flash, Claude Sonnet). The beta experience went from "take a photo, accept result" to "take a photo, review + refine."
- **`cross_domain_insight` analytical tool (#317):** Users can now ask "do I eat more on gym days?" or "how does my sleep affect my calories?" — Drift correlates across food/weight/exercise/glucose/sleep domains in a single response. First tool that reads 2+ services for analysis, not logging.
- **Domain-aware IntentClassifier thresholds (#302):** Each domain (food, exercise, weight, health) now has its own confidence floor before triggering a clarification prompt. Food queries were over-clarifying; exercise queries were under-clarifying. Telemetry-calibrated thresholds fixed both simultaneously.
- **Telemetry raw-text persistence (#297):** Every query + response is now persisted locally for analysis. Closes the blind spot where we could see that classification failed but not *which* phrasings clustered into failure modes.
- **Photo Log multi-provider (OpenAI + Gemini via #298):** Users who prefer OpenAI or Gemini Vision can now use their preferred key. The provider choice persists and is respected in the review screen model picker.
- **Intent classifier 'log X' routing fix (#277):** "log pizza" was routing to food_info (search) instead of log_food. Fixed at the intent stage with an LLM prompt improvement, not a static override.
- **Build 162 hash-gated food reseed + telemetry toggle fix:** Reseed is now idempotent across app relaunches via content hash, and telemetry toggle recursion bug resolved.

## Competitive Analysis

- **MyFitnessPal:** MFP acquired Cal AI (photo food logging, 15M downloads, $30M ARR) and integrated with ChatGPT Health. Their photo scanning is now cloud-backed with GPT-4V at Premium+ ($20/mo). Our Photo Log BYOK matches the core capability at user cost with better privacy — users pay the API vendor directly, no Drift subscription. MFP food DB remains 20M+; our 2,511 is best closed with USDA API, not manual entry.
- **Boostcamp:** Exercise presentation (videos, GIFs, muscle diagrams per exercise) remains the gold standard. Drift has text-only instructions via chat. Gap is real but deliberate — we compete on AI coaching quality, not media content.
- **Whoop:** Launched AI Coach with conversation memory and contextual recovery guidance. Their Behavior Insights (habits → Recovery scores after 5+ entries) is the same pattern as our cross-domain analytical tools, but cloud-based with multi-week history. Our differentiator: on-device, private, and available without a $30/mo subscription. Analytical tools like `cross_domain_insight` directly compete with their insight layer.
- **Strong:** Stays minimal and clean. Clean UX is their moat. No major AI features. Our workout AI (progressive overload alerts, exercise instructions in chat) outpaces them in intelligence at zero cost.
- **MacroFactor:** MacroFactor Workouts (Jan 2026) now includes auto-progression, cardio, Apple Health write, AI recipe photo logging, and Jeff Nippard content library at $72/year. They're becoming a serious all-in-one competitor. Our edge: free, on-device, privacy-first with a broader chat interface.

## Product Designer Assessment

*Speaking as the Product Designer persona:*

### What's Working

1. **Photo Log is now a real competitor to Cal AI.** The build 160-162 improvements — editable macros, serving unit picker, ingredients display, model picker — transformed Photo Log from "scan and accept" to "scan and review." The BYOK story (users bring their own API key, pay the vendor directly) is unique in the market. No competitor offers privacy-preserving photo logging at zero platform fee.

2. **`cross_domain_insight` proves the analytical tools category.** Users asking "do I lose more weight on gym days?" get a real answer with data. This is the AI health coach moment we've been building toward — moving from transactional (log food, log weight) to analytical (correlate patterns). The tool category is proven; we need 3-4 more to complete the positioning.

3. **Clarification card on the current branch (#316) is the right UX direction.** Instead of freeform text when ambiguous, users tap a chip to choose. "Chicken breast" vs "Chicken thigh" becomes a 1-tap decision. This is the "every AI decision becomes a tap" philosophy applied consistently.

### What Concerns Me

1. **5 consecutive cycles with zero user-filed bugs or feature requests.** The Settings → Feedback row (#329) is still open. Without a feedback loop, we're flying blind on real-user pain. The TestFlight notes nudge hasn't changed user behavior. We need an in-app mailto row before cycle 4560 — non-negotiable.

2. **Analytical tools are 1/5 of the target.** `cross_domain_insight` is live, `glucose_food_correlation` (#324) is in the queue. We need `weight_trend_prediction`, `exercise_volume_summary`, and one more to reach the "AI health coach" positioning threshold. Each tool takes one senior session. Three more tools = 3 sessions; realistic in 3-4 planning cycles if senior drain rate holds.

3. **46 tasks in the queue with only 5 tasks/senior-session throughput.** Queue grew from 38 to 46 last cycle. At 5/session with ~2 sessions/day for senior, the queue drains in ~5 days if no new tasks are added. But we add 8 tasks every 6 hours (planning). Queue will grow unless we either increase session throughput or reduce planning additions. Recommend capping new tasks at ≤6/cycle until queue drops below 30.

### My Recommendation

Complete the analytical tools category and fix the feedback vacuum in parallel. The next 2 planning cycles should each add: one new analytical tool (SENIOR), one feedback/discoverability improvement (JUNIOR), and one food DB batch (JUNIOR). Everything else is maintenance. The "AI health coach" identity unlocks when 3-5 analytical tools are live — we're at 1. Execute.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona:*

### Technical Health

The pipeline's 6-stage architecture is mature: StaticOverrides → InputNormalizer → IntentClassifier → DomainExtractor → Tool execution → Presentation. Every stage now has isolated eval coverage: FoodLoggingGoldSetTests (aggregate), IntentClassifierGoldSetTests (Stage 2), DomainExtractor gold set (#325 in queue), per-tool 50-query sets, PipelineE2EEval, ChatLatencyBenchmark (default-path TTFT). Per-stage failure attribution (#312, still open) will close the last gap — once it lands, regressions will surface at the stage level, not just the aggregate.

Photo Log added the first off-device model calls. The fallback chain (#300, in queue) will make this invisible to users. Architecture-wise, the `CloudVisionClient` protocol + multiple provider impls is the right pattern — provider-agnostic with per-provider auth shapes handled at the implementation layer.

### Technical Debt

1. **Context window at 4096 tokens (2048 actual, per state.md which is outdated — likely 4096 post-#176).** The context window bump to 6144 (#315, open) is ready to ship but needs a prompt audit alongside it. Without the audit, the extra tokens get absorbed by prompt bloat, not conversation history. Both must ship together.

2. **DomainExtractor Stage 3 has no isolated gold set (#325, open).** This is the last eval infrastructure gap. If extraction regresses, per-stage attribution (#312) can identify it as Stage 3, but we won't know if the extraction gold set passed or failed independently. Both #312 and #325 should ship in the same session.

3. **Photo Log review screen approaching extraction threshold.** Four feature additions across two builds (editable macros, serving unit picker, model picker, ingredients). Adding #331 (onboarding tip) may push it past the maintainability threshold. Consider extracting `PhotoLogReviewViewModel` before the next feature addition.

4. **state.md accuracy.** Current state.md says "Build 133", "Context: 2048 tokens", "Tests: 1677+". Build is now 162, context is 4096 (post-#176), tests may have grown. State.md needs a refresh — it's the first thing new contributors would read.

### My Recommendation

Ship #312 (per-stage failure attribution) and #325 (DomainExtractor gold set) together as the next senior priority — they're complementary and each is incomplete without the other. Then unblock the context window (#315 + prompt audit) as the next session. These two pairs take 2 senior sessions and complete the eval infrastructure. After that, every subsequent AI task can claim a stage-specific success metric.

## The Debate

*The Product Designer and Principal Engineer discuss where to focus next.*

**Designer:** We need more analytical tools now. `cross_domain_insight` proved the category. `glucose_food_correlation` is already in queue (#324). I want `weight_trend_prediction` and `exercise_volume_summary` in this cycle's sprint — three more tools in 3 sessions and we can market the AI health coach angle.

**Engineer:** I agree on the direction but the order matters. Per-stage attribution (#312) is an eval infrastructure dependency — without it, we can't confidently say an analytical tool "passed" because we don't know which stage failed when it doesn't work. Ship #312 first (1 session), then add analytical tools. Adding 3 analytical tools without measurement is flying blind.

**Designer:** Fair. But #312 isn't a blocker for shipping the tools themselves — it's a blocker for *attributing failures*. We can ship `weight_trend_prediction` and iterate. The user sees a working tool or "not enough data" gracefully — they don't see stage attribution. Let's parallel-track: #312 in one session, `weight_trend_prediction` in another.

**Engineer:** Agreed on parallel — as long as `weight_trend_prediction` has its own gold-set cases pinned before merge. The pattern from `cross_domain_insight` is: write the tool, write 5 eval cases, run eval, ship if 100%. Same gate applies. I'll also flag: #325 (DomainExtractor gold set) is a dependency for my #312 recommendation. Both must land together.

**Agreed Direction:** Sprint adds two analytical tools (`weight_trend_prediction`, `exercise_volume_summary`) alongside the eval infrastructure pair (#312 + #325). Designer gets the user-visible tools; engineer gets the measurement foundation. Feedback vacuum (#329, Settings → Feedback) ships this cycle — non-negotiable after 5 silent cycles.

## Decisions for Human

1. **Analytical tool priority:** Should `weight_trend_prediction` ("when will I reach my goal?") or `exercise_volume_summary` ("how's my training volume?") be the higher priority? Both are SENIOR tasks taking ~1 session each. The order determines which one beta testers see first.

2. **State.md accuracy:** state.md still lists Build 133 and 2048-token context. Should the autopilot update state.md as part of every sprint-planning cycle, or is it acceptable to let it drift between major milestones?

3. **Queue cap:** Queue is at 46 pending (15 SENIOR, 31 junior). At 5/session drain rate, this is ~2-3 days of SENIOR work. Should planning be paused until queue drops below 30, or continue adding 6-8 tasks per cycle as long as they're high-value?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
