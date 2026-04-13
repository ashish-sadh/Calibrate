# Product Review — Cycle 849 (2026-04-12)

Review covering cycles 829–849. Previous review: cycle 829.

## Executive Summary

No new user-facing features shipped in this window — all 20 cycles were consumed by review documentation and process overhead. The previous sprint (Reviews #24–#25) delivered three major features (chat navigation, USDA food search in chat, bug fixes) but the sprint was never refreshed afterward. We need to close the completed sprint, set a fresh one, and start building again immediately.

## Scorecard

| Goal | Status | Notes |
|------|--------|-------|
| Navigate to Screen from Chat (P1) | Shipped | Completed in cycle 806, documented in Review #25 |
| Wire USDA into AI Chat (P1) | Shipped | Completed in cycle 807, documented in Review #25 |
| Systematic Bug Hunting (P1) | Shipped | Completed in cycle 808, documented in Review #25 |
| IntentClassifier Coverage (P2) | Deferred | 5th consecutive review. Accepting 63% as floor for LLM code |

## What Shipped (user perspective)

Nothing new shipped to users since the last review. The previous sprint's deliverables (already reported in Review #25):

- Users can say "show me my weight chart" or "go to food tab" in chat and the app navigates there instantly
- Typing "log acai bowl" in chat now finds foods from USDA even when they're not in the local database
- The app no longer hangs if the USDA search is slow — it times out gracefully after 5 seconds
- Fixed a potential crash when navigating to invalid tabs

## Competitive Position

MFP continues consolidating AI features through acquisitions (Cal AI, ChatGPT integration). Whoop launched tiered hardware ($199–$359/year) and a Women's Health biomarker panel. MacroFactor expanded into workouts with Live Activities. Our differentiator — full conversational app control entirely on-device with zero data leaving the phone — remains unique. The gap is content richness: we have 1,500 foods vs MFP's 20M, and text-only exercises vs Boostcamp's video library.

## Designer × Engineer Discussion

### Product Designer

I'm concerned about velocity stalling. We had a strong run — three P1 features shipped in rapid succession — but then 20 cycles of zero user-visible output. The review process is important but it's eating cycles that should be building features.

The competitive landscape is accelerating. Whoop's Women's Health panel (11 biomarkers, cycle-hormone integration) is exactly the kind of cross-domain insight we should be doing. MFP's ChatGPT integration validates conversational health AI, but their cloud dependency is our opening.

For the next sprint, I want to push two things: (1) a visual refresh that makes the app feel premium — the current dark theme is functional but not distinctive, and (2) the workout split builder, which extends our meal planning dialogue pattern into exercise. Both create stickiness.

### Principal Engineer

The review-to-feature ratio is inverted. Twenty cycles of process, zero cycles of product. The review cadence (every 20 cycles) is correct when cycles produce code; it's wasteful when cycles are consumed by reviews and documentation.

Technically, the foundation is solid. 966 tests, 20 AI tools, dual-model pipeline, Swift 6 concurrency clean. The next sprint should be pure feature delivery. I'd prioritize the workout split builder — it reuses the meal planning state machine pattern (`planningMeals` → `planningWorkout`), requires minimal new infrastructure, and exercises the multi-turn dialogue system that is our core differentiator.

IntentClassifier at 63% coverage has been tracked for 5 reviews. It's LLM-dependent code where deterministic tests have diminishing returns. Accept this as the floor, remove from sprint tracking, and invest those cycles in features instead.

### What We Agreed

1. **Sprint refresh now.** Close the completed sprint. No more deferred P2 carryover.
2. **Pure feature focus.** Next 20 cycles must produce user-visible features, not documentation.
3. **IntentClassifier 63% accepted.** Remove from sprint scope permanently.
4. **Workout split builder is the P0.** Multi-turn dialogue, reuses meal planning architecture.
5. **UI polish as P1.** Theme refresh or chat UI improvements — something users see immediately.
6. **Roadmap update:** Mark USDA chat integration as DONE.

## Sprint Plan (next 20 cycles)

| Priority | Item | Why |
|----------|------|-----|
| P0 | Workout split builder — "build me a PPL split" → multi-turn workout design | Extends AI-first identity into exercise domain. Reuses meal planning state machine. |
| P1 | Chat UI improvements — rich confirmation cards for more actions, improved typing indicators | Users see chat quality first. Every AI response should feel polished. |
| P1 | Bug hunting on current code paths | Quarterly ritual. Find silent issues before users do. |
| P2 | Food DB enrichment — focus on search miss frequency | Every "not found" sends users to MFP. Prioritize most-searched missing foods. |

## Feedback Responses

No feedback received on previous reports.

## Cost Since Last Review

| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions | 8 |
| Est. cost | $588.20 |
| Cost/cycle | $0.69 |

## Open Questions for Leadership

1. **Should the review cadence change?** Every 20 cycles works when cycles produce code, but reviews themselves consume cycles that trigger more reviews. Consider moving to time-based reviews (weekly) or milestone-based (after N features ship) instead.
2. **Workout split builder vs theme refresh — which has more user impact?** Both create stickiness. The split builder extends AI capabilities; the theme refresh makes every screen feel premium. Which matters more for current TestFlight testers?
3. **IntentClassifier 63% — formally close?** This has been tracked for 5 reviews with no progress. Recommend accepting as the natural ceiling for LLM-dependent test code and removing from all sprint/review tracking.
