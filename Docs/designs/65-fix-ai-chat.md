# Design: Structurally Fix AI Chat

> References: Issue #65

## Problem

AI chat is brittle. The pipeline has 50+ hardcoded rules in StaticOverrides, 150+ keywords in ToolRanker, and 8+ regex patterns in AIActionExecutor — all of which break when users deviate from expected phrasing. Voice input makes this worse: natural speech has filler words, run-on sentences, and no punctuation.

Today's architecture is rules-first, LLM-fallback. The IntentClassifier (Gemma 4) already exists and works well, but it's only Phase 2 — most queries never reach it because StaticOverrides or ToolRanker intercept first. When those hardcoded paths misfire, users get wrong results with high confidence (worse than a slow correct answer).

**Who's affected:** Every user, every interaction. Misclassified intents cause wrong food logs, missed tool calls, and confusion.

## Proposal

Flip the pipeline: **LLM-first, rules-minimal.** Make IntentClassifier the primary routing path for all queries on Gemma 4 devices. Shrink StaticOverrides to ~10 instant patterns (greetings, undo, exact navigation). Retire ToolRanker keyword scoring. Add a lightweight input normalization step as preprocessing that feeds INTO the LLM rather than replacing it.

**In scope:**
- New pipeline order for Gemma 4 path
- Input normalization preprocessor (sprint task #78)
- Food logging gold set eval (sprint task #79)
- Multi-turn context hardening (sprint task #80)
- Shrinking StaticOverrides to essential-only patterns

**Out of scope:**
- SmolLM path changes (keeps current rules-based pipeline)
- New tools or tool schema changes
- Fine-tuning or new model downloads

## UX Flow

No visible UX changes — same chat interface, same tools. The difference is reliability.

### Example: Voice input (currently fails)

```
User: "umm I had like two eggs and some toast for breakfast"
Current: StaticOverrides misses (no "log" verb), ToolRanker scores log_food low ("had" = 2.5 but "like" confuses), falls to Tier 3 which may or may not parse correctly
New: Normalizer strips "umm", "like" → "I had two eggs and some toast for breakfast" → IntentClassifier → {"tool":"log_food","name":"eggs, toast","servings":"2"}
```

### Example: Ambiguous intent (currently misrouted)

```
User: "how much fat did I eat today"
Current: "fat" triggers body_comp anti-keyword in food_info, scoring is ambiguous
New: IntentClassifier sees full sentence context → {"tool":"food_info","query":"fat today"}
```

### Example: Multi-turn (currently loses context)

```
User: "log lunch"
AI: "What did you have for lunch?"
User: "rice and dal"
Current: StaticOverrides doesn't see prior context, may re-prompt or route to wrong tool
New: IntentClassifier receives history prefix "Chat:\nAI: What did you have for lunch?\n\nUser: rice and dal" → {"tool":"log_food","name":"rice, dal"}
```

## Technical Approach

### New Pipeline (Gemma 4 path)

```
User message
    |
    v
Step 0: Input Normalizer (instant, no LLM)
  Strip filler words (umm, uh, like, you know)
  Collapse whitespace, trim
  Normalize voice artifacts (repeated words, partial restarts)
  Fix common contractions ("dont" → "don't")
    |
    v
Step 1: Thin Static Layer (~10 patterns, instant)
  Only: greetings, thanks, help, undo, barcode scan
  These are interaction patterns, not intent classification
    |
    v
Step 2: IntentClassifier (LLM, ~3s)
  Existing system prompt + conversation history
  Returns: tool call JSON or follow-up text
  This is the PRIMARY routing path
    |
    v
Step 3: Tool Execution
  If tool call: execute via ToolSchema (existing)
  If info tool: fetch data, stream presentation (existing)
  If text: display directly (follow-up question, greeting)
    |
    v
Step 4: Streaming Fallback (only if classifier timeout/failure)
  Full context + history → respondStreamingDirect
  20s timeout, generic fallback text
```

### Files that change

| File | Change |
|------|--------|
| `Services/AIToolAgent.swift` | Reorder pipeline: normalizer → thin static → classifier → tools → stream fallback |
| `Services/StaticOverrides.swift` | Remove all intent-classification rules. Keep only: greetings, thanks, help, undo, barcode. ~10 patterns from ~50 |
| `Services/IntentClassifier.swift` | Add input normalization hook. Extend system prompt examples for voice-style input. Add confidence-based fallback |
| `Services/InputNormalizer.swift` | **New file.** Pure text preprocessing: filler removal, whitespace, voice artifacts. No LLM, no regex intent matching |
| `Services/ToolRanker.swift` | Remove `tryRulePick()` and keyword scoring for Gemma path. Keep `buildPrompt()` for SmolLM fallback and `rank()` for screen-default tool suggestions |
| `Services/AIActionExecutor.swift` | Keep param parsing (parseFoodIntent, extractAmount) — these are post-classification extraction, not intent detection |

### Dual-model handling

- **Gemma 4 (8GB+ devices):** New LLM-first pipeline above
- **SmolLM (6GB devices):** Keep current rules-first pipeline unchanged. SmolLM can't reliably do intent classification in 2048 context

### Latency tradeoff

Every query that used to be instant (~0ms via StaticOverrides) now takes ~3s via IntentClassifier. This is the right tradeoff: **a correct answer in 3s beats a wrong answer instantly.** Health tracking errors (logging wrong food, wrong calories) compound — users lose trust. The typing indicator already shows step labels ("Thinking...") during LLM calls.

Mitigation: the thin static layer still handles greetings/undo instantly (these are unambiguous and high-frequency).

### IntentClassifier enhancements

1. **Add voice-style examples** to system prompt:
   - `"umm had like 2 eggs and toast"→{"tool":"log_food","name":"eggs, toast","servings":"2"}`
   - `"so I did bench press today three sets of ten at 135"→{"tool":"start_workout","name":"bench press"}`

2. **Confidence-based fallback:** If classifier returns text that looks like a confused response (very short, repetitive), fall through to streaming rather than displaying it.

3. **History window:** Increase from 200 chars to 400 chars for better multi-turn context. Still fits in 2048 token budget (history is ~100 tokens at 400 chars).

## Edge Cases

- **Classifier timeout (10s):** Fall through to streaming pipeline (Phase 4). Already handled.
- **Classifier returns malformed JSON:** `parseResponse` returns nil → treated as text response. If text is empty, falls to streaming.
- **SmolLM device:** Pipeline unchanged — no regression.
- **Undo after LLM-classified action:** ConversationState.lastWriteAction tracking remains the same. Undo is in the thin static layer.
- **"log" without food name:** Classifier should return follow-up text "What did you have?" — this is already in the system prompt examples.
- **Very long input (voice rambling):** Input normalizer truncates to 200 chars after cleanup. Classifier context budget unchanged.

## Open Questions

1. **Should we A/B test?** We could add a feature flag to switch between old (rules-first) and new (LLM-first) pipelines. Adds complexity but lets us measure regression. Recommend: skip A/B, use gold set eval (#79) for quantitative measurement instead.

2. **How aggressive should static layer pruning be?** Proposal says ~10 patterns. Could go as low as 5 (greetings, undo, help) or keep ~15 (add navigation, barcode). Recommend: start with 10, expand only if classifier struggles.

3. **Should food param parsing move into classifier?** Currently IntentClassifier returns `{"name":"eggs, toast","servings":"2"}` and AIActionExecutor also has `parseFoodIntent()`. Could unify. Recommend: keep both — classifier extracts high-level, executor handles DB lookup, gram conversion, spell correction.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
