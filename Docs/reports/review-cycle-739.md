# Product Review — Cycle 739 (2026-04-12)
Review covering cycles 719–739. Previous review: cycle 719.

## Executive Summary

This sprint shipped the single most impactful infrastructure change since launch: online food search is now available behind a privacy-preserving opt-in toggle, connecting users to 300,000+ USDA foods and the Open Food Facts database when local results are insufficient. The toggle defaults to OFF — maintaining our privacy-first identity — and includes rate limiting and a clear privacy notice. Combined with the previous sprint's proactive alerts and AI workout intelligence, Drift now has both the data depth and proactive coaching that define a serious health app. Next sprint should focus on connecting USDA search to the AI chat pipeline and deepening the proactive health coach pattern.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| P0: USDA API Phase 1 (client + cache + fallback) | Shipped | Opt-in toggle, rate limiting, FoodService.searchWithFallback(), 946 tests |
| P1: Navigate to screen from chat | Not Started | Deprioritized in favor of completing USDA thoroughly |
| P1: More proactive alerts (workout consistency, logging gaps) | Not Started | Next sprint |
| P1: Systematic bug hunting | Not Started | Next sprint |
| P2: IntentClassifier coverage improvement | Not Started | Next sprint |

## What Shipped (user perspective)

- **Online food search (opt-in)** — Can't find quinoa or acai bowl in our database? Enable "Online Food Search" in Settings and Drift searches USDA and Open Food Facts when local results are limited. Results are cached locally — search once, available forever.
- **Privacy-first toggle** — Online search is OFF by default. When enabled, only food search terms leave your device — no personal data, no tracking, no accounts.
- **Rate limiting** — Online searches are throttled (max 1/second, 50/session) to prevent abuse and keep the app responsive.
- **Updated privacy notice** — Settings now clearly explains what data leaves the device and when.
- **AI chat can now search online foods** — When the toggle is on, asking the AI to "log quinoa" will find it online if it's not in the local database.
- **946 automated tests** — 4 new tests covering preference toggle behavior and search fallback.

## Competitive Position

With opt-in access to 300,000+ USDA foods, Drift's food database gap narrowed dramatically — from 1,500 vs MFP's 20M to 300K+ cached-on-demand. The privacy-first approach (opt-in, no PII, local cache) is unique — MFP, Cronometer, and MacroFactor all require cloud accounts. WHOOP is doubling down on AI coaching with conversation memory and contextual guidance; our proactive alerts are the same pattern but fully on-device. MacroFactor launched Workouts with personalized progression — our progressive overload alerts serve a similar need but through AI chat rather than structured programs.

## Designer x Engineer Discussion

### Product Designer

This is a foundational sprint. One item shipped, but it's the right one — closing the food database gap has been our biggest credibility issue since launch. Every "food not found" was a moment where users opened MFP instead. Now, with USDA access behind an opt-in toggle, users who want breadth can have it without compromising our privacy promise.

The toggle UX is clean — globe icon, clear description, privacy note that appears when enabled. I like that previously cached USDA foods appear in local search forever. This is the "offline-first with on-demand enrichment" pattern done right.

What concerns me is that we shipped 1/5 sprint items. The USDA work was necessary and well-scoped, but chat navigation, proactive alerts, and bug hunting all slipped. We need to be honest about sprint sizing — if one P0 takes a full sprint, don't plan four P1s alongside it.

For next sprint, I want to see the proactive alerts extended. We have protein streak and supplement gap alerts. Adding workout consistency ("no workouts in 5+ days") and logging gap ("no food logged in 2+ days") completes the health coach pattern. These are high-visibility, low-complexity features that make users feel the app is watching out for them.

WHOOP's AI Coach now has conversation memory and contextual guidance. We should note this as a long-term competitive pressure — our on-device approach can't easily add persistent memory across sessions, but our proactive alerts serve a similar user need without the privacy cost.

### Principal Engineer

The USDA integration is architecturally significant — it's the first external network call in the app's history. The implementation is conservative and correct: `@MainActor` isolation for rate-limiting state, opt-in preference gating at both the view layer (FoodSearchView) and service layer (FoodService.searchWithFallback), and graceful degradation when offline.

The existing USDA client and OpenFoodFacts integration were already in place from a previous cycle — they were just ungated. This sprint's real contribution was the privacy layer: the preference toggle, the rate limiting, and the FoodService-level fallback that makes online search available to the AI chat pipeline (not just the search view).

946 tests is healthy. The 4 new tests cover the preference toggle default (OFF), toggle behavior, local-only search when disabled, and rate limiting code path. Coverage for this change is appropriate — the network layer itself isn't unit-testable without mocking, and the integration is behind a flag.

Risk: the DEMO_KEY API key has lower rate limits than a registered key. For production, we should register a proper USDA API key. This is low-urgency (the rate limiting handles it) but should be done before App Store launch.

For next sprint, the chat navigation feature ("show me my weight chart") is the most impactful remaining AI parity gap. It requires a navigation tool in the AI pipeline and a way to programmatically switch tabs — both straightforward but need careful state management.

### What We Agreed

1. **More proactive alerts (P0)** — Workout consistency (5+ days no workout) and logging gap (2+ days no food). Complete the health coach pattern.
2. **Navigate to screen from chat (P1)** — "Show me my weight chart" switches tabs. Biggest remaining AI parity gap.
3. **Wire USDA fallback into AI chat food logging (P1)** — When user says "log quinoa" and it's not local, use searchWithFallback if toggle is on.
4. **Systematic bug hunting (P1)** — Focus on USDA integration code paths and proactive alert edge cases.
5. **IntentClassifier coverage (P2)** — Push from 63% toward 80%.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | More proactive alerts (workout consistency, logging gaps) | Complete health coach pattern — 4 alert types → 6 |
| P1 | Navigate to screen from chat | Biggest AI parity gap — chat should reach any screen |
| P1 | Wire USDA into AI chat food logging | searchWithFallback exists but chat pipeline doesn't call it yet |
| P1 | Systematic bug hunting | Every-sprint cadence — focus on new USDA and alert code |
| P2 | IntentClassifier coverage | Only file below 80% threshold |
| P2 | Register production USDA API key | Replace DEMO_KEY before App Store launch |

## Feedback Responses

No feedback received on previous reports (PR #15, Review #21 at cycle 719 — zero comments).

## Open Questions for Leadership

1. **USDA API key registration** — Should we register a production API key now, or is DEMO_KEY acceptable for TestFlight? Registration is free but requires an email address associated with the app.
2. **Proactive alert frequency** — We now show alerts on the dashboard when patterns are detected. Should alerts also push as local notifications, or is dashboard-only sufficient for now?
3. **Sprint sizing** — This sprint shipped 1/5 items (but the one P0 was high-impact). Should we size sprints smaller (3-4 items) to improve completion rate, or is shipping the right P0 more important than completion percentage?
