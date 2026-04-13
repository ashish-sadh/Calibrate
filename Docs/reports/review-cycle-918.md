# Product Review — Cycle 918 (2026-04-13)
Review covering cycles 869–918. Previous review: cycle 869.

## Executive Summary

After three consecutive zero-feature reviews, the autopilot broke through with two significant deliveries: workout split builder ("build me a PPL split") and a voice input UX overhaul that eliminates the "eaten words" problem. TestFlight build 107 shipped these to testers. The review loop itself was the bottleneck — suspending it until features shipped was the right call. Next sprint focuses on chat UI polish, bug hunting, and food DB quality.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| P0: Workout split builder | Shipped | Multi-turn "build me a PPL split" — 4 split types, exercise suggestions, template saving |
| P1: Rich confirmation cards | Not Started | Displaced by voice UX fix (higher user impact) |
| P1: Systematic bug hunting | Not Started | To be picked up next sprint |
| P2: Food DB enrichment | Not Started | Deferred — USDA integration covers the immediate gap |

## What Shipped (user perspective)

- **"Build me a workout split"** — Users can now say "build me a PPL split" in chat and design a multi-day workout program through conversation. Supports push/pull/legs, upper/lower, full body, and bro splits. The app suggests exercises, users pick or skip, and the result saves as reusable templates.
- **Voice input that actually works** — Fixed a bug where the app was "eating" words during voice input. Speech-to-text now captures everything you say without dropping syllables or cutting off mid-sentence.
- **TestFlight build 107** — Both features shipped to testers with the voice UX overhaul as the headline improvement.

## Competitive Position

Drift now has two sticky multi-turn dialogue features (meal planning + workout split building) that work entirely on-device — no competitor offers this without cloud dependency. Whoop's new AI Coach (OpenAI-powered) does similar workout building but requires sending data to OpenAI's servers. MFP acquired Cal AI for photo-based logging and integrated with ChatGPT Health, doubling down on cloud AI. MacroFactor launched a full Workouts app ($72/yr bundle), entering the exercise space. Our moat remains privacy + on-device intelligence, but the gap in food DB (1,500 vs 20M) and exercise presentation (text-only vs videos) is widening.

## Designer × Engineer Discussion

### Product Designer

I'm genuinely excited that the review suspension worked. Three reviews with zero output was embarrassing — and the moment we stopped self-auditing, two features shipped. That's a lesson about process serving product, not the reverse.

The workout split builder is the second multi-turn dialogue feature (after meal planning) and it proves the pattern: conversational design sessions drive daily engagement. Users don't just log — they plan. This is what separates us from data loggers.

What concerns me: the competitive landscape moved fast this quarter. Whoop now has AI-powered workout building with photo parsing. MFP has ChatGPT integration and a 20M food database. Boostcamp added muscle engagement visualization. We're competing on privacy, but privacy alone doesn't win if the experience gap is too wide.

The voice fix was the right call over confirmation cards — users who tried voice input and had words eaten would never try it again. First impressions matter more than UI polish on secondary flows.

Next 20 cycles should focus on the experience gaps that make users switch to competitors: chat confirmation cards (every action should feel acknowledged), and a systematic bug hunt to catch silent issues before testers report them.

### Principal Engineer

The workout split builder reused `ConversationState.Phase` exactly as predicted — added `planningWorkout` phase, followed meal planning's state machine transitions. Minimal new infrastructure, maximum feature output. This validates the architecture investment from earlier sprints.

The voice UX fix is more interesting than it sounds. The bug was in how `SpeechRecognizer` handled partial vs final transcription results — the app was submitting partial results as final, causing word loss. The fix required understanding the AVFoundation speech pipeline, not just our code. Hardware-dependent bugs like this are invisible in simulator testing.

Technical health is good: 981 tests, zero open bugs, zero open issues. The codebase is clean enough that features ship without fighting debt. The boy scout rule is working — code quality improves organically alongside feature work.

Risk assessment: AIChatView is still the largest file and will need ViewModel extraction as we add more conversation phases. Not urgent, but the next complex chat feature (confirmation cards across all action types) will likely force it. Plan for it, don't fight it.

### What We Agreed

1. **Review cadence permanently changed** — milestone-based (every 2 features shipped), not commit-based. No more self-reinforcing review loops.
2. **Next sprint: 4 items max** — proven scope that achieves 75%+ completion.
3. **Chat UI polish is the top priority** — rich confirmation cards for all actions. This is the biggest perceived-quality gap.
4. **Bug hunting every sprint** — systematic analysis agent on new code paths. Found real bugs every time we've done it.
5. **Voice input needs real-device testing ritual** — simulator doesn't catch audio bugs. Test on hardware after every voice-related change.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Rich confirmation cards for all chat actions | Biggest perceived-quality gap — actions feel unacknowledged without structured feedback |
| P1 | Systematic bug hunting on recent features | Workout split builder + voice UX are new code — find issues before testers do |
| P1 | AIChatView ViewModel extraction | Confirmation cards will add complexity — extract now to keep the file manageable |
| P2 | Food DB: search miss analysis + targeted additions | Every "not found" = user opens MFP. Fix the most common misses first |

## Feedback Responses

No feedback received on previous reports (PR #22, Review #27).

## Cost Since Last Review
| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions | 1 |
| Est. cost | $5.94 |
| Cost/cycle | $0.01 |

## Open Questions for Leadership

1. **Voice input testing protocol** — Should we invest in an automated real-device test rig, or is manual hardware testing after voice changes sufficient? Audio bugs are invisible in simulator.
2. **Food DB strategy** — USDA API is live behind opt-in toggle. Should we push users toward enabling it (default ON with privacy notice), or keep it hidden until the local DB is larger? The 1,500 vs 20M gap is our biggest competitive weakness.
3. **Review cadence** — We're switching to milestone-based reviews (every 2 features). Does leadership want to maintain a minimum time floor (e.g., no more than one review per week) to prevent review fatigue?
