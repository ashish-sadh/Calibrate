# Product Review — Cycle 429 (2026-04-12)
Review covering cycles 358–429. Previous review: cycle 358.

## Executive Summary
We shipped the two P0 items from last sprint — voice input and a warmer color palette — plus TestFlight build 105 and a web-based Command Center for leadership to review reports and file bugs. However, 4 of 6 sprint items remain unstarted (chat UI, food DB expansion, meal planning, ViewModel extraction). The majority of cycles went into Command Center infrastructure rather than user-facing product work. We need to refocus hard on chat UI polish and food DB breadth for the next 20 cycles.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| Voice input prototype (P0) | Shipped | Mic button in chat, on-device speech recognition, pulse animation |
| Color harmony (P0) | Shipped | Warmer palette app-wide — navy background, accent-driven cards, domain colors |
| Chat UI — bubbles, typing, tool feedback (P1) | Not Started | Deprioritized for Command Center work |
| Food DB to 1,500 (P1) | Not Started | Still at 1,201 foods |
| Meal planning dialogue (P2) | Not Started | |
| AIChatView ViewModel extraction (P2) | Not Started | Should be done alongside chat UI work |

## What Shipped (user perspective)
- **Voice input in AI chat** — Users can now tap a mic button and speak instead of typing. On-device, no cloud.
- **Refreshed color palette** — Warmer, more cohesive dark theme across every screen. Less "developer project," more "polished app."
- **New TestFlight build (105)** — Latest improvements available to beta testers.
- **Bug fix: natural language meal logging** — "Can you log lunch" now correctly asks what you ate, instead of opening a random food search page.
- **Bug fix: API rate limiting** — Command Center no longer hits GitHub rate limits for authenticated users.
- **Command Center** — Web portal where leadership can read reports, comment on specific sections, and file bugs with screenshots. (Internal tooling, not user-facing.)

## Competitive Position
Our on-device AI chat remains unique — no competitor offers conversational health tracking without cloud dependency. MFP continues to dominate on food DB breadth (14M vs our 1,201) and is integrating AI via acquisitions (Cal AI, ChatGPT Health, Intent). MacroFactor launched a separate Workouts app with Apple Health integration coming. The market is consolidating toward all-in-one platforms, which validates our approach, but we need to move faster on chat UI polish and food coverage to feel competitive in a side-by-side comparison.

## Designer x Engineer Discussion

### Product Designer
I'm encouraged that voice input and color harmony finally shipped — these were overdue and they make a real difference in how the app feels. Voice input is especially important because it's the natural evolution of our chat-first philosophy. Users shouldn't have to type "log breakfast 2 eggs and toast" when they can just say it.

What concerns me is the cycle allocation. We spent a significant number of cycles building the Command Center — a useful internal tool, but invisible to users. Meanwhile, the chat UI still looks like a debug console. Plain text responses with no bubbles, no typing indicator, no visual feedback when the AI is working. This is the first thing users see and it needs to feel polished. Every competitor has chat-style UI as a baseline.

The food DB at 1,201 is still a trust problem. Every time a user searches for something we don't have, they mentally compare us to MFP's 14 million. We won't close that gap, but we need to cover the top 2,000-3,000 most commonly logged foods to stop the bleeding.

### Principal Engineer
The voice input implementation is clean — SpeechRecognizer routes through the existing chat pipeline, which means all existing intent handling, tool calling, and multi-turn flows work with spoken input automatically. No separate pipeline to maintain.

The conversational prefix stripping fix we just shipped for bug #5 exposed a broader pattern: our intent matchers are brittle against natural language variation. The fix (strip "can you", "please", etc.) works, but as the vocabulary of prefixes grows, we should consider a lightweight normalizer that runs before all intent matchers, not just meal logging. This isn't urgent, but it's worth noting as a pattern.

The Command Center was necessary tooling investment, but it consumed more cycles than planned. The architecture is simple (GitHub Pages + Cloudflare Worker for OAuth), so maintenance cost should be low going forward.

Coverage at 24% is stable but not improving. The boy scout rule keeps it from dropping, but we need a focused push to get critical paths above 50%.

### What We Agreed
1. **Zero internal tooling this sprint.** Every cycle goes to user-facing product work.
2. **Chat UI polish is the #1 priority.** Bubbles, typing indicator, and tool execution feedback. This is the most visible quality gap.
3. **Food DB push to 1,500.** JSON-only, zero code risk. Focus on most-searched-but-not-found items.
4. **Voice input needs real-device testing.** Shipped the prototype, now validate with messy spoken input on actual hardware.
5. **Meal planning dialogue (P2)** stays on the board but only if P0/P1 items are done.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Chat UI — message bubbles | Plain text looks unfinished. Most visible quality gap in the app. |
| P0 | Chat UI — typing indicator | Users need feedback that AI is thinking, not frozen. |
| P1 | Chat UI — tool execution feedback | "Looking up food..." during processing builds trust and reduces perceived latency. |
| P1 | Food DB enrichment to 1,500 | Every "not found" sends users to MFP. Cover top Indian, fast food, branded items. |
| P1 | Voice input real-device validation | Prototype works in simulator — test with real spoken input, messy sentences, accents. |
| P2 | Meal planning dialogue | "Plan my meals today" is a top failing query. Needs `awaitingMealPlan` state. |
| P2 | AIChatView ViewModel extraction | Do alongside chat UI bubbles — the refactor enables cleaner state management for new UI. |
| P2 | Intent normalizer | Centralize conversational prefix stripping ("can you", "please") for all intent matchers. |

## Feedback Responses
No feedback received on previous reports.

## Open Questions for Leadership
1. **Voice input go/no-go:** The prototype is built. Should we ship it in the next TestFlight for beta tester feedback, or hold until we've validated with more spoken input patterns?
2. **Command Center adoption:** Is the web portal useful for reviewing reports and filing bugs? Should we invest more here, or is GitHub PR comments sufficient?
3. **Food DB strategy:** Manual curation is slow (1,201 foods in 400+ cycles). Should we prioritize a USDA API integration to accelerate coverage, even though it adds a network dependency for the import step?

---
Comment on any line for strategic feedback. @ashish-sadh
