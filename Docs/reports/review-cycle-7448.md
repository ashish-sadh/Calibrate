# Product Review — Cycle 7448 (2026-04-26)

## Executive Summary

This cycle closed 2 of the 4 remaining failing-query categories (historical weekday queries, calorie goal setting) and completed a major DriftCore architecture migration — moving pure-logic tests from iOS simulator to `swift test`, retiring the legacy DriftRegressionTests target, and documenting the 5-tier test map. Build 175 is live on TestFlight. The product's AI chat is measurably more correct; the engineering foundation for autonomous fast testing is now in place.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 175 | +1 from last review |
| Tests | 2,061+ iOS + DriftCoreTests (grew with migration) | + (migrations moved pure-logic to faster macOS target) |
| Food DB | 2,511 | flat |
| AI Tools | 20 | flat |
| Coverage | ~50% services / ~80% logic | flat |
| P0 Bugs Fixed | 0 | — |
| Failing Query Categories Closed | 2 of 4 (historical dates, calorie goal) | ↑ |

## What Shipped Since Last Review

- **Historical weekday queries fixed**: "how many calories last Tuesday" / "what did I eat on Monday" now resolve correctly via `weekdayDateString()` + `historicalDaySummary()`. Two query variants supported: "last X" and "on X".
- **Calorie goal setting fixed**: "set my calorie goal to 2000" / "calorie budget 1800" now sets `WeightGoal.calorieTargetOverride` via StaticOverrides and is immediately reflected in `resolvedCalorieTarget()`.
- **DriftCore pure-logic test migration**: Waves 2–6 moved to `DriftCoreTests` — pure-logic tests now run in ~0.1s via `swift test` instead of 30s iOS simulator boot. DriftRegressionTests target retired and folded into DriftCoreTests.
- **5-tier test map documented**: CLAUDE.md now has an explicit decision tree for test tier assignment — prevents future test file misplacement.
- **Harness reliability**: Sessions now reliably reach the task loop; `gh` errors no longer swallowed silently; commit scoping prevents cross-agent pollution.
- **Build 175** shipped to TestFlight.

## Competitive Analysis

- **MyFitnessPal**: Launched a new "Today" tab redesign (April 2026) — but it backfired. Heavy user complaints: food logging takes more taps, diary is buried behind a "View All" button. This is a direct opportunity — Drift's AI chat makes logging faster, not slower. MFP is proving that tab-centric redesigns add friction; chat-first removes it.
- **Whoop**: Behavior Trends + Behavior Insights live (habit → Recovery correlation after 5 entries). AI Strength Trainer now generates workouts from natural language prompts. Passive MSK covers rucking/Solidcore. Biomarkers now mapped to Healthspan pillars. Whoop is expanding the habit-correlation pattern we've been building analytically.
- **Boostcamp**: Minor bug fixes in March–April 2026. No major features. Still the gold standard for exercise presentation (videos, muscle diagrams) but not innovating.
- **Strong**: No significant updates tracked this cycle.
- **MacroFactor**: Workouts app (Jan 2026) now shipping; Favorites feature for saved serving sizes; Expenditure Modifiers with step-informed calorie adjustments; AI food logging improvements in progress. Apple Health write integration coming. MacroFactor is deepening its all-in-one story — the same lane Drift occupies.

## Product Designer Assessment

*Speaking as the Product Designer persona:*

### What's Working

- The failing-query fix for historical dates closes a visible trust gap. "Last Tuesday" returning today's data was the kind of answer that makes users stop trusting the AI entirely. This is exactly the right category to close first.
- DriftCore test speed (0.1s vs 30s) is infrastructure that directly enables faster iteration on AI quality. Every AI change can now be verified in seconds, not minutes — that's a compound win across every future sprint.
- MFP's Today tab backlash is a competitive gift. Their redesign proves that adding taps to logging destroys user goodwill. Our chat-first model is the anti-MFP: zero taps, just type.

### What Concerns Me

- **Two failing-query categories remain**: micronutrient queries (fiber/sodium/sugar) and macro goal progress ("am I hitting my protein goal"). These are daily-use questions for health-conscious users — the kind of thing they'll test in the first week. Both require DB migrations and data model changes; they're not prompt fixes.
- **Food DB is flat at 2,511**. No enrichment this cycle. The MFP gap is 20M vs 2,511 — we're not closing it manually. The USDA API Phase 2 task (#345) has been in queue for multiple cycles. At current trajectory, every session of zero food DB growth is a session where "not found" drives a user to MFP.
- **State.md still shows build 174, 30 macOS tests**. After the test migrations, DriftCoreTests grew significantly but the doc hasn't been updated. Stale state misleads every senior session that reads it.

### My Recommendation

Close the remaining 2 failing-query categories this sprint. Micronutrient tracking (#442) and macro goal progress (#440, #441) are the visible AI chat gaps for health-aware users. After those ship, the failing-queries.md "Failing" section will be empty — a milestone worth marking. Then: USDA API Phase 2 to restart food DB growth.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona:*

### Technical Health

The test infrastructure migration is the most impactful architectural improvement in recent cycles. Moving pure-logic tests to `swift test` (0.1s) makes the Tier 0 loop feasible in practice — previously, any logic change required a 30s simulator boot to verify. The 5-tier decision tree in CLAUDE.md closes the misplacement problem that was slowly accumulating tech debt in test organization.

Harness reliability improvements (reaching task loop, non-swallowed `gh` errors, commit scoping) are foundational. Silent failures in the harness are worse than crashes — they mask execution failures as "completed" sessions. This is fixed.

The historical date fix and calorie goal fix followed the right tier: StaticOverrides/RuleEngine, not prompt tweaks. Both are deterministic and testable.

### Technical Debt

- **Micronutrient schema**: `fiber_g`, `sodium_mg`, `sugar_g` are not on FoodEntry. This is DB migration v35, and it requires nil-safe reads for all pre-migration rows. The pattern is established from prior migrations — the risk is backfill scope (don't backfill historical rows from Food table; too slow and accuracy is unknowable).
- **Macro goals schema**: `calorieGoal` / `proteinGoal` not in UserPrefs. Required before macro goal progress queries can work. Strictly ordered with the macro goal progress task — data model first, query second.
- **State.md staleness**: Still showing stale build/test counts. This is a junior task that's been deferred multiple cycles. It actively misleads planning.
- **USDA API Phase 2 (#345)**: In queue since cycle 4734. At 2,511 foods vs MFP's 20M, manual curation is not the answer. The API is free, the infrastructure exists (Phase 1 is live), and the task is scoped. Oldest high-value unexecuted task in the queue.

### My Recommendation

Implement micronutrient tracking (#442) and macro goals (#440, #441) in strict order — #440 first because #441 depends on its DB migration. This closes the last visible AI chat gaps. Then State.md refresh (#410 or equivalent) as a junior task. Then USDA API Phase 2 to restart food DB growth at scale.

## The Debate

**Designer:** The remaining 2 failing-query categories are user-trust killers. A user who asks "how much fiber did I eat?" and gets a non-answer stops trusting the AI. We've closed 2 of 4 this cycle — momentum is there, close the last 2 now. Then MFP's Today tab backlash is our marketing window: we should be showing that AI-first logging is *faster*, not redesigning tabs.

**Engineer:** Agreed on the failing queries — they're the right priority. But I want to flag that micronutrients (#442) requires DB migration v35 (adding nullable columns to FoodEntry) and nil-safe aggregation. This is a 1-session SENIOR task, not a junior quick fix. And macro goals (#440 + #441) are strictly ordered — #441 must claim #440's migration before any work begins. If a session claims both simultaneously, the second will fail. Planning must note this dependency explicitly.

**Designer:** Fair. Then sequencing is: #440 → verify migration lands → #441 → then #442 in parallel if there's SENIOR budget. After those 3, food DB growth is the unlock. MFP's Today tab is actively alienating users right now — if we ship a TestFlight with better chat logging AND USDA-backed food search, we can start telling that story to TestFlight users.

**Engineer:** Agree on sequencing. One more flag: State.md staleness. It's a junior task, 15 minutes. Every cycle it's stale, senior sessions read wrong context and make wrong assumptions. This must be the first junior task this sprint before any implementation work. Then #440 → #441 → #442 for senior. USDA Phase 2 (#345) after those clear.

**Agreed Direction:** Close the 2 remaining failing-query categories in strict dependency order (#440 → #441 for macro goals, #442 for micronutrients). State.md refresh as first junior task. USDA API Phase 2 queued immediately after, as the food DB growth unlock.

## Decisions for Human

1. **USDA API Phase 2 priority**: Issue #345 has been in queue since cycle 4734. It's the highest-ROI food DB move available (400k+ verified foods, free API, Phase 1 infra already live). Should this be elevated to P0 so it claims senior budget immediately after the failing-query closures? Or maintain current priority?

2. **Macro goal types**: Closing non-weight goals (#440) adds `calorieGoal` and `proteinGoal` to UserPrefs. Should we also add `carbGoal` and `fatGoal` in the same migration, or scope strictly to calorie + protein first (the two most-queried)?

3. **TestFlight feedback**: Build 175 is live. Any specific queries or flows you'd like tested before the next build? The failing-query fixes (historical dates, calorie goals) are the best candidates to probe.

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
