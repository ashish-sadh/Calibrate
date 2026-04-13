# Product Review — Cycle 1038 (2026-04-13)
Review covering cycles 1014–1038. Previous review: cycle 983 (Review #29).

## Executive Summary
This sprint delivered two architectural wins: ViewModel extraction for the AI chat (cleaner codebase, extensible for new card types) and supplement/sleep confirmation cards (in progress, compiling). The confirmation card pattern now covers all major action types — food, weight, workout, navigation, supplements, and sleep. Competitive landscape shows MacroFactor aggressively expanding into workouts with Live Activity support and AI recipe photo logging, while MFP continues pushing Premium AI logging tools. Our on-device privacy moat holds, but polish gaps remain the main barrier to perceived quality.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| P0: Bug hunting on recent features | Shipped | Misleading workout checkmark + force unwrap fixed |
| P1: AIChatView ViewModel extraction | Shipped | State + logic separated from view rendering |
| P1: Supplement/sleep confirmation cards | In Progress | Card data structs + UI rendering + tool wiring done, testing next |
| P2: Food DB quality | Not Started | Deferred — card work took priority |

## What Shipped (user perspective)
- **Unconfirmed workouts now show a question mark** instead of a misleading green checkmark — clearer feedback before you commit
- **AI chat is more maintainable internally** — ViewModel extraction makes adding new features faster (no user-visible change, but enables everything below)
- **Supplement queries in chat will show a status card** — taken/remaining count at a glance (in progress)
- **Sleep and recovery queries will show a structured card** — sleep hours, HRV, recovery score, readiness in one visual (in progress)
- **Bug fix: rare crash eliminated** in activity duration parsing (force unwrap replaced with safe handling)

## Competitive Position
MacroFactor launched a dedicated Workouts app (Jan 2026) with auto-progression, cardio support, and Apple Health write — they're becoming a serious all-in-one competitor at $72/year. MFP continues pushing Premium AI tools (meal scan, voice log) behind paywall. Our edge remains: free, on-device, privacy-first, all-in-one with AI chat as primary interface. The gap: our exercise vertical is text-only while competitors have videos, progression automation, and Live Activities.

## Designer × Engineer Discussion

### Product Designer
I'm excited about the confirmation card expansion. After Review #29 identified the card pattern as extensible, we're delivering on that promise — supplements and sleep cards complete the "every action gets visual feedback" story. The chat experience is maturing from text-only to a structured messaging interface.

What concerns me: MacroFactor's Workouts app with AI recipe photo logging and Live Activity support raises the bar significantly. Their $72/year bundle (nutrition + workouts) is aggressive pricing for an all-in-one play. We need to match perceived quality even if we can't match feature breadth. The supplement/sleep cards help — users seeing structured data in chat feels more polished than plain text.

The ViewModel extraction was the right call technically, but it's invisible to users. Next sprint needs to be 100% user-visible. The card pattern is proven — extend it to glucose and biomarkers, then focus on exercise visual quality.

### Principal Engineer
The ViewModel extraction was overdue and went cleanly. `AIChatView` dropped from 470+ lines of mixed state/rendering to a thin view struct. The `@Observable` class pattern means all extensions (`+MessageHandling`, `+Suggestions`) target the ViewModel, and closures properly use `[weak self]` capture. This was the last architectural prerequisite before adding more card types.

The `attachToolCards` approach is pragmatic — checking `toolsCalled` after LLM execution and fetching current service data for cards. No changes needed to the tool pipeline or AgentOutput struct. The pattern scales to glucose/biomarkers trivially.

Risk: we now have 6 optional card fields on ChatMessage. If we add 3 more (glucose, biomarkers, body comp), it becomes unwieldy. Consider a `ConfirmationCard` enum with associated values in the next refactor cycle. Not urgent — optional fields work fine for now.

981 tests still passing. The closure capture fix (`[weak self]` in onToken/onStep callbacks) was the only surprise from the struct→class migration.

### What We Agreed
1. **Finish supplement/sleep cards** — test, commit, ship. This is the immediate next action.
2. **Extend cards to glucose and biomarkers** — same pattern, low effort, high visual impact.
3. **Exercise visual quality** — this is our weakest vertical vs competitors. Muscle group icons or simple visual indicators in workout cards. Not full Boostcamp-level video, but better than text-only.
4. **Keep sprints 100% user-visible** — ViewModel extraction was the last pure-architecture sprint item for a while.
5. **Update state.md** — build number, test count, card types are stale.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Finish + test supplement/sleep confirmation cards | Already 90% done — ship it |
| P0 | Glucose + biomarker confirmation cards | Same pattern, completes "every domain gets a card" |
| P1 | Exercise visual polish — muscle group icons on workout cards | Weakest vertical vs competition |
| P1 | Update state.md + TestFlight build 108 | Docs stale since build 107, need a fresh build for testers |
| P2 | Food DB search miss analysis | Every "not found" = user opens competitor app |

## Feedback Responses
No feedback received on previous reports.

## Cost Since Last Review
| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions | 3 |
| Est. cost | $103.38 |
| Cost/cycle | $0.10 |

## Open Questions for Leadership
1. **Exercise visual direction:** Should we invest in muscle group icons/diagrams for workout cards, or focus AI chat intelligence (progressive overload suggestions, form tips)? Both improve the exercise vertical but pull in different directions.
2. **Card consolidation:** With 6+ card types, should we invest in a unified card framework (enum with associated values) or keep the current simple optional-field pattern?
3. **Live Activities:** MacroFactor shipping workout Live Activities raises the bar. Should we prioritize this for the next phase, or stay focused on chat quality?
