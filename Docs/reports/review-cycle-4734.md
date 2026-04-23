# Product Review — Cycle 4734 (2026-04-22)

## Executive Summary

Since the last review (cycle 4521, build 162), Drift shipped a focused bug-fix cycle: five user-reported bugs fixed from TestFlight dogfooding (photo log review, stale DB, key UX), zero-calorie food fix for composed foods, and FoodLogSheet default amount wiring. No new features shipped — this was a stabilization cycle. Sprint queue is at 64 pending tasks (24 SENIOR, 40 junior) with the analytical tools category, USDA expansion, and eval infra as the leading priorities.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 166 | +4 since review #50 (162) |
| Tests | 1,677+ | Stable |
| Food DB | 2,511 | +0 (stable) |
| AI Tools | 20 registered | +0 |
| Coverage | ~50%+ services | Stable |
| P0 Bugs Fixed | 5 (user-filed batch) | Strong signal — users are dogfooding |
| Sprint Velocity | Bugfix-only | Stabilization cycle |

## What Shipped Since Last Review

- **Zero-calorie composed-food fix (build 163):** "Coffee with milk" no longer returns 0 kcal. The composed-food lookup path was dropping additive calories — now correctly sums base food + modifiers. This was a long-running bug (#195) that eroded trust for anyone logging common morning foods.
- **Food diary refresh button (build 163):** Users can now force-refresh the food diary without leaving the view. Addresses the stale database display issue reported in user feedback.
- **Five-bug bundle from TestFlight feedback:** Photo log review screen fixes, stale DB display, and key UX issues — all filed by the user in a single dogfooding session. This is the highest-quality signal we get: batch-filed bugs from active real-device use.
- **FoodLogSheet default amount (build 163):** Food log sheet now correctly wires the default amount from FoodUnit.defaultAmount instead of hardcoding "1".

## Competitive Analysis

- **MyFitnessPal:** Redesigned "Today" tab with streaks view and Healthy Habits section; Premium photo upload for meal scanning (iOS); Blue Check dietitian-reviewed recipes behind Premium+; GLP-1 medication tracking in progress. Their AI photo scanning is cloud-backed via Cal AI acquisition — we match this with BYOK Photo Log at zero platform fee and better privacy.
- **Whoop:** New heart rate algorithm improves Recovery/Strain/Sleep data accuracy; Behavior Trends & Insights now connect daily habits to Recovery scores after 5+ logged entries; Women's Health panel integrated with Advanced Labs for cycle-phase biomarker ranges. The Behavior Insights pattern directly competes with our `cross_domain_insight` analytical tool — except theirs is cloud-based at $30/mo.
- **MacroFactor:** Workouts app launched (Jan 2026) with personalized progressive overload plans and Apple Health write integration coming. Favorites feature for quick re-logging saved staples. Expenditure Modifiers add step-informed and goal-based algorithm adjustments. At $72/year they're becoming the serious all-in-one competitor; our edge remains free + on-device + privacy-first.
- **Boostcamp:** No major 2026 updates found — still focused on the exercise content library and Web Program Creator (2024). Exercise visual presentation (videos, GIFs, muscle diagrams) remains their moat; our AI chat coaching ("how's my bench?") is the counterpart.
- **Strong:** No significant AI features or major updates. Clean UX remains their focus. Our workout AI continues to outpace them in intelligence.

## Product Designer Assessment

*Speaking as the Product Designer persona (read Docs/personas/product-designer.md):*

### What's Working

1. **User is actively dogfooding and filing bugs.** A five-bug batch from a single TestFlight session is the best signal we can get. The fixes landed fast (same cycle), which is the right response. This feedback loop — user tests, files bugs, we fix — must be protected.

2. **Photo Log is maturing.** Editable macros, serving unit picker, model picker, ingredients — it's a real feature now. The BYOK story (user brings API key, pays vendor directly, no Drift fee) is unique. MFP's equivalent is $20/mo behind Premium+.

3. **Zero-calorie fix closes a trust gap.** "Coffee with milk = 0 kcal" is the kind of silent data-accuracy bug that makes users stop trusting the app. Fixing it restores credibility for a very common morning log.

### What Concerns Me

1. **USDA API is confirmed free and we're not using it for expansion.** The admin comment on PR #333 confirmed: USDA FoodData Central API is free with API key, 400k+ verified entries, 1000 req/hour. We have 2,511 foods. This is the highest-ROI food DB move available — not manual curation, not USDA-as-fallback (already live), but USDA-as-search-source. Should be this cycle's food task.

2. **Settings → Feedback row has been deferred 6 cycles.** Six consecutive cycles with zero or near-zero user-filed bugs after an active dogfood period means the feedback channel is broken or silent. An in-app mailto row is 30 minutes of code and recovers the signal. Every cycle without it is a product blindspot.

3. **Analytical tools category is 1/5 of target.** `cross_domain_insight` is live. `glucose_food_correlation` (#324) is in queue. We need 3-4 more to claim the "AI health coach" positioning with credibility. Whoop's Behavior Insights validates the market — users want habit-to-outcome correlation. We have the data; we need the tools.

### My Recommendation

This cycle: ship Settings → Feedback (JUNIOR, 30 min), start USDA expansion beyond fallback (SENIOR, design decision needed on scope), and add two more analytical tools to the sprint. The analytical tools are where Drift earns its "AI health coach" identity — one tool is a demo, five tools is a product category.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona (read Docs/personas/principal-engineer.md):*

### Technical Health

Pipeline eval coverage is at 4-layer maturity: FoodLoggingGoldSetTests, PerToolReliabilityEval, PipelineE2EEval, ChatLatencyBenchmark. The two gaps from last cycle (per-stage failure attribution #312, DomainExtractor Stage 3 gold set #325) are in the sprint queue. Until both land, we attribute regressions to "the pipeline" rather than to a specific stage — this makes fixing them slower.

The five-bug bundle came from real device use, not from the test suite. That's expected for UI/UX bugs, but the stale DB and composed-food bugs should have been catchable. Worth a quarterly audit of which categories of bugs our test suite structurally misses.

### Technical Debt

1. **state.md is outdated.** Still says "Build 133", "Context: 2048 tokens", "Tests: 1677+". Build is 166, context is 4096 (post-#176), and state deserves an accurate snapshot. First thing new contributors read.

2. **failing-queries.md is overdue for a refresh.** The roadmap says "failing-queries.md refresh cycle 3985→4487 (#330)" — that task shipped last cycle. The doc should now reflect the current failing categories from 4487 onward, not 3985.

3. **Photo Log review screen is near the extraction threshold.** Four feature additions across two builds (editable macros, serving unit picker, model picker, ingredients). One more addition and `PhotoLogReviewViewModel` extraction is overdue. Plan it proactively, not reactively.

4. **USDA DEMO_KEY is still in use.** Low urgency for TestFlight but will hit rate limits before App Store launch. Should be swapped for a registered key before public release.

### My Recommendation

Ship #312 (per-stage failure attribution) and #325 (DomainExtractor gold set) together — they're interdependent and neither is useful alone. Update state.md and failing-queries.md as junior tasks (30 min each). Hold the Photo Log review screen at its current scope; extract the ViewModel before adding any new feature to that view.

## The Debate

*The Product Designer and Principal Engineer discuss where to focus next.*

**Designer:** User filed five bugs in one session — great signal. But it also means we're flying blind on what else is broken. Settings → Feedback must ship this cycle, no exceptions. After that: USDA expansion and two more analytical tools. `glucose_food_correlation` is in queue; I want `weight_trend_prediction` alongside it. Three analytical tools = the start of a real category.

**Engineer:** Agreed on Settings → Feedback — it's trivial and the feedback blindspot is real. On analytical tools: `glucose_food_correlation` is safe (same read-only pattern as `cross_domain_insight`). `weight_trend_prediction` touches WeightTrendService in a new way — make sure there's a gold-set gate before merge, same as every other new tool. My priority add: #312 + #325 as a paired senior task. Until we have per-stage attribution, any analytical tool regression is hard to diagnose.

**Designer:** Fair on the gold-set gate — that's the established pattern, it stays. On #312 + #325: they're in queue, let senior pick them up. I won't block analytical tool additions on eval infra, as long as each tool ships with its own 5+ eval cases. That's the contract.

**Engineer:** Agreed. Also: state.md + failing-queries.md refresh are 30-minute junior tasks with high signal-to-noise. Put them in this cycle's sprint. Clean docs reduce onboarding friction and planning drift.

**Agreed Direction:** This cycle's sprint adds: Settings → Feedback (JUNIOR, P0-priority non-negotiable), USDA key upgrade to registered key (JUNIOR), `weight_trend_prediction` analytical tool with gold-set gate (SENIOR), state.md + failing-queries.md refresh (JUNIOR). Eval infra pair (#312 + #325) is already in queue — senior picks it up in normal rotation. Cap new tasks at 6 this cycle since queue is at 64.

## Decisions for Human

1. **USDA API expansion scope:** We confirmed USDA FoodData Central is free (PR #333 comment). We already have USDA as a *fallback* for search misses. Should we expand to: (a) USDA as a primary source for a dedicated "verified foods" search tier, (b) a batch import of common foods from USDA into our local DB, or (c) keep current fallback and just swap DEMO_KEY for registered key? Option (a) or (b) could meaningfully close the MFP DB gap.

2. **Analytical tools positioning:** `cross_domain_insight` is live. How aggressively should we market the "AI health coach" identity in TestFlight release notes? Waiting for 5 tools before calling it out, or start now with 1-2?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
