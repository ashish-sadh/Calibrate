# Product Review — Cycle 1289 (2026-04-13)
Review covering cycles 1248–1289. Previous review: cycle 1248 (Review #34).

## Executive Summary

Two items shipped since the last review: AI intent detection coverage hit 99% (the highest of any file in the codebase), and the Muscle Recovery card on the Exercise tab now shows weekly set counts per muscle group — giving users a "how much did I train this" view alongside "how long ago." The review cycle hook triggered twice in quick succession due to the known commit-based counter design flaw; addressed by pre-writing the counter. Next 20 cycles focus on proactive push notifications (the biggest UX leap available: passive dashboard alerts → active health coach nudges) and decomposing the AI chat core to keep it maintainable as we add features.

## Scorecard

| Goal | Status | Notes |
|------|--------|-------|
| Muscle group heatmap (P0) | In Progress | BodyMapView now shows weekly set counts per muscle group; visual heatmap intensity TBD |
| Proactive push notifications (P0) | Not Started | Highest-impact item remaining |
| AIChatView.sendMessage decomp (P1) | Not Started | 491-line function blocking future AI work |
| Food search miss telemetry (P1) | Not Started | Blind spot — we can't improve what we can't measure |
| Exercise instructions via chat (P2) | Not Started | "How do I deadlift?" still returns generic LLM response |
| IntentClassifier coverage (carry-over) | Shipped | 63% → 99%. Best-covered file in the codebase. |

## What Shipped (user perspective)

- **Muscle Recovery card shows weekly sets** — Each muscle group now displays how many sets you hit in the past 7 days, not just how many days since you last trained. "16 sets" vs "3d ago" gives volume context at a glance.
- **AI chat understands intent more reliably** — Under-the-hood improvements mean the AI makes fewer wrong guesses when you type naturally. Fixes a persistent edge-case class that affected conversational logging.
- **All 981 tests still passing** — New features landed without breaking anything already working.

## Competitive Position

MFP and MacroFactor both shipped AI photo logging in 2026, making it table stakes — but cloud-dependent and weak on non-Western cuisines. Whoop's new Behavior Trends feature (habits → Recovery correlation) mirrors our dashboard insights pattern, but requires a $30/month hardware subscription. Our full feature set — voice, AI chat, meal planning, workout split design, proactive alerts — is free and entirely on-device, which is a genuine differentiator as competitors move deeper behind paywalls. The gap to close: Boostcamp and Strong both have muscle group heatmaps now; ours is partially done and must ship this sprint.

## Designer × Engineer Discussion

### Product Designer

I'm pleased the set-count data is now surfacing on the Muscle Recovery card — that's the "how much did I train" context users actually need, not just "how long ago." But the visual still feels passive. What I want is intensity: a cell that *looks* heavier when you've done 20 sets of chest this week vs. 2. The recovery color is based on recency; the set count is now displayed as text. The next step is tying the two together — opacity or fill based on volume.

On the competitive side, I'm watching Whoop's Behavior Trends closely. After 5+ logged entries, it starts showing you patterns like "when you sleep under 7 hours, your calories run 400 over." We have the data to do exactly this. Our dashboard insights are today hardcoded; the path to Whoop-level intelligence is making them dynamic and cross-domain. That's Phase 5 work — but we should keep it in view.

Sprint priority is clear: push notifications first. The dashboard alerts are invisible to someone who doesn't open the app. A 6pm "You've missed protein 3 days in a row" notification is what makes Drift feel like a coach, not a logger.

### Principal Engineer

The IntentClassifier result validates the "test deterministic wrappers, not stochastic code" pattern. We extracted pure functions and coverage went from 63% (a 4-review-old accepted ceiling) to 99% in one sprint. This pattern should be the default for any future ML-adjacent code.

The review hook double-firing is a design issue, not a product one — commit-based triggers count review commits toward the next trigger. We've noted it across four reviews now. The cleanest fix is to only count `.swift` file commits toward the cycle counter. I'll flag this as a hygiene item.

BodyMapView is clean — the weekly set count enhancement is ~20 lines touching one view file. No architectural concerns. For the visual intensity enhancement the designer wants, I'd recommend adding a `volumeIntensity(for:)` computed property in the view (sets/week normalized 0–1 against the max across all groups). Keeps the data logic in the view since it's presentation-only.

Push notifications are the right next P0. UserNotifications is well-understood framework, no new infrastructure needed. The only risk is permission prompt timing — one wrong prompt timing = permission denied forever on iOS. Recommend prompting after the second food log, not the first, to ensure user has committed to using the app.

### What We Agreed

1. **Ship push notifications this sprint** — three signals (protein, supplements, workout gap), prompt after second food log, 6pm daily, quiet hours 9pm–8am
2. **Enhance muscle intensity visuals** — after set counts are committed, add opacity/fill tying volume to cell appearance
3. **Fix review hook** — count only `.swift` commits toward cycle counter (owner decision needed)
4. **sendMessage decomposition is next after notifications** — 491 lines is past the threshold; every AI feature added now makes it worse

## Sprint Plan (next 20 cycles)

| Priority | Item | Why |
|----------|------|-----|
| P0 | Proactive push notifications | Passive alerts → active health coach. Highest UX impact available. |
| P0 | Muscle heatmap intensity visuals | Set counts show; opacity/fill on volume makes it a real heatmap |
| P1 | AIChatView.sendMessage decomp | 491 lines blocks every future AI feature. Pay the debt now. |
| P1 | Food search miss telemetry | We're blind to what users can't find. 10-line fix, permanent data signal. |
| P2 | Exercise instructions via chat | "How do I deadlift?" should work. Data exists, routing is the work. |

## Feedback Responses

No feedback received on PR #33 (Review #34).

## Cost Since Last Review

| Metric | Value |
|--------|-------|
| Model | Opus / Sonnet mix |
| Sessions | 3 |
| Est. cost | $162.94 |
| Cost/cycle | $0.13 |
| Cache read ratio | 94% |

## Open Questions for Leadership

1. **Review hook cadence**: The commit-based cycle counter causes reviews to fire on review commits themselves, creating loops. Should we filter to only `.swift` file commits, or switch to a time-based trigger (e.g., every 24 hours of active session)?
2. **Push notification aggressiveness**: Three daily signals (protein, supplements, workout gap) — should we ship all three at once, or start with one (protein) to calibrate the feel before adding more?
3. **Muscle heatmap visual style**: Intensity through opacity (subtle) vs. color saturation (bold) vs. a bar/fill inside each cell (structural). Which direction matches the app's aesthetic?
