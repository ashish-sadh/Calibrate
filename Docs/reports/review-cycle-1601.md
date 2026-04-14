# Product Review — Cycle 1601 (2026-04-14)
Review covering cycles 1570–1601. Previous review: cycle 1483 (Review #37).

## Executive Summary

This sprint fixed two user-visible bugs (recovery score mismatch and overwhelming progressive overload list) and refreshed product documentation. 60% sprint completion (3/5 items). All Phase 3c "Now" roadmap items remain complete — the product is at a natural inflection point between deepening polish and expanding to new surfaces. TestFlight build 114 failed to archive this cycle (compilation timeout); resolving this is the top priority.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| Fix recovery score mismatch (#41) | Shipped | Dashboard and detail page now show consistent recovery scores |
| Fix progressive overload list overflow (#42) | Shipped | Capped to top 5 exercises with "Show more" expand |
| State.md refresh | Shipped | Updated build number, test count, food count to current reality |
| Systematic bug hunt | Not Started | Displaced by sprint plan sync and Command Center fixes |
| Progressive overload UI polish | Not Started | Depended on #42 shipping; deferred |

## What Shipped (user perspective)
- **Recovery score now consistent** — Dashboard and Body Rhythm page show the same recovery number (was showing different values before)
- **Progressive overload section is cleaner** — Exercise tab now shows top 5 stalling exercises instead of 14+, with a "Show more" option to see all
- **Command Center reliability** — Fixed broken JavaScript that prevented the web dashboard from loading
- **Barcode scanning accuracy** — Fixed calorie calculation for multi-piece food servings via barcode

## Competitive Position

MacroFactor launched Workouts as a standalone app with auto-progression and Apple Health write coming, priced at $72/year bundled. MFP continues stripping its free tier while maintaining a 14M food database. The market insight remains: "most serious fitness people run three apps that don't talk to each other." Drift's all-in-one + free + private positioning is strong, but we need to start expanding surfaces (widgets, Watch) to match the convenience of dedicated apps.

## Designer × Engineer Discussion

### Product Designer

I'm pleased that the two user-facing bugs shipped quickly — consistent recovery scores and a less overwhelming progressive overload list are the kind of reliability improvements that build trust. But I'm concerned about velocity: 3/5 items shipped, and neither the bug hunt nor the UI polish landed. We've been in Phase 3c for a long time now and all "Now" items are done.

The competitive landscape is shifting. MacroFactor Workouts with auto-progression is exactly the all-in-one play we're making, but at $72/year with professional content (Jeff Nippard integration via Boostcamp). MFP is gating more features behind Premium+. Our free + private moat is real, but invisible to users who haven't tried us yet.

I think the next sprint should be about expanding Drift's surface area. iOS widgets (calories remaining, recovery score on the home screen) would make Drift visible throughout the day without opening the app. This is the difference between "a thing I open to log" and "a thing that's always with me." Whoop's lock screen complications are a big part of their stickiness.

### Principal Engineer

The TestFlight archive failing this cycle is concerning — it timed out during compilation, not a build error. This suggests the project is hitting a complexity threshold for the build system or the machine's resources during archive builds. This needs investigation before it becomes a recurring blocker.

On the codebase: `sendMessage` at 491 lines has been flagged since Review #34. Every AI feature addition makes it harder to decompose later. I'd like to see this addressed in the next sprint — not as standalone refactoring, but paired with a feature that touches chat.

The test suite at 996+ is healthy. No open bugs, no open issues — clean operational state. The architecture (tiered AI pipeline, ConversationState FSM, attachToolCards pattern) is sound and extensible. We're in good shape to expand to new surfaces without accumulating debt.

For widgets: WidgetKit + App Groups is the right approach. Data sharing between main app and widget extension via shared UserDefaults or GRDB read-only access. Low architectural risk, high user-visibility.

### What We Agreed
1. **Fix TestFlight build pipeline** — Must publish build 114 this sprint. Investigate archive timeout.
2. **sendMessage decomposition** — Break the 491-line function into focused handlers. Pair with any chat feature.
3. **iOS widget prototype** — Calories remaining + recovery score. Phase 4 begins.
4. **Systematic bug hunt** — Carried twice, must ship. Focus on notification edge cases and recent AI changes.
5. **Keep sprint scope to 4-5 items max** — The 4-item sprint formula works.

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | TestFlight build 114 — debug archive timeout | Users can't get latest fixes without a working build pipeline |
| P0 | sendMessage decomposition (491→focused handlers) | Maintainability gate — every AI feature makes it worse |
| P1 | Systematic bug hunt (notifications, AI edge cases) | Carried twice; proactive quality keeps trust high |
| P1 | iOS widget exploration (calories remaining, recovery) | Phase 4 surface expansion — makes Drift visible all day |
| P2 | Food search miss analysis | Data-driven food DB improvement; every "not found" = user opens competitor |

## Feedback Responses
No feedback received on previous report (PR #43, Review #37/Cycle 1550). PR had zero comments.

## Cost Since Last Review
| Metric | Value |
|--------|-------|
| Model | Opus |
| Sessions | New session (no prior data today) |
| Est. cost | N/A (first session of cycle) |
| Cost/cycle | ~$0.06 (historical average) |

## Open Questions for Leadership
1. **Phase 4 timing:** Should we commit to iOS widgets as the next user-visible feature, or is there deeper Phase 3c polish work you'd like to see first?
2. **TestFlight cadence:** Archive builds are timing out — should we invest in build optimization (incremental builds, module splitting) or is this a machine-specific issue to debug?
3. **Food DB strategy:** Manual enrichment (1,520 foods) vs. deeper USDA API integration vs. accepting chat-first logging covers the gap. Which direction should we invest in?
