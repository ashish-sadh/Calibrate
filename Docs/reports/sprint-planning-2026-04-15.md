# Sprint Planning Report — 2026-04-15

## Previous Sprint: Complete (10/10)

All tasks from the AI Chat Reliability sprint shipped:

| Task | Status |
|------|--------|
| #78 Input normalization pipeline | Shipped — centralized at sendMessage entry point |
| #79 Food logging gold set eval | Shipped — 13 voice-style tests |
| #80 Multi-turn context hardening | Shipped — 18 multi-turn tests |
| #81 Coverage: WeightTrendService | Shipped |
| #82 Coverage: AIRuleEngine | Shipped — 11 food-seeded branch tests |
| #83 Food DB: +20 foods | Shipped — 1544->1564 |
| #84 Bug hunting: AI food logging | Shipped — multi-food meal hint fix |
| #85 Eval: Voice-style input cases | Shipped — 13 InputNormalizer cases |
| #86 UI: Exercise card enhancement | Shipped — muscle group SF Symbol chips |
| #87 Coverage: Notification + Insight | Shipped |
| P0 #77: Food diary meal grouping | Shipped |
| P0 #88: AI food logging fixes | Shipped |

**Velocity: 100%.** All failing queries fixed. All human-reported bugs resolved.

## New Sprint: AI Chat LLM-First Pipeline

### Strategic Direction

Product focus mandates replacing hardcoded rules with LLM-based intent detection. Design doc #65 (PR #112) proposes flipping the Gemma 4 pipeline from rules-first to LLM-first:
- Shrink StaticOverrides from ~50 patterns to ~10
- Make IntentClassifier the primary routing path
- Retire ToolRanker keyword scoring on Gemma 4
- Latency tradeoff: ~3s correct answer beats instant wrong answer

**Decision required:** PR #112 needs `approved` label to unblock 4 refactor tasks.

### Tasks Created

**Ready now (no approval needed):**
- #116 — Expand gold set eval to 50+ queries (measurement framework)
- #117 — Voice input edge case hardening (product focus: voice)
- #118 — Food DB: +30 voice-friendly foods

**Contingent on #65 approval:**
- #92 — Reorder AIToolAgent pipeline (LLM-first)
- #93 — Prune StaticOverrides to essentials
- #94 — Retire ToolRanker keyword scoring (Gemma path)
- #95 — Extend IntentClassifier for primary routing
- #96-97 — Coverage + bug hunting for refactored pipeline
- #99 — Update state.md post-refactor

### Design Docs Pending Review
- **#65** — Structurally fix AI chat (PR #112, doc-ready, awaiting approval)
- **#66** — Exercise images/youtube enrichment (doc-ready)
- **#74** — Lab reports + LLM parsing (P1, doc-ready, included in sprint)

### Risk Assessment
- Refactor touches core query routing (~3,000 LOC surface area)
- Gold set eval (#116) must land first to capture baseline
- SmolLM path unchanged — no regression for 6GB devices

## Current State
- Build 119, 1077+ tests, 1564 foods, 960 exercises
- Phase 3c (Polish & Depth)
- All failing queries fixed, all human bugs resolved
