# Product Review — Cycle 983 (2026-04-13)
Review covering cycles 941–983. Previous review: cycle 941 (Review #28).

## Executive Summary

Rich confirmation cards shipped — navigation, weight, workout, and food actions all now show structured visual cards in chat instead of plain text. This completes the P0 from last sprint and is the last piece of the "AI chat feels like a real messaging app" story. The fitness app market is consolidating around all-in-one platforms (MacroFactor added Workouts, MFP added AI), validating our direction. Next focus: bug hunting on recent features, ViewModel extraction to keep AIChatView manageable, and food DB quality.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| Rich confirmation cards (P0) | Shipped | Navigation cards (new), activity preview cards (new), weight/workout cards (already existed). All chat actions now have structured visual feedback. |
| Bug hunting on recent features (P1) | Not Started | Deferred while confirmation cards were built. Next sprint priority. |
| AIChatView ViewModel extraction (P1) | Not Started | NavigationCardData added cleanly without extraction — still viable but not yet blocking. |
| Food DB search miss analysis (P2) | Not Started | Deferred. |

## What Shipped (user perspective)

- **Navigation shows a card** — When you say "show me my weight chart" or "go to food tab," you now see a visual card with the destination icon and name, not just plain text.
- **Activity logging shows a preview** — When you say "I did yoga for 30 min," you see a workout card immediately at the confirmation step, not just after saying "yes."
- **Fixed a test compilation bug** — SpeechRecognition tests were broken (referencing a renamed method). Fixed as part of boy scout cleanup.
- **Voice UX overhaul shipped last sprint** — Eaten-words bug fixed, Build 107 on TestFlight (from cycles before this review window).
- **Workout split builder shipped last sprint** — "Build me a PPL split" multi-turn dialogue (from cycles before this review window).

## Competitive Position

The market is fragmenting into 3-app stacks (nutrition + recovery + workout) that don't talk to each other. MacroFactor launched a separate Workouts app (Jan 2026) rather than integrating into their nutrition app — validating that all-in-one is hard. MFP's free tier continues to shrink. Our edge: single app, on-device privacy, AI chat that handles nutrition + exercise + health in one conversation. Our gap: food DB (1,500 vs MFP's 14M), no exercise visuals (Boostcamp has expert videos and muscle diagrams).

## Designer x Engineer Discussion

### Product Designer

I'm pleased with where confirmation cards landed. Every major chat action — food, weight, workout, navigation — now has structured visual feedback. This is what separates "prototype chat" from "product chat." The card pattern is extensible: supplements, sleep, glucose could all get cards later.

What concerns me is that we've shipped one sprint item out of four. The confirmation cards were the right P0, but the pattern of P1/P2 items never getting touched persists. The market isn't waiting — MacroFactor Workouts launched with personalized progression and auto-periodization. Boostcamp still has the best exercise content library. We need to move faster on the exercise vertical.

The all-in-one market positioning is being validated externally. A 2026 fitness app roundup called out that "most serious fitness people are running three apps that don't talk to each other." That's exactly our pitch. But we need polish to match — the chat cards help, but food DB depth and exercise presentation remain the two biggest trust gaps.

### Principal Engineer

The NavigationCardData addition was clean — one struct, one view, two wiring points. The card pattern (optional card fields on ChatMessage) scales well. I'm not concerned about AIChatView complexity from this change specifically, but the file is accumulating optional card fields. If we add supplement/sleep/glucose cards, ViewModel extraction will become necessary.

The pre-existing SpeechRecognition test failure (referencing `stopRecording` after the method was renamed to `forceStop`) is a process gap. Method renames should catch all callsites — the compiler would have caught this if the test target was part of the main build. Worth adding a CI step that builds the test target even when tests aren't run.

Cost efficiency is excellent at $0.06/cycle. The cache read ratio (20.7M cache reads vs 1.3M cache writes) shows the prompt cache is working well for iterative development.

### What We Agreed

1. **Bug hunting is the next P0.** Recent features (workout split builder, voice UX, confirmation cards) need systematic analysis before more features are added. Fix silent issues before users find them.
2. **ViewModel extraction moves to P1.** AIChatView now has 4 card types and will need 2-3 more. Extract before the next card type is added.
3. **Food DB quality over quantity.** Don't add foods blindly — analyze search misses, cross-reference with USDA, fix the most-searched missing items.
4. **Sprint scope stays at 4 items.** The persistent P1/P2 slip pattern means we should only commit to what we'll actually ship.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Systematic bug hunting — workout split builder, voice UX, confirmation cards | Three features shipped recently with no systematic analysis. Find issues before testers do. |
| P1 | AIChatView ViewModel extraction | 4 card types, voice state, conversation state — file is at the complexity threshold. Extract before adding more. |
| P1 | Supplement/sleep confirmation cards | Extend the card pattern to remaining action types. Do this after ViewModel extraction. |
| P2 | Food DB search miss analysis + targeted additions | Every "not found" sends users to MFP. Identify top missing foods by search frequency. |

## Feedback Responses

No feedback received on previous reports.

## Cost Since Last Review
| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions | 3 |
| Est. cost | $56.15 |
| Cost/cycle | $0.06 |

## Open Questions for Leadership

1. **Exercise presentation investment:** Boostcamp has expert videos and muscle diagrams for every exercise. We have 873 exercises but text-only. Should we invest in static exercise images/illustrations, or lean harder into AI-powered workout intelligence (chat-based form tips, progressive overload coaching) as our differentiator?
2. **Food DB strategy:** At 1,500 foods vs MFP's 14M, we can't compete on breadth. USDA API is integrated but behind an opt-in toggle (privacy concern — queries leave device). Should we make USDA search default-ON for new users, or keep the privacy-first default and invest in expanding the local DB?
3. **App Store timeline:** We're on TestFlight with a small group. What milestones need to be hit before considering a public App Store launch? Is it food DB depth, test coverage, feature completeness, or something else?
