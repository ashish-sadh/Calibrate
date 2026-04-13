# Product Review — Cycle 869 (2026-04-12)

Review covering cycles 849–869. Previous review: cycle 849.

## Executive Summary

Third consecutive review window with zero user-facing features. All cycles have been consumed by the review process itself — writing reports, updating documentation, creating PRs, merging PRs. The review mechanism (trigger every 20 commits) counts its own documentation commits, creating a self-reinforcing loop that prevents feature work. This review proposes an immediate fix: skip reviews until the next feature ships, then resume on a milestone basis.

## Scorecard

| Goal | Status | Notes |
|------|--------|-------|
| Workout split builder (P0) | Not Started | Review loop consumed all cycles since sprint refresh |
| Chat UI improvements (P1) | Not Started | Blocked by review loop |
| Bug hunting (P1) | Not Started | Blocked by review loop |
| Food DB enrichment (P2) | Not Started | Blocked by review loop |

## What Shipped (user perspective)

Nothing new shipped to users in this window. The last user-visible change was USDA food search in AI chat, shipped ~60 cycles ago (cycle 808).

## Competitive Position

No change from Review #26. Our on-device conversational AI (log, query, navigate, plan, discover) remains unique. MFP, Whoop, and MacroFactor continue expanding cloud AI features. The competitive gap is stable but we're not widening it while stuck in the review loop.

## Designer × Engineer Discussion

### Product Designer

I'm raising an alarm. Three reviews in a row with nothing to show users. The review process was designed to ensure quality and direction — instead it's become the primary output. We've spent ~60 cycles (since cycle 808) producing reviews instead of features. That's roughly $40 in compute costs generating reports about having nothing to report.

The sprint we set in Review #26 is solid — workout split builder, chat UI, bug hunting. None of it has started because every time we commit review documentation, the cycle counter advances, and 20 commits later another review triggers. The review is eating itself.

I want to suspend the review cycle entirely until the workout split builder ships. Then resume with a milestone-based trigger: review after every 2 features shipped, not every 20 commits.

### Principal Engineer

The root cause is clear: the review hook fires on `PostToolUse git commit`, incrementing a cycle counter. Review documentation requires multiple commits (report, personas, sprint, roadmap, review log, PR merge). Each review generates 4-6 commits, so two reviews within the same session consume 8-12 of the 20-commit budget for the next review. Add the merges of prior review PRs and it's 15+ commits of pure process.

Possible fixes, in order of preference:
1. **Skip reviews until next feature ships.** Simplest. Just don't trigger.
2. **Milestone-based trigger.** Review after N features ship (e.g., every 2 feature commits), not N total commits.
3. **Exclude doc-only commits from cycle counter.** Only count commits that touch `.swift` files.

Option 3 is the cleanest long-term fix but requires modifying the hook script. Option 1 gets us building immediately. I recommend option 1 now, option 3 when we next touch the hooks.

### What We Agreed

1. **Suspend reviews until the workout split builder ships.** No more reviews until a real feature is delivered.
2. **After next feature ships, do one review, then switch to milestone-based cadence** (review after every 2 feature PRs, not every 20 commits).
3. **Sprint plan unchanged from Review #26.** It was never executed — just resume it.
4. **Merge PR #21 now** to stop accumulating open review PRs.

## Sprint Plan (next 20 cycles)

| Priority | Item | Why |
|----------|------|-----|
| P0 | Workout split builder — "build me a PPL split" | Extends AI-first identity to exercise. Reuses meal planning architecture. |
| P1 | Chat UI improvements — rich confirmation cards | Users see chat quality first. Structured cards for all actions. |
| P1 | Bug hunting on current code paths | Quarterly ritual. Find issues before users do. |
| P2 | Food DB enrichment — search miss frequency | Every "not found" sends users to MFP. |

## Feedback Responses

No feedback received on previous reports.

## Cost Since Last Review

| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions | 8 |
| Est. cost | $597.81 |
| Cost/cycle | $0.68 |

## Open Questions for Leadership

1. **Should we suspend reviews until the next feature ships?** The review loop has consumed 60+ cycles with zero features. We recommend pausing reviews entirely until the workout split builder is delivered.
2. **After resuming, should reviews trigger on feature milestones (every 2 features) instead of commit count (every 20 commits)?** This would prevent documentation commits from inflating the review cadence.
