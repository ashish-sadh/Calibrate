# Drift AI Improvement Log

Track of autonomous improvement cycles. Each entry = one cycle of the loop.

---

## Cycle 1 · 2026-04-06 08:37

**Priority:** P1 (Rearchitect: LLM for intent)
**Change:** Action tags always available in system prompt + all screen contexts; fix weight intent false positive
**Files:** LocalAIService.swift, AIContextBuilder.swift, AIActionExecutor.swift
**Build:** OK
**Tests:** 729 passed, 0 failed
**Eval harness:** All passed
**Commit:** d76c92e
**Status:** keep
**Notes:** "chicken weighs 200g" was a pre-existing bug — parseWeightIntent matched "weigh" too broadly. Changed to "i weigh". Action tags now always in system prompt so LLM can classify food/weight/workout intents from any screen.

---

## Cycle 2 · 2026-04-06 08:40

**Priority:** P1 (Rearchitect: LLM for intent)
**Change:** Removed 3 hardcoded response blocks from sendMessage() — workout logging prompt, generic food guidance, restaurant guidance. These now go to LLM.
**Files:** AIChatView.swift
**Build:** OK
**Tests:** 729 passed, 0 failed
**Eval harness:** n/a (no AI logic change, just routing)
**Commit:** 1bbd1a3
**Status:** keep
**Notes:** sendMessage() is 18 lines shorter. "log a workout", "log food", "ate out" now handled by LLM with action tags. Kept: weight intent (deterministic), multi-turn follow-up (complex), food/multi-food intent parsers (deterministic).
