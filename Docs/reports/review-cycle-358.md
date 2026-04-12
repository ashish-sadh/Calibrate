# Product Review — Cycle 358 (2026-04-12)

Review #13. Covering cycles 291–358 (67 cycles). Previous review: Cycle 291.

---

## What Happened (Cycles 291–358)

### Sprint Scorecard (agreed at Review #12)
| Item | Status | Notes |
|------|--------|-------|
| Food DB enrichment to 1,200+ | **DONE** | 1,201 foods. Fruits, breakfast, bakery, Asian, Indian, global. |
| Chat food confirmation card | **DONE** | Structured card with name, calories, macros when food logged. |
| Prompt consolidation | **DONE** | Dead code removed, token budget safety added. |
| Multi-turn reliability | **DONE** | Topic switch detection, stale state cleanup. |
| Voice input research | **NOT DONE** | Deferred 3rd consecutive review. |
| Coverage maintenance | **DONE** | 886 tests (+143 from coverage sprint). |

**Score: 5/6 delivered.** Voice input deferred again — now a credibility issue.

### Key Commits
- `a2f80b4` fix: multi-turn reliability — topic switch detection, stale state cleanup
- `55b5a28` refactor: prompt consolidation — remove dead code, add token budget safety
- `9762576` feat: structured food confirmation card in AI chat
- `de67346` feat: food DB to 1,201 — fruits, breakfast, bakery, Asian, Indian, global
- `d4a1414` feat: add 31 foods — beverages, Thai, Japanese, Indian proteins, snacks
- `f1fc6ed` refactor: conversation state machine — replace scattered pending vars
- `d97d294` feat: dashboard redesign — macro rings hero, section headers
- `281ae42` feat: bold UI theme overhaul — premium dark refresh
- `3c3352f` fix: revert adaptive TDEE — dropped calories dangerously

### Current State
- 886 tests, 19 test files, 380+ eval scenarios
- 1,201 foods, 873 exercises, 19 AI tools
- Build 104 on TestFlight
- Zero open bugs, zero open GitHub Issues

---

## Product Designer Assessment

### Strengths
The sprint execution was excellent — 5/6 items delivered, and the ones that shipped are meaningful. The food confirmation card is the first structured UI element in chat, breaking the text-only pattern. Multi-turn reliability fixes directly improve the core "type what you did" experience. Food DB at 1,201 is a trust milestone — users hit "not found" less often.

The macro rings + premium dark theme (shipped in the coverage sprint before this period) give the app a genuinely premium feel. First time Drift looks like it belongs on the App Store alongside Whoop and Strong.

### Gaps & Concerns

**1. Voice input — 3 reviews deferred. This must stop.**
Voice input has been in "Next" or "research" for 3 consecutive reviews. Meanwhile, the competitive landscape is moving fast. iOS SpeechRecognizer is a well-documented API. A basic prototype (mic button → speech-to-text → feed to chat) is 1-2 cycles of work. We don't need perfection — we need a go/no-go decision backed by a working prototype.

**2. Color harmony still unfinished.**
The sprint task was added (`e02f599`) but not executed. The dark blue/purple palette with bright ring colors still feels disjointed. This is the most visible quality gap — every user sees it on every screen.

**3. MFP is building a moat.**
MFP acquired Cal AI (AI photo scanning, 15M downloads, $30M ARR), integrated ChatGPT Health, and acquired Intent (meal planning) — three major moves in 12 months. Their food DB is now 20M foods. Our 1,201 foods is 0.006% of that. We can't compete on DB size, but we MUST compete on AI chat quality and privacy. That's our moat.

**4. Whoop's Passive MSK is the future.**
Whoop's Strength Trainer now auto-detects muscular load without manual logging. Text/photo → structured workout. Behavior Insights tied to Recovery scores. This is where wearable + AI is going. We can't match hardware, but we can match the "text → structured data" pattern — that's exactly what our AI chat does.

**5. MacroFactor launched a workout app.**
MacroFactor Workouts (Jan 2026) brings personalized workout plans and progression tracking. They're expanding from nutrition into our exercise territory. Their adaptive algorithms are strong. We need to make sure our workout experience is competitive.

### Proposed Changes

1. **Voice input prototype — P0, non-negotiable.** 1 cycle to build SpeechRecognizer → chat pipeline. Go/no-go at next review.
2. **Color harmony pass — P0.** One cycle, app-wide. Research Whoop/Apple Fitness palettes, pick cohesive system, apply everywhere.
3. **Chat UI evolution — P1.** Message bubbles, typing indicator, tool execution feedback. The confirmation card proved structured chat UI works — keep going.
4. **Food DB to 1,500 — P1.** Focus on most-searched-but-not-found items. Indian restaurant meals, fast food combos.
5. **Meal planning dialogue — P2.** "Plan my meals today" is the top failing query. Iterative suggestion flow.

---

## Principal Engineer Assessment

### Technical Health
Architecture is in good shape. The conversation state machine (`ConversationState.Phase`) landed cleanly and eliminated invalid state combinations. Prompt consolidation reduced token waste in our tight 2048-token context window. Multi-turn fixes are targeted and testable — topic switch detection and stale state cleanup are the right patterns.

886 tests is healthy. Zero open bugs. The coverage gate is working as intended — it correctly blocks risky refactors until test coverage exists.

### Review of Designer Proposals

**Voice input (P0) — Agree, with caveats.**
SpeechRecognizer is straightforward API. The risk isn't the speech-to-text — it's the downstream effects. Spoken input is messier than typed: "um", "like", partial sentences, corrections. Our AI pipeline (StaticOverrides regex + LLM normalizer) was built for typed input. We need to test how our existing pipeline handles speech-quality text before calling it done. Prototype: mic button → SpeechRecognizer → existing chat input. Don't build a separate speech pipeline.

**Color harmony (P0) — Agree.** 
Pure design work, zero architectural risk. `.card()` ViewModifier pattern means one source of truth for card styles. The risk is scope creep — "color harmony" can expand to "full redesign." Scope it: background, card, accent, ring, text colors. 6 decisions, applied consistently. One cycle.

**Chat UI (P1) — Agree, but sequence carefully.**
Message bubbles and typing indicators are view-layer changes. Tool execution feedback needs state machine integration (show "Looking up food..." during Tier 2-3 execution). Do bubbles first (pure UI), then tool feedback (needs plumbing).

**Food DB to 1,500 (P1) — Agree.**
JSON-only changes, zero code risk. Ideal background work. But the designer is right — we can't compete with MFP's 20M. Our advantage is AI parsing quality, not DB size. Focus on the 300 most common foods being correct, not raw count.

**Meal planning (P2) — Agree on priority.**
This is a multi-turn dialogue feature that needs the state machine to handle `awaitingMealPlan` phase. The Phase enum makes this cleaner than it would have been before. But it's not a 1-cycle item — park at P2.

### Issue Triage
- Zero open GitHub Issues. Clean slate.
- PR #2 (Cycle 199 review) is stale — 67 cycles old, no comments. Merge it.

### Technical Debt Watch
- `AIChatView` still 400+ lines — ViewModel extraction should happen alongside the chat UI work.
- StaticOverrides at 421 lines — stable, no urgency.
- Context window (2048 tokens) is the hard ceiling on multi-turn quality. Worth profiling on 6GB devices if voice input increases prompt length.

---

## Agreed Direction — Cycles 358–378

### Sprint Plan
| Priority | Item | Cycles Est. | Owner |
|----------|------|-------------|-------|
| **P0** | Voice input prototype — SpeechRecognizer → chat | 1-2 | Engineer |
| **P0** | Color harmony — app-wide palette refresh | 1 | Designer/Engineer |
| **P1** | Chat UI — message bubbles, typing indicator | 2-3 | Designer/Engineer |
| **P1** | Chat UI — tool execution feedback ("Looking up...") | 1-2 | Engineer |
| **P1** | Food DB enrichment to 1,500 | 3-4 | Autopilot |
| **P2** | Meal planning dialogue prototype | 2-3 | Engineer |
| **P2** | Coverage maintenance — boy scout rule | Ongoing | Autopilot |
| **P2** | AIChatView ViewModel extraction (with chat UI work) | 1-2 | Engineer |

### Key Decisions
1. Voice input is P0 — no more deferring. Build prototype, test with real speech, go/no-go at Review #14.
2. Color harmony is P0 — one cycle, done. Not "iterate toward a palette."
3. Chat UI is the next visual frontier after color harmony. Confirmation card proved structured chat works.
4. Food DB growth is important but secondary to AI quality. Focus on accuracy over count.
5. Merge stale PR #2 from Cycle 199.

### Success Criteria for Review #14 (Cycle ~378)
- [ ] Voice input: working prototype OR explicit go/no-go with technical justification
- [ ] Color harmony: shipped, app-wide, cohesive palette
- [ ] Chat UI: at minimum message bubbles shipped
- [ ] Food DB: 1,400+ foods
- [ ] Zero P0 bugs

---

## Competitive Landscape Summary (April 2026)

| App | Key 2026 Move | Threat Level | What We Learn |
|-----|---------------|-------------|---------------|
| MyFitnessPal | Cal AI acquisition (photo scanning), ChatGPT Health, Intent (meal planning) | **High** | AI photo + 20M DB is their moat. We compete on privacy + on-device + chat quality. |
| Whoop | AI Strength Trainer (text/photo→workout), Passive MSK auto-detection | **Medium** | Text→structured data is exactly our pattern. Match their quality. |
| MacroFactor | MacroFactor Workouts app launch (Jan 2026) | **Medium** | They're expanding from nutrition→exercise. Our all-in-one is an advantage. |
| Strong | Steady. Clean UX benchmark. | **Low** | UX quality bar. Our workout logging should match their speed. |
| Boostcamp | Exercise presentation benchmark (videos, muscle diagrams) | **Low** | Visual exercise content. Later priority for us (text-only is fine for now). |

---

## Open Questions

1. **Voice input: should we use Apple's SFSpeechRecognizer or the newer SpeechAnalyzer API?** Need to check iOS 18+ availability.
2. **Context window: can we safely increase from 2048 to 4096 on 8GB devices?** Multi-turn + voice input will pressure token budget.
3. **Should we consider a "Drift Lite" mode for 4GB devices?** SmolLM-only, limited features, broader device support.

---

*Comment on any line to provide feedback. Next review at ~Cycle 378.*
