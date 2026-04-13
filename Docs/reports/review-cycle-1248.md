# Product Review — Cycle 1248 (2026-04-13)
Review covering cycles 1224–1248. Previous review: cycle 1224.

## Executive Summary

Two items from the Review #33 sprint shipped: the food diary reorder bug is fixed (users can now reliably reorder meals even when multiple items were logged at the same time), and AI reliability tests hit 99% coverage — the highest in the codebase. The muscle group heatmap remains the one unshipped P1, deferred now for a third consecutive sprint. The next 20 cycles focus on two things: finally shipping the exercise heatmap, and extending the health coach pattern from passive dashboard alerts to active push notifications — the move that separates "data logger" from "coach."

## Scorecard

| Goal | Status | Notes |
|------|--------|-------|
| Fix food diary reorder (same-timestamp bug) | Shipped | Reorder now works reliably for AI-logged multi-item meals |
| IntentClassifier test coverage to 80%+ | Shipped | Reached 99% — highest coverage file in the codebase |
| Muscle group heatmap on exercise tab | Not Started | Deferred for the third time — P0 next sprint, no exceptions |
| Food DB search miss telemetry | Deferred | Moved to next sprint as P1 |

## What Shipped (user perspective)

- **Food diary reorder is reliable.** When you log multiple foods at once via AI, you can now reorder them without the swap silently doing nothing.
- **AI chat is more consistent.** Under-the-hood reliability improvements mean fewer cases where the AI misunderstands or misroutes a query.
- **Command Center streamlined.** Internal tooling cleaned up — fewer tabs, owner-only views separated cleanly.
- **Design doc review process in place.** New features proposed via design docs must be approved before development starts — prevents wasted cycles on unvalidated ideas.

## Competitive Position

We remain the only serious health tracker that is fully on-device, free, and handles complex multi-domain queries through conversation — logging, meal planning, workout design, and navigation all through chat. MFP ($20/mo Premium+), Whoop ($30/mo), and MacroFactor ($72/yr) are all expanding their AI capabilities behind paywalls; our entire feature set is free and private. The exercise vertical is our clearest gap: Boostcamp's visual exercise content (videos, muscle diagrams) and MacroFactor's workout auto-progression are significantly ahead of our text-only exercise display.

## Designer × Engineer Discussion

### Product Designer

I'm proud of the bug reliability this sprint — when users log breakfast through chat and then try to reorder their oatmeal above their eggs, it should just work. It does now. That's the kind of fix that builds daily trust.

What concerns me is the exercise tab. Muscle group heatmap has now been deferred three times. I set a "ship it or cut it" rule last review and we're still not there. Users who train seriously look at their workout history and see a wall of text — no visual summary of what they hit this week, no at-a-glance recovery insight. Boostcamp and MacroFactor users take this for granted. We need to ship something this sprint, even if it's a simple colored grid rather than a full body silhouette.

What excites me most for the next sprint: push notifications. Our proactive dashboard alerts (protein streak, supplement gap, workout consistency) are valuable — but passive. Users see them only if they open the app. A timely push ("You've been low on protein for 3 days") is the difference between a health tracker and a health coach. Whoop's AI push nudges are gaining traction precisely because of this. We can do it entirely on-device with no cloud dependency.

### Principal Engineer

Technically, this was a solid sprint. The food reorder fix — moving from timestamp-swapping to an explicit `sortOrder` column — is the right architectural decision. Timestamps should never be used as ordering keys when items can be created at the same millisecond.

IntentClassifier at 99% is a validation of the "test deterministic wrappers, not stochastic LLM output" pattern from Review #32. We reversed a 4-review assumption. That's the kind of engineering learning worth carrying forward.

For next sprint: the muscle group heatmap is medium complexity — query recent workouts, aggregate muscle group tags, render a visual grid. The exercise DB already has muscle group tags on all 873 exercises. This is mostly UI work. No new infrastructure needed.

Push notifications require the UserNotifications framework and one-time permission request. The notification content can be derived entirely from existing services (food log, supplement DB, workout history). The risk is permission prompt timing — we should ask only after the user has logged something meaningful, not on first launch. Implementation is straightforward but I'd plan 2-3 cycles for permission UX, notification scheduling, and edge case handling (don't notify at 3am, don't notify if user already logged today).

AIChatView.sendMessage is 491 lines. It blocks further AI chat feature work. I want to budget one cycle for decomposition before we add push notification hooks or any new AI behavior.

### What We Agreed

1. **Muscle group heatmap ships this sprint.** P0. No more deferrals — the data is there, the need is real.
2. **Push notifications for health patterns.** P0 next sprint. On-device scheduling, no cloud. Starts with 3 patterns: protein streak, supplement gap, workout gap.
3. **sendMessage decomposition first** before adding new AI behaviors. One cycle, medium risk.
4. **Food search miss telemetry.** P1. Add a lightweight local table that logs zero-result searches. First step to data-driven food DB improvement.
5. **Keep sprint to 4-5 items.** The formula is proven: tight scope, clear tiers, no mid-sprint additions.

## Sprint Plan (next 20 cycles)

| Priority | Item | Why |
|----------|------|-----|
| P0 | Muscle group heatmap on exercise tab | Deferred 3x — ships this sprint or we cut it |
| P0 | Proactive push notifications (protein / supplement / workout) | Passive alerts → active coach; on-device, no cloud |
| P1 | AIChatView.sendMessage decomposition | 491-line function blocks further AI feature work |
| P1 | Food search miss telemetry | Can't improve food DB without knowing what users can't find |
| P2 | Exercise instructions via chat ("how do I do a deadlift?") | Closes exercise content gap without requiring video/image storage |

## Feedback Responses

No feedback received on previous reports (PR #31 — Review #33 had no comments from ashish-sadh).

## Cost Since Last Review

| Metric | Value |
|--------|-------|
| Model | Sonnet 4.6 (Autopilot) |
| Sessions | 3 |
| Est. cost | $162.94 |
| Cost/cycle | $0.13 |

## Open Questions for Leadership

1. **Push notification timing:** When should Drift first ask for notification permission? Options: (a) after first successful food log, (b) after 3 days of use, (c) user-initiated from Settings. Which feels right for a privacy-first app?
2. **Exercise heatmap scope:** A simple colored grid (muscles hit = brighter) vs a body silhouette outline (anatomically accurate). Grid ships faster. Body silhouette is more compelling. Which matters more right now?
3. **Sprint refresh cadence:** Should we refresh the sprint mid-sprint when all P0s ship, rather than waiting 20 cycles? The last few sprints have had cycles with no sprint-level direction after early items ship.
