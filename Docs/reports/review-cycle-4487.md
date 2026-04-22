# Product Review — Cycle 4487 (2026-04-21)

## Executive Summary

Since the last full product review (cycle 3200), the AI chat pipeline has been meaningfully hardened: Photo Log went multi-provider with BYOK fallback chain, domain-aware intent thresholds replaced the single global confidence cutoff, `cross_domain_insight` opened the first analytical tool category, and voice health-term repair closed a silent trust gap. The product is at the inflection point between "reliable chat logging" and "AI health coach" — the analytical tools sprint (#317 + pending #312–#319) is the bridge. Next focus should be closing the clarification card (#316), per-stage attribution (#312), and launching the daily-briefing feedback nudge to re-engage the silent TestFlight pool.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 162 | +5 since last review (157→162) |
| Tests (DriftTests) | 886+ | +143 from coverage sprint |
| Food DB | 2,511+ | +180 since cycle 3200 |
| AI Tools | 20 | +1 (cross_domain_insight) |
| Coverage | 80%+ logic / 50%+ services | Targets met |
| P0 Bugs Fixed | 4 (intent routing, photo dismiss, telemetry toggle, intent classifier) | |
| Sprint Velocity | ~70% | Consistent; SENIOR queue is binding constraint |

## What Shipped Since Last Review

- **cross_domain_insight tool** (#317) — First analytical tool. Users can now ask correlational questions ("does my protein intake affect my lifting?") across food/weight/exercise/glucose. New tool category: transactional → analytical.
- **Photo Log multi-provider** (#298) — OpenAI and Gemini added alongside Anthropic BYOK. Real provider error messages surface instead of generic failures. "Bring your favorite AI vision key" is the UX story.
- **Photo Log UX overhaul** (builds 161–162) — Editable macros on review screen, AI-returned serving units and ingredients preserved, per-provider model picker, plant badge, fiber tracking. Photo Log now feels like a first-class feature, not a prototype.
- **Domain-aware IntentThresholds** (#302) — Per-domain confidence cutoffs replace single global threshold. Food, weight, exercise, sleep each calibrated independently via telemetry.
- **Telemetry raw-text persistence** (#297) — Every query + response is persisted locally for debugging and gold-set growth. `/debug last-failures` ticket (#301) turns this into an on-device consumer.
- **Voice health-term repair** (#285) — Post-transcription dictionary pass corrects metformin/creatine/whey misrecognitions. Silent quality win competitors can't match on cloud voice pipelines.
- **SmolLM↔Gemma parity invariants** (#286) + **TTFT smoke default** (#287) — Cross-model consistency enforced in CI; latency regression threshold runs on every commit by default.
- **Intent classifier routing fix** (#277) — 'log pizza' was routing to food_info (lookup) instead of log_food. Fixed root cause of reported user confusion (#271).
- **Watchdog commit-rate stall detector** — 3-hour / 0-commit threshold kills stalled sessions. Closes the "infinitely spinning" failure mode in autonomous operation.
- **Hash-gated food reseed** — Food DB seeding is now idempotent and hash-gated. Prevents duplicate seed data on re-runs.

## Competitive Analysis

- **MyFitnessPal:** Completed Cal AI integration (photo-to-log, 15M downloads). MFP+Cal AI is now the cloud benchmark: cloud vision + 20M DB. Premium+ at $20/mo covers photo scan + AI tools. Their moat is database breadth + distribution, not privacy. Directly relevant: branded food (#304 queue) and restaurant chains (#231 queue) are the biggest gaps vs MFP in our DB.
- **Boostcamp:** Still the gold standard for exercise content — exercise GIFs/videos, muscle diagrams, detailed form instructions. We have 960 exercises text-only. This is an active gap but lower priority than chat quality given our AI-first identity.
- **Whoop:** AI Coach with conversation memory and contextual proactive nudges at $30/mo. Behavior Insights (habits → Recovery correlation) is their newest sticky feature. Our proactive alerts (protein/supplement/workout streak on dashboard) are the free, on-device equivalent — but push notifications have more reach than dashboard cards.
- **Strong:** Remains clean and focused for set/rep logging. No major AI additions. Our multi-turn workout dialogue is ahead of them in AI-first UX.
- **MacroFactor:** Workouts app (Jan 2026) added progressive overload automation, cardio tracking, Apple Health write, AI recipe photo logging at $72/year. They're completing the all-in-one story. Key difference: cloud + subscription vs. our on-device + free.

## Product Designer Assessment

*Speaking as the Product Designer persona (read Docs/personas/product-designer.md first):*

### What's Working
- **Photo Log BYOK story** is genuinely differentiated. "Bring your own API key, get cloud-quality food scanning, pay the vendor directly — no subscription" is a pitch that resonates with power users who are already paying for Claude/OpenAI. The multi-provider fallback chain makes it feel professional.
- **cross_domain_insight is the right direction.** Users want insight, not just logging. "How does my sleep affect my next-day eating?" is a question no app currently answers on-device. This tool is small but it's the first in a category — the product story shifts from data logger to health analyst.
- **Voice health-term repair** is invisible quality that builds trust over time. Users who use voice for "metformin 500mg" and get a perfect log entry will never know the app repaired "muttering" to "metformin" — and that's exactly right. Trust built silently compounds.

### What Concerns Me
- **Four cycles with zero user-filed bugs or feature requests.** This is not signal of satisfaction — it's signal of silence. The TestFlight beta pool may have reduced. The "Reply to this email" nudge in release notes was planned in cycle 3985 and hasn't shipped. This must go out in build 163's notes, plus an in-app Settings → Feedback entry. Silence isn't safety.
- **Clarification card (#316) is on a feature branch but not merged.** This is the UX counterpart to every confirmation card: instead of "I logged X" → "Did you mean A or B? [tap]". Text input as the failure mode. Every sprint we wait on this, users who ask ambiguous food questions get a freeform clarify prompt instead of a 1-tap choice. Friction compounds.
- **38 pending sprint tasks with SENIOR queue as the binding constraint.** The design debt here is not the number of tickets — it's that the analytical tool category (#317) opened without a roadmap commitment to the next 3-5 analytical tools. We need a roadmap entry: "Analytical tools — correlate glucose/food, sleep/recovery, supplements/biomarkers." Otherwise the cross_domain_insight ships and the pattern goes dormant.

### My Recommendation
Ship clarification card (#316) and get feedback nudge into next TestFlight release notes. Then focus one full senior sprint on per-stage failure attribution (#312) — we can't know if the analytical tools are accurate without stage-level visibility. The product roadmap should explicitly call out analytical tools as the bridge to Phase 5 (Deep Intelligence).

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona (read Docs/personas/principal-engineer.md first):*

### Technical Health
- **Test infrastructure is at 4-layer maturity**: FoodLoggingGoldSetTests (intent), PerToolReliabilityEval (tool selection), MultiTurnRegressionTests (state machine), ChatLatencyBenchmark (perf). This is the right architecture — any regression surfaces at the right layer.
- **Photo Log provider abstraction** is clean. Each provider is isolated; the fallback chain (#300 — queued) is additive. Adding a 4th provider would be a 2-file change. Architecture is sound.
- **cross_domain_insight tool** reads from 2+ domain services read-only. No state mutations. The pattern is clean and the category is established — next analytical tools slot in by following the same pattern.
- **Telemetry loop** is now two-thirds closed: emission (#297) + planned consumer (#301). When #301 ships, the loop is complete. The lesson from cycles 261/297 is enforced: telemetry without a reader is shelfware.

### Technical Debt
- **DomainExtractor (Stage 3) still has no isolated gold set.** Every other stage has one. Stage 3 is the invisible middleware between routing and tool call — a 5% extraction drift shows as "wrong quantities" with no clear attribution. Ticket #312 (per-stage failure taxonomy) partially addresses this but Stage 3 needs its own 50-query eval, not just attribution piggyback.
- **Photo Log review screen growing complexity.** Editable macros + fiber + plant badge + ingredients + serving unit picker — the view is accumulating state. Pre-emptive: if we add one more feature to this screen, extract a PhotoLogReviewViewModel. Not urgent yet but the threshold is close.
- **Context window is at 4096 tokens** with bump to 6144 queued (#315). As noted in cycle 4247: every n_ctx bump must ship with its prompt audit, or the growth is absorbed by sloppy prompts instead of conversation history. Do not merge #315 without the stage-prompt audit proving ≤ same token count per stage.

### My Recommendation
Land #316 (clarification card) + #312 (per-stage attribution) as the first SENIOR tasks this sprint. #316 closes a user-facing trust gap; #312 gives us attribution data to make every subsequent AI task defensible. Hold #315 (context window bump) until the prompt audit is done — merging without it inverts the intended win.

## The Debate

**Designer:** The biggest product gap right now is the feedback vacuum. Four cycles of silence means we may be optimizing for the wrong things. Before we ship the next 10 sprint tasks, we need signal from actual TestFlight users. Add a feedback nudge to build 163 release notes and an in-app feedback entry in Settings. That's a one-sprint P0 — not because it's glamorous, but because we're flying blind.

**Engineer:** Agree on feedback nudge — it's trivially cheap (release notes text + one Settings row). But I'd caution against pausing the AI pipeline work waiting for feedback. The #316 clarification card and #312 stage attribution are both structural improvements with known user-facing value from the existing gold sets. We don't need user feedback to know these are correct next steps. Ship both; feedback nudge gets bundled into the next TestFlight build.

**Designer:** Fair — I'm not saying pause, I'm saying bundle the nudge explicitly. The risk I see is that if we get feedback after the next 10 tasks ship and it points in a different direction, we'll have wasted cycles. The nudge costs nothing and reduces that risk. Counter-proposal: make #316 and the feedback nudge a single build (163), then continue the queue. The nudge is in the TestFlight release notes, not a sprint task.

**Engineer:** That works. Feedback nudge in build 163 release notes (non-sprint, zero code, one sentence in the notes). #316 is the sprint P0. #312 is the P1. Then continue analytical tools and queue drain. One structural risk: queue depth is 38 pending with only senior sessions as drain. If we don't increase drain rate, queue grows without bound. Recommend: don't add more than 8 tasks per planning cycle until queue drops below 25.

**Agreed Direction:** Bundle clarification card (#316) and feedback nudge into build 163. Prioritize #312 (per-stage failure attribution) as the P1 for the next senior sprint. Cap new task creation to ≤ 8 per planning cycle until queue drops below 25.

## Decisions for Human

1. **Feedback strategy**: The in-app Settings → Feedback entry was recommended in cycle 3985 and again here. Should this be a sprint task (light implementation: mailto: link or in-app form) or just release-notes text? Options: (a) release notes text only (2 minutes), (b) Settings → "Send Feedback" mailto row (30 minutes), (c) in-app feedback form (2+ days). What's the right level of investment given the current user count?

2. **Analytical tools roadmap commitment**: `cross_domain_insight` opened a new tool category. Should we explicitly add 3-5 analytical tool tickets to the roadmap "Now" section (correlate glucose/food, sleep/recovery, supplements/biomarkers)? Or keep them in backlog until the current queue drains?

3. **Queue growth cap**: Current recommendation is ≤ 8 new tasks per planning cycle until queue drops below 25 (currently 38). Does this match the cadence you want? Or should planning cycles add more aggressively and trust senior sessions to drain?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
