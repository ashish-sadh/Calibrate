# Product Review — Cycle 341 (2026-04-18)

## Executive Summary
Cycle 341 is a planning-first review that refocuses the sprint on AI chat depth — pipeline threading, `edit_meal` tool, conversation persistence, structured nutrition cards, and meal-period auto-detect. Seven real-world bugs (186–192, 195) filed same-day from TestFlight prove users are stressing the chat pipeline; four P0 recipe/food friction bugs are already queued, and three approved P1 bugs were promoted into the sprint this session. No user-visible ship this cycle (planning-only); the coming senior/junior sessions will drain a ~21-item queue targeting measurable chat quality improvements while keeping FoodLoggingGoldSet at 100%.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 138 | +5 since last review (#133) |
| Tests | 1,564+ | +622 (LLM eval expanded + infra suites) |
| Food DB | 2,187 | +687 since cycle-199; +0 this session |
| AI Tools | 20 | steady |
| Coverage | ~60% overall, IntentClassifier 99% | stable |
| P0 Bugs Fixed | 4 in-queue (186, 187, 191, 192) | 0 closed this session |
| Sprint Velocity | N/A (planning cycle) | queue: 21 items |

## What Shipped Since Last Review
This is a planning session — no user-visible shipping this cycle. Recent cycles (via git log) show heavy infrastructure work on the watchdog, Drift Control, hooks, and the planning/sprint service layer — which was necessary but must now convert into product velocity.

- Graphify knowledge-graph for codebase navigation landed (dev tooling only, no user impact).
- TestFlight auto-publish cadence + preflight hardened (builds 137, 138).
- Watchdog crash/stall recovery, compliance ordering, planning-issue safety — all invisible to users but essential for autonomous operation.
- Command Center bug badge + P1/P2 dedup shipped the same day as this planning session (commit 84779cb by an overlapping autopilot session).

The opportunity cost is visible: 20+ of the last 40 commits are infra/drift-control rather than AI or UX. The sprint we just planned is explicitly 100% AI-chat / bug-fix to rebalance.

## Competitive Analysis
No fresh web search this cycle (planning session, reusing competitor posture from the prior review log).

- **MyFitnessPal:** Cal AI (photo scanning) + ChatGPT Health integration remain their moat. 20M-food DB. Cloud-dependent; all premium AI features paywalled.
- **Boostcamp:** Still the gold standard for exercise visual presentation (videos, muscle diagrams).
- **Whoop:** AI Strength Trainer accepts text + photos; Behavior Insights tie habits to Recovery; proactive push nudges are their signature coaching pattern.
- **Strong:** Minimal, fast set/rep entry. Hasn't expanded — our advantage window is holding.
- **MacroFactor:** Workouts app (Jan 2026) brings auto-progression + Jeff Nippard videos at $72/yr. Their adaptive TDEE remains best-in-class.

Our moat is unchanged: on-device, all-in-one, chat-first, free. Every cycle we don't improve chat quality is a cycle the cloud competitors widen the experience gap.

## Product Designer Assessment

*Speaking as the Product Designer persona (Docs/personas/product-designer.md).*

### What's Working
- Proactive alerts are now our defining UX pattern — six behavioral signals on the dashboard make the app feel like a coach, not a data logger.
- Confirmation cards across 8 domains make chat feel like a real messaging app. The architecture is extensible and proven.
- TestFlight dogfooding is producing high-signal bug reports. The user filing 7 bugs in one day after voice + chat use is the healthiest possible feedback loop.

### What Concerns Me
- Recipe editing flow is broken in two P0 ways (cannot edit ingredients after add, Done button doesn't log "add to recipe"). This is a trust-eroding state — users are discovering a partially-functional feature.
- "This is my breakfast" is a first-class mental model the app does not meet (#189). A flat food list is MFP-2012 UX; meal-period grouping with auto-detection is table stakes.
- South Indian coverage gap (#188) is a direct competitive loss for our Indian-user base. Chat-first logging blunts this, but a "not found" on dosa-sambar drives a user to MFP.
- "Coffee with milk" returning 0 kcal (#195) is the worst kind of silent failure — the app looks confident while being wrong.

### My Recommendation
Fix the four P0 recipe/food-list bugs this week. Ship the sprint's `edit_meal` tool, meal-period auto-detect, and nutrition card in the same push — together they transform chat from "can log food" to "can own the whole meal lifecycle." Do not start any new visual surface (widgets, Watch, photo) until these land.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona (Docs/personas/principal-engineer.md).*

### Technical Health
- 1,564 tests, IntentClassifier at 99%, 6-stage pipeline with gold-set baseline. The AI subsystem is the healthiest it's ever been architecturally.
- Drift Control / watchdog / planning service are the most complex piece of infra in the repo, and they've been stabilizing for ~40 commits. Diminishing returns from here — any further infra work needs an explicit product justification.
- Graphify is an experiment; value unclear until we use it to actually reduce token budgets in real sessions. Treat as dev-tool until proven.

### Technical Debt
- **Composed-food lookup** (bug #195) suggests the USDA fallback + "with X" modifier path is dropping additive calories somewhere. This is a correctness bug in a core path; audit end-to-end.
- **Recipe mutation path** (#191, #192) is underspecified — we shipped write, not edit/delete. Every write on a structured object needs a matching mutation API at the same layer.
- **Last-review-time vs git-log validation** mismatch: the planning hook's `validate` requires a review commit in 7h, but the `review-due` script uses a file timestamp. When they disagree, planning gets blocked. Fix the validation to also accept a recent `last-review-time` file, or fold review-due logic into validate.

### My Recommendation
This cycle: ship the `edit_meal` tool (#197) and session-persistent state (#203) as the two senior items — both close real architectural gaps surfaced by user bugs. Defer context-threading (#198) one cycle until edit_meal is in — it will otherwise compete for the same prompt real estate. After this sprint, freeze new infra for two full cycles. Measure, don't build tooling.

## The Debate

**Designer:** Users are telling us exactly what to build — seven bugs in one day. Ship the bug fixes + `edit_meal` + meal-period auto-detect this week. Everything else waits.

**Engineer:** Agreed on the bug fixes. I want to push back on stacking `edit_meal` + context threading + session persistence in one sprint — that's three senior-budget items in one domain. Pick two.

**Designer:** `edit_meal` and session persistence. Context threading can wait one cycle — it's an amplifier, not a foundation. We need users to trust that the app doesn't lose their state first.

**Engineer:** Deal. And after this sprint, we freeze infra for two cycles. If I catch another watchdog fix merging before two feature commits, I'm escalating.

**Agreed Direction:** Drain the P0 bug queue (186, 187, 191, 192, 195) first. Senior budget this sprint goes to `edit_meal` (#197) and session persistence (#203). Context threading (#198) defers one cycle. Zero new infra work unless it unblocks a user-visible fix.

## Decisions for Human

1. **Context threading priority** — Designer and Engineer agreed to defer #198 one cycle. Confirm, or override to ship it this sprint?
2. **Infra freeze** — Can we commit to two full cycles of zero watchdog/hook/planning-service changes unless a session-ending bug forces it?
3. **South Indian enrichment scope** — Should #188 become a dedicated 30-dish data task (JSON-only, zero risk, high user signal), or roll it into a broader "search-miss telemetry + enrich top 30" initiative?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
