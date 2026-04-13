# Product Review — Cycle 670 (2026-04-12)
Review covering cycles 650–670. Previous review: cycle 650.

## Executive Summary

This sprint delivered both P0 items: a comprehensive weight unit audit (7 files fixed) and progressive overload alerts in workout history. The exercise vertical — our weakest area vs MacroFactor/Strong — now actively coaches users when they're stalling. The unit audit permanently closes a systemic bug pattern that's been recurring since Review #12. Next sprint should continue strengthening exercise features and begin the USDA API design.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| P0: Progressive overload alerts | Shipped | Stalling/declining exercises shown in workout tab with weight suggestions |
| P0: Hardcoded unit audit | Shipped | 7 files fixed — ExerciseBrowser, ExercisePicker, TemplatePreview, WorkoutDetail, ExerciseService, DEXAOverview |
| P1: AI chat workout intelligence | Not Started | Deferred — P0s took priority |
| P1: USDA API design doc | Not Started | Deferred — P0s took priority |
| P1: Systematic bug hunting | Not Started | No bugs found; zero open issues |
| P2: Exercise presentation (icons) | Not Started | Deferred |
| P2: Coverage maintenance | Ongoing | 936 tests, boy scout rule active |

## What Shipped (user perspective)

- **Progressive overload alerts** — The Exercise tab now shows a "Progressive Overload" card highlighting exercises where you've been stuck at the same weight. Includes a specific suggestion like "Same weight for 4 sessions — try 142 kg."
- **Weight units work everywhere** — If you use kg, every screen now shows kg: exercise PR displays, workout detail volumes, template previews, exercise picker history, share text, progressive overload trends, and DEXA body composition forms.
- **936 automated tests** — No new tests this sprint, but all existing tests continue to pass.

## Competitive Position

Our exercise vertical has meaningfully improved with progressive overload alerts — we now actively coach users when they're stalling, which neither Strong nor Boostcamp does proactively. MacroFactor's Workouts app has progressive overload automation built into their programming, but ours surfaces insights without requiring users to follow a specific program. Our privacy-first, on-device approach remains a unique differentiator as competitors continue building cloud AI moats.

## Designer × Engineer Discussion

### Product Designer

The progressive overload card is exactly the kind of proactive intelligence that differentiates us. Users don't have to go looking for insights — the app tells them when something needs attention. This is the pattern I want to see replicated across domains: "you haven't logged supplements in 3 days," "your protein has been below target all week," "your weight trend reversed."

That said, two P0s in 20 cycles is modest velocity. We shipped high-quality work, but the P1 items (AI workout intelligence, USDA design doc) didn't get touched. For next sprint, I'd like to see the AI chat workout intelligence shipped — it's low effort since the progressive overload service already exists, and asking "how's my bench?" in chat is a natural user behavior we should support.

The exercise presentation gap (text-only, no images) remains our biggest visual weakness. I'd rather invest in AI-powered workout intelligence in chat than static exercise images — it's more aligned with our AI-first identity and cheaper to implement.

### Principal Engineer

The hardcoded unit audit was the right call as a P0. This was a systemic pattern — the same "stale preference" bug class from Review #12, just in different files. The audit found 7 instances across views and services. The pattern is now documented and closed: all weight display paths go through `Preferences.weightUnit.convertFromLbs()`.

The progressive overload implementation is clean — it reuses the existing `ExerciseService.getProgressiveOverload()` without any new infrastructure. The card checks the last 10 workouts' exercises, queries overload status for each, and filters to stalling/declining. One concern: if a user has many exercises, this could do 20+ database queries on tab load. For now this is fine (SQLite queries are fast), but worth monitoring if we add more overload features.

For next sprint, the AI chat workout intelligence is the ideal task — it connects existing infrastructure (progressive overload service) to the chat pipeline. The USDA design doc should also be prioritized since it requires thinking, not coding, and blocks future food DB work.

### What We Agreed

1. **AI chat workout intelligence (P0)** — "How's my bench progress?" should return trend data from the overload service. Connect existing service to chat.
2. **USDA API design doc (P0)** — Write the design (caching, offline, privacy) so food DB investment can begin next sprint.
3. **Proactive insight pattern (P1)** — Extend the overload alert pattern to other domains: protein adherence alerts, supplement streak nudges.
4. **Systematic bug hunting (P1)** — Run analysis agent across pipeline files. Maintain quarterly cadence.
5. **Exercise presentation (P2)** — Muscle group icons on workout cards if time permits.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | AI chat workout intelligence ("how's my bench?") | Connects existing overload service to chat — low effort, high value |
| P0 | USDA API design document | First external API — needs architecture design before code |
| P1 | Proactive insight alerts (protein, supplements) | Extend overload alert pattern to other health domains |
| P1 | Systematic bug hunting (every 5 cycles) | Quarterly analysis cadence — last found 4 silent bugs |
| P2 | Exercise presentation (muscle group icons) | Visual polish, moves toward Boostcamp parity |
| P2 | Coverage maintenance via boy scout rule | 936 tests, maintain quality organically |

## Feedback Responses

No feedback received on previous reports (PR #11, Review #18 at cycle 650 — zero comments).

## Open Questions for Leadership

1. **Proactive insight strategy** — Should we invest in a generalized "proactive alerts" system (protein targets, supplement streaks, workout consistency) or keep insights domain-specific and manually implemented?
2. **Exercise content direction** — AI-powered workout intelligence in chat vs. static exercise images/videos? Our AI-first identity suggests the former, but visual content has higher perceived value.
3. **USDA API timeline** — Is this quarter the right time for our first external network call, or should we maximize on-device features first?
