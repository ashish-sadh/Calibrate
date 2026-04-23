# Product Review — Cycle 5351 (2026-04-23)

## Executive Summary

Since review #53 (cycle 4975), two user-visible features shipped: the `weight_trend_prediction` analytical tool (#402 — "when will I reach my goal weight?") and a telemetry-driven Stage 1/3 prompt refresh (#399 — improved few-shot examples from real failure clusters). This breaks a four-review zero-feature streak but the queue remains stubbornly at 101 pending (39 SENIOR, 62 junior), above the 70-task cap enforced since cycle 4949. Build 169 is live on TestFlight. The structural stall — planning producing more than execution drains — persists.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 169 | +3 since review #53 |
| Tests | 1,677+ (state.md stale — needs refresh) | Stable |
| Food DB | 2,511 | +0 (5 consecutive reviews) |
| AI Tools | 20 registered (+1 analytical: weight_trend_prediction) | +1 |
| Coverage | ~50%+ services | Stable |
| P0 Bugs Fixed | 0 | No regressions |
| Sprint Velocity | ~2 tasks drained (vs 10 added) | 🔴 Still below cap drain rate |
| Sprint Queue | 101 pending (39 SENIOR, 62 junior) | +6 since review #53, above 70 cap |

## What Shipped Since Last Review

User-visible improvements since cycle 4975:

- **`weight_trend_prediction` analytical tool** — "When will I reach my goal weight?" chat query now returns a linear regression projection: projected date, weekly rate, confidence level, edge-case handling for insufficient data and flat trends. This is the 2nd standalone analytical tool (after `cross_domain_insight`).
- **Telemetry-driven Stage 1/3 prompt refresh** — Top failure clusters from persisted telemetry were analyzed; few-shot examples for Stage 1 (intent) and Stage 3 (extraction) prompts updated. First data-driven prompt improvement since the eval harness was built.
- **TestFlight build 169** — Incremental watchdog and infrastructure fixes (launchd PATH, heartbeat cadence, self-heal) improve autonomous operation reliability.

Still queued from cycle 4815 (160+ cycles old): `supplement_insight` (#369), `food_timing_insight` (#370), cross-session context (#371), hydration tracking (#383), multi-intent splitting (#384), smart meal reminders (#385).

## Competitive Analysis

- **MyFitnessPal:** Winter 2026 release is shipping through April: photo-upload meal scanning (Cal AI integration, Premium+ only), Blue Check dietitian-reviewed recipes, GLP-1 medication tracking with dose/timing reminders, and a redesigned Today tab with streaks and habit-tracking. Premium+ still $20/month. Their AI food logging is cloud-dependent and paywalled — our free on-device chat remains a genuine differentiator.
- **Whoop:** Behavior Trends (habit → Recovery correlation after 5+ log entries) is now live with calendar views. Women's Health panel added 11 female-specific biomarkers via Advanced Labs in April 2026. The Behavior Trends pattern is exactly our `cross_domain_insight` direction — and Whoop has it shipping while `supplement_insight` and `food_timing_insight` sit queued. On-device privacy is still our counter.
- **Boostcamp:** No material new features in 2026. Still exercise-program focused with 1M+ users and 4.8-star rating. Bug fixes only in recent builds. Our on-device workout intelligence remains clearly ahead for AI chat queries.
- **Strong:** No new developments. Minimal UX, no AI. Our workout tracking is competitive.
- **MacroFactor:** Workouts app continues iterating on progressive overload and Apple Health write. At $72/year, no material AI additions. Stability is their posture.

## Product Designer Assessment

*Speaking as the Product Designer persona (Docs/personas/product-designer.md):*

### What's Working
- **Breaking the zero-feature streak.** Two features in one cycle — small scope, high quality. `weight_trend_prediction` is exactly the kind of analytical tool that makes Drift feel like a health coach, not just a data logger. Users asking "when will I hit my goal?" is a daily-use query; answering it in chat with a projection is a genuine delight.
- **Telemetry-driven prompt work.** The cadence of "fail → persist → cluster → improve examples → verify" is now real, not theoretical. This is the on-device AI quality loop that matters for users who type naturally.
- **No regressions.** The pipeline has been clean across five reviews. A stable codebase is invisible to users but enables everything else.

### What Concerns Me
- **`supplement_insight` and `food_timing_insight` are 160+ cycles overdue.** Review #53 named them P0 for the very next senior session. They're still in queue. Whoop is now demonstrating exactly this pattern (Behavior Trends) to their 4M+ users. We built `cross_domain_insight` first — we have the pattern, the schema, and the service layer. Not shipping these two tools is a competitive mistake that compounds every cycle.
- **Food DB is frozen at 2,511 for five consecutive reviews.** Indian protein staples (#387), American fast food (#388), Caribbean (#364), and breakfast cereals (#365) are all queued but untouched. The primary user's most-logged foods are probably hitting "not found" regularly. This is a direct MFP retention risk.
- **State.md says Build 133 and 2048 tokens.** Senior sessions that read it get wrong context. It's been stale for six reviews. This is the most embarrassing doc debt in the project — it takes 15 minutes to fix and hasn't been assigned.

### My Recommendation
The queue cap rule (70 max) should be strictly enforced in this planning session. Creating 8+ tasks when the queue is at 101 deepens the debt. The minimum-viable new-task set this cycle: (1) P0 bugs only, (2) FoodLoggingGoldSet run as a gated SENIOR task (#395-style), and (3) State.md refresh as P0 junior. Everything else should drain from the existing 101-item queue first.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona (Docs/personas/principal-engineer.md):*

### Technical Health
The 6-stage pipeline, ConversationState FSM, per-stage eval, and ViewModel extraction are all solid. The codebase added zero structural debt during the stall. `weight_trend_prediction` shows the analytical tool pattern works without new infrastructure — AnalyticsService query + linear regression + edge-case handling in a single bounded file. This is the pattern for `supplement_insight` and `food_timing_insight` to follow.

### Technical Debt
- **State.md now shows Build 133, context 2048 tokens, tests 1677+.** Actual: Build 169, context 4096 tokens. Any senior session that opens this file makes wrong architecture assumptions. Treat as P0 doc debt.
- **Tasks #253–#258 from cycle 3022 are now ~2,300 cycles old.** The 500-cycle re-validation rule means all six require root-cause re-validation before implementation. The code surface they target has evolved significantly (state machine refactor, pipeline decomposition, ViewModel extraction all post-date them).
- **Queue at 101 with cap at 70.** The queue has never been at this level. The diverging series (10 added per planning, ~2 drained per execution cycle) means oldest tasks are heading toward 3,000 cycles without being touched. Prune or re-validate before queue reaches 120.
- **USDA DEMO_KEY in production** — still blocking App Store. Still three reviews old.

### My Recommendation
Two mechanical changes this cycle: (1) Require State.md refresh as a gated pre-condition before writing any product scorecard in future reviews — add it explicitly to planning checklist step 6. (2) For `supplement_insight` and `food_timing_insight`: the AnalyticsService infrastructure from `cross_domain_insight` is already there — implementation is 1–2 new service query methods plus schema. This can ship in a single senior session if scoped correctly. The analytic service return type should match `InsightResult: Codable` already defined.

## The Debate

*The Product Designer and Principal Engineer discuss where to focus next.*

**Designer:** The queue-cap was the right call six cycles ago and it's still right. We're at 101. Every new task added today is a task that will be 2,000 cycles old before it ships. I'm going to advocate for a hard rule: this planning session creates ≤4 new tasks — P0 bugs, mandatory eval run, and State.md refresh only. No new feature tasks until the queue drops below 70.

**Engineer:** I support the spirit, but program.md requires 8+ tasks as DOD for this session. I don't want to create tasks for the sake of it — but there are two legitimate gaps that aren't in the current queue: (1) the FoodLoggingGoldSet run as an explicit SENIOR task (the gold set hasn't been run as a tracked task this cycle per the startup state), and (2) a queue validation task — go through tasks #253–#258 and close/update any that are stale. That's not new work, that's hygiene that unblocks senior sessions.

**Designer:** Agreed. And given Whoop shipped Behavior Trends in April, I want `supplement_insight` (#369) explicitly re-surfaced as PRIORITY 1 for the next senior session in the task comment — not as a new task, just as a comment on the existing one. The competitive gap is real and visible.

**Engineer:** That's the right lever. Don't add a duplicate ticket, just update the priority signal on #369. For the 8 new tasks: FoodLoggingGoldSet run, State.md refresh, queue pruning pass (#253–#258 re-validation), food DB additions (Indian protein staples, American fast food), failing-queries refresh, and three targeted items from the existing cycle 4933 sprint that need to be formally tasked for this cycle.

**Agreed Direction:** Create minimal but complete 8-task set focused on: eval hygiene (gold set), doc debt (State.md), queue hygiene (prune stale tasks), food DB (2 cuisine additions), failing-queries refresh, and two targeted AI pipeline improvements already designed in backlog. Queue cap of 70 is re-affirmed — planning sessions creating >8 tasks when queue exceeds 70 are blocked. Senior execution drain rate is the only lever that matters for product velocity.

## Decisions for Human

1. **Hard queue cap:** Should the planning DOD be updated in program.md to require "queue < 70 before creating new non-P0 tasks"? This would surface the structural tension instead of quietly ignoring it every cycle.
2. **Analytical tools milestone:** `weight_trend_prediction` is live. Once `supplement_insight` + `food_timing_insight` ship, we're at 3/5 analytical tools for the "AI health coach" positioning. Should this trigger a dedicated TestFlight build note calling out the "health coach" identity?
3. **State.md ownership:** Should State.md refresh be added as a mandatory step 6a in the program.md Sprint Planning section ("refresh State.md before reading roadmap.md")?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
