# Product Review — Cycle 291 (2026-04-12)

## What Happened (Cycles 199–291)

All 6 items from the cycle 199 sprint plan were completed:

| # | Item | Status | Commits |
|---|------|--------|---------|
| 1 | Coverage sprint (P0) | DONE | 886 tests (+143), AIToolAgent/IntentClassifier/AIRuleEngine/FoodService all expanded |
| 2 | UI theme overhaul (P0) | DONE | Premium dark refresh via Theme.swift, propagated to all 46 views |
| 3 | State machine refactor (P1) | DONE | ConversationState.Phase enum replaces 5 scattered pending vars |
| 4 | Food DB enrichment (P1) | DONE | 34 new foods (1041→1075): seafood, Asian, Mediterranean, soups, breakfast |
| 5 | Dashboard redesign (P1) | DONE | Apple Fitness-style macro rings, section headers, ring legend |
| 6 | Behavior insights v2 (P2) | DONE | 4th insight (sleep vs calories), protein window 14→30 days |

**Bonus:** Adaptive TDEE reverted (was dropping calories dangerously 1960→1400). TestFlight build 104 published.

**Key metric:** 6/6 sprint items completed. First sprint with 100% completion rate.

---

## Product Designer Assessment

### Strengths
1. **Macro rings are a real differentiator.** Apple Fitness-style concentric rings on the dashboard give instant visual progress. No competitor in the on-device space has this.
2. **Theme overhaul landed.** After 29 cycles of being "overdue," the premium dark refresh shipped in one cycle. Deep navy background, accent-driven cards, consistent Typography — it looks like a real app now.
3. **Behavior insights expanding well.** Sleep vs calories is the kind of cross-domain insight that Whoop charges $30/month for. We have 4 insights for free, on-device.
4. **State machine refactor was invisible to users but critical.** No more impossible states (meal AND workout pending simultaneously).

### Gaps
1. **Chat UI is still plain text.** No markdown rendering, no structured cards for food/workout results. When you ask "daily summary" and get a text wall, it feels 2020-era. Competitors are moving to rich cards.
2. **Food DB at 1,075 is still tiny.** Missing major soft drinks (Coke, Pepsi), common breads, and Thai/Japanese staples. Every "not found" in food search erodes trust.
3. **No voice input.** We've been talking about SpeechRecognizer for 3 reviews. It's the #1 accessibility and convenience gap.
4. **Exercise is text-only.** 873 exercises with zero visual aids. Boostcamp sets the bar here.
5. **Onboarding doesn't exist.** New TestFlight users land on dashboard with no data and no guidance.

### Competitive Notes (from persona knowledge)
- MFP's Cal AI acquisition means photo food scanning is becoming mainstream. Our on-device constraint makes this hard, but voice input is our answer.
- Whoop's AI Strength Trainer (text→workout plan) validates our AI-first approach but they're cloud-based.
- Strong remains focused and clean — a good reminder that polish > features.

### Proposed Direction
Focus on **user experience polish and food DB depth**. The architecture is solid. The AI pipeline works. Now make it feel premium:
1. Food DB to 1,200+ (soft drinks, breads, Thai/Japanese, more Indian proteins)
2. Chat UI cards for food results and summaries
3. Voice input prototype (SpeechRecognizer → chat)
4. Onboarding flow for new users

---

## Principal Engineer Response

### What I Agree On
- Food DB enrichment is high-ROI, low-risk. Do it.
- State machine refactor was cleanly done. Phase enum is the right pattern.
- Theme propagation via `.card()` modifier was smart — one change, 46 views.

### Where I Push Back
1. **Voice input is premature.** SpeechRecognizer is straightforward but the UX design (when to listen, how to display, error states, microphone permissions) is a rabbit hole. Research yes, ship no — not in the next 20 cycles.
2. **Chat UI cards require a rendering engine.** Structured response types, card templates, layout logic — this is a multi-cycle project. Propose: start with one card type (food log confirmation) and iterate.
3. **Onboarding is scope creep for an app with <10 TestFlight users.** When we have 50+, then invest. For now, the profile nudge banner works.

### Technical Assessment
- 882 tests, build 104, zero open bugs. Health is good.
- Coverage sprint hit targets. The "coverage before refactor" gate proved its value — state machine refactor went smoothly because AIToolAgent had tests.
- ConversationState.Phase is a clean FSM. Next step: move remaining @State data vars (pendingRecipeItems, pendingExercises) into the Phase associated values for full consolidation.
- Food DB at 1,075 — engineer agrees this is the easiest win. JSON additions don't break anything.
- MacroRingsView is well-isolated as a Shared component. No performance concern at 4 rings.

### Sequencing Recommendation
1. Food DB enrichment (zero risk, high user value) — finish the in-progress batch
2. Chat UI: one structured card type (food confirmation)
3. Prompt consolidation (compress token usage, improve response quality)
4. Multi-turn reliability testing
5. Voice input RESEARCH only (feasibility study, no shipping)

---

## Agreed Direction (Cycles 291–311)

### Sprint Plan

| # | Item | Priority | Est. Cycles | Notes |
|---|------|----------|-------------|-------|
| 1 | Food DB enrichment batch 2 | P0 | 1 | Soft drinks, breads, Thai/Japanese, Indian proteins. Target 1,200+ |
| 2 | Food DB enrichment batch 3 | P0 | 1 | Fruits, vegetables, common snacks to fill remaining gaps |
| 3 | Chat food confirmation card | P1 | 2 | Structured card when food is logged (name, cals, macros, edit link) |
| 4 | Prompt consolidation | P1 | 2 | Audit token usage, compress system prompt, measure improvement |
| 5 | Multi-turn reliability | P1 | 2 | Test and fix: 3-turn meal logging, 3-turn workout, topic switch |
| 6 | Voice input research | P2 | 1 | SpeechRecognizer feasibility study, prototype, decide go/no-go |
| 7 | Coverage maintenance | P2 | ongoing | Boy scout rule, new tests for new code |

### Decisions
- **Voice input:** Research only. Go/no-go decision at next review.
- **Onboarding:** Deferred until TestFlight user count > 50.
- **Exercise visuals:** Deferred to Phase 4. Text-only is acceptable for now.
- **Adaptive TDEE:** Stays reverted. v2 (weight-trend-only, no food log dependency) is a Phase 5 item.

---

## Open Questions

1. Should chat food confirmation cards be interactive (tap to edit) or informational only?
2. Is 2048 context window sufficient for 3-turn meal logging, or do we need to profile higher?
3. Voice input: continuous listening or push-to-talk?

---

*Comment on any line to shape the next 20 cycles.*
