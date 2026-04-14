# Product Review — Cycle 1380 (2026-04-13)
Review covering cycles 1355–1380. Previous review: cycle 1289 (Review #35).

## Executive Summary
Muscle group heatmaps shipped with full volume-intensity shading — users can now see at a glance which muscles are overworked vs. neglected. However, only 1 of 5 sprint items delivered. Push notifications (the #1 product gap) remain unstarted after 4 consecutive deferrals. This sprint must focus entirely on push notifications — nothing else moves the needle on the "health coach" identity.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| Muscle group heatmap (P0) | Shipped | Set counts + opacity intensity by volume. Two commits. |
| Push notifications (P0) | Not Started | 4th deferral. Critical product gap. |
| sendMessage decomposition (P1) | Not Started | Deferred — no blocking need this sprint. |
| Food search miss telemetry (P1) | Not Started | Deferred — infrastructure, not user-facing. |
| Exercise instructions via chat (P2) | Not Started | Expected deferral at P2. |

## What Shipped (user perspective)
- **Muscle group heatmap** — The exercise tab now shows a visual body map where shading intensity reflects training volume. Darker muscles = more work this week.
- **Weekly set tracking** — Each muscle group shows its exact weekly set count, helping users spot imbalances.
- **TestFlight builds 110–112** — Three beta builds shipped to testers in one day, keeping the beta channel active.
- **AI intent recognition at 99%** — Chat now correctly understands virtually every query type, reducing "I don't understand" responses.

## Competitive Position
Our AI-first, on-device privacy story remains unique — MFP's AI features are cloud-only and behind a $20/mo paywall, Whoop's AI Coach requires $30/mo. The muscle heatmap narrows the exercise visual gap vs. Boostcamp, but we're still text-only for exercise instructions while competitors show videos and diagrams. The biggest gap is now proactive engagement: Whoop sends push nudges based on AI-detected patterns; we show alerts only when users open the app.

## Designer x Engineer Discussion

### Product Designer
The muscle heatmap is exactly what I wanted — volume as visual weight, not just numbers. This is the pattern for all our data: show it, don't just list it. But I'm genuinely concerned about push notifications. This is the 4th time we've planned it and the 4th time it hasn't shipped. Every health app worth using sends timely nudges. "3 days low protein" as a notification is qualitatively different from a dashboard card nobody sees. This is the single biggest gap between "data logger" and "health coach."

Looking at competitors: Whoop's proactive nudges (stress detection, sleep debt alerts) are driving their retention numbers. MFP's engagement relies on streak notifications. We have the intelligence (6 alert types on dashboard) but zero delivery mechanism to users who aren't actively in the app. This needs to be the only P0 this sprint. No distractions.

### Principal Engineer
Muscle heatmap implementation was clean — `volumeIntensity(for:)` as a normalized 0–1 value drives opacity, keeping computation in the view since it's presentation-only. No architectural concerns there.

For push notifications: the technical path is straightforward. `UserNotifications` framework, local scheduling, no cloud dependency. The risk is entirely UX: when to request permission (after first food log, not on launch), how to avoid notification fatigue (quiet hours, combined notifications), and graceful degradation when permission is denied. This is a 1-cycle feature if we scope it to 3 notification types (protein, supplements, workout gap) and resist adding settings UI beyond a single on/off toggle.

The 491-line sendMessage function is past maintainability threshold but isn't actively blocking work. Defer it until a feature requires touching that code path.

### What We Agreed
1. **Push notifications is the ONLY P0.** No other P0 items this sprint. Ship it in the first 5 cycles.
2. **Exercise instructions via chat as P1** — leverages existing 873-exercise DB, meaningful user value, low risk.
3. **sendMessage decomposition as P2** — do it if time permits after P0/P1 ship.
4. **Food search miss telemetry deferred** — infrastructure, not user-facing. Revisit when food DB becomes the focus again.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Proactive push notifications (protein / supplement / workout) | 4th deferral. #1 product gap. Transforms passive dashboard into active health coach. |
| P1 | Exercise instructions via AI chat | "How do I deadlift?" uses existing exercise DB. Low-risk, high-value AI feature. |
| P1 | Systematic bug hunt | Run analysis across new code paths from last sprint. Quarterly cadence. |
| P2 | sendMessage decomposition | 491-line function needs breaking up. Only if P0/P1 done. |

## Feedback Responses
No feedback received on previous reports (PR #34, PR #36).

## Cost Since Last Review
| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions today | 3 |
| Est. cost today | $162.94 |
| Cost/cycle | $0.12 |

## Open Questions for Leadership
1. **Push notification timing:** Should we prompt for notification permission after first food log, or after 3 days of use? Earlier = more reach, later = more trust.
2. **Notification frequency cap:** Maximum 1 notification per day, or allow up to 3 (one per domain: food, supplements, exercise)? More nudges = more engagement but risks annoyance.
3. **Exercise visual roadmap:** After heatmaps, should we invest in exercise images/GIFs (high storage cost, Boostcamp parity) or lean into AI-powered form tips in chat (unique to us, lower cost)?

---
Comment on any line to steer direction. @ashish-sadh
