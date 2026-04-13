# Product Review — Cycle 806 (2026-04-12)
Review covering cycles 785–806. Previous review: cycle 785 (Review #23).

## Executive Summary

Chat navigation shipped — users can now say "show me my weight chart" or "go to food tab" and the app switches screens. This closes the biggest remaining gap in the AI-first experience: every major interaction is now reachable through conversation. The sprint is on track with 1 of 4 items shipped; USDA chat integration and bug hunting are next.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| P0: Chat navigation | Shipped | Static overrides + LLM tool + tab switching + 16 tests |
| P1: Wire USDA into AI chat | Not Started | Next up |
| P1: Systematic bug hunting | Not Started | Planned |
| P2: IntentClassifier coverage | Not Started | Planned |

## What Shipped (user perspective)
- **"Show me my weight chart" switches tabs** — Say it in chat, app navigates there
- **Navigate to any screen via chat** — Dashboard, Weight, Food, Exercise, Supplements, Glucose, Biomarkers, Settings
- **Multiple phrasing styles work** — "go to", "show me", "open", "switch to", "take me to", "navigate to"
- **Chat collapses on navigation** — So you see the screen you asked for, not the chat overlay
- **AI understands navigation intent** — Even natural variations like "show me my food diary" or "open the gym tab"
- **962 tests** (+16 navigation tests)

## Competitive Position

No competitor offers on-device AI chat that navigates you to app screens. MFP, Whoop, and Strong all require manual tab navigation. This reinforces our AI-first differentiator. The remaining gap is food DB breadth (1,500 local + USDA opt-in vs MFP's 20M) and exercise content (text-only vs Boostcamp's videos).

## Designer × Engineer Discussion

### Product Designer

Chat navigation is the feature that makes the AI-first promise real. Before this, a user could log food, check calories, plan meals, and ask about workouts through chat — but then had to manually tap a tab to view their weight chart. That friction broke the conversational flow. Now the entire app is accessible through one interface.

The static override approach is smart: common phrases like "show me my weight chart" resolve instantly without hitting the LLM, while unusual phrasings like "take me to my supplement tracker" route through the intent classifier. Users get instant response for the 80% case and intelligent handling for the rest.

What I want next is to wire USDA into the chat food logging flow. The API exists behind a toggle, but when a user says "log quinoa" and it's not in our local DB, the chat should search USDA automatically. This is the single biggest daily-use improvement we can make.

### Principal Engineer

The implementation is clean. NotificationCenter for tab switching between the chat overlay and ContentView is the right choice — it's a one-way signal that doesn't need reactive binding or state sharing. The `openBarcodeScanner` fix cleaned up a pre-existing hack where barcode scanning misused `.navigate(tab: 0)` as a placeholder.

The layered approach (StaticOverrides for deterministic matches, `navigate_to` tool in ToolRegistry for LLM-driven matches) follows the same tier pattern as food logging. The tool is registered with the full screen vocabulary so the LLM can resolve synonyms ("gym" → Exercise, "diary" → Food).

One note: the `ToolAction` enum now has 6 cases. Any exhaustive switch on it requires handling all cases. The compiler enforces this, so there's no risk of missed callsites, but the pattern should be monitored as we add more UI actions.

### What We Agreed
1. **Wire USDA into chat food logging** — The P0 for this mini-sprint. Quick integration since the API layer exists.
2. **Systematic bug hunting** — Run analysis on USDA integration, proactive alerts, and navigation code paths.
3. **IntentClassifier coverage** — Push toward 80% with deterministic test cases for known intents including navigation.
4. **Update sprint.md** — Mark chat navigation as shipped.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Wire USDA into AI chat food logging | API exists but chat doesn't use it — biggest daily-use improvement |
| P1 | Systematic bug hunting on new code paths | Navigation, USDA, alerts all need analysis |
| P1 | IntentClassifier coverage toward 80% | Only file below threshold, navigation intents added |
| P2 | Update help text and suggestion pills for navigation | Users should discover they can navigate via chat |

## Feedback Responses

No feedback received on previous reports (Review #23, PR #18 — 0 comments).

## Open Questions for Leadership
1. **Should we add navigation hints to the chat suggestion pills?** E.g., "Show weight chart" as a pill when user opens chat. This would increase discoverability but adds visual clutter.
2. **Is the 4-item sprint scope working?** We shipped 1/4 quickly (P0 done in one cycle). Should we keep this pace or add items now that capacity is clear?
