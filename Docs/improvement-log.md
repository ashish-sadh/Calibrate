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

---

## Cycle 3 · 2026-04-06 08:44

**Priority:** P2 (Conversational workout builder)
**Change:** Enhanced workoutContext() with exercise details from last workout and body part coverage analysis
**Files:** AIContextBuilder.swift
**Build:** OK
**Tests:** 729 passed, 0 failed
**Eval harness:** All passed
**Commit:** 0a4ee95
**Status:** keep
**Notes:** LLM now sees "Last exercises: Bench Press 3x135lb, Squats 4x185lb" and "Needs training: Legs (5d), Back (4d)". This enables Flow C (AI suggests workout based on history).

---

## Cycle 4 · 2026-04-06 08:46
**Priority:** P3 (Eval harness)
**Change:** Eval 22→25: workout routing, false positives, multi-exercise parsing
**Commit:** 6dc40c0 | **Status:** keep

---

## Cycle 5 · 2026-04-06 08:47
**Priority:** P1 (Routing fix)
**Change:** Comparison routing includes domain context (workout/food) when mentioned
**Commit:** ace6652 | **Status:** keep

---

## Cycle 6 · 2026-04-06 08:48
**Priority:** P2 (Workout keywords)
**Change:** Expanded workout keywords: push/pull/leg day, body part, muscle, split, PPL
**Commit:** c415918 | **Status:** keep

---

## Cycle 7 · 2026-04-06 08:49
**Priority:** P3 (Response quality)
**Change:** Response cleaner: markdown bullets, numbered lists, regurgitation detection
**Commit:** 52f9d32 | **Status:** keep

---

## Cycle 8 · 2026-04-06 08:50
**Priority:** P3 (Eval harness)
**Change:** Eval 25→35: Indian foods, amounts, negation, response cleaner, domains
**Commit:** e47af9b | **Status:** keep

---

## Cycle 9 · 2026-04-06 08:51
**Priority:** P1 (Dashboard fallback)
**Change:** Dashboard fallback provides fullDayContext for substantive queries (>10 chars)
**Commit:** a619910 | **Status:** keep

---

## Cycle 10 · 2026-04-06 08:52
**Priority:** P3 (Eval harness)
**Change:** Eval 35→39: routing expansion, food coverage, action parser batch, rule engine
**Commit:** a1f72ab | **Status:** keep

---

## Cycle 11 · 2026-04-06 08:53
**Priority:** P2 (Workout builder)
**Change:** CREATE_WORKOUT template includes reps + weight in notes field
**Commit:** 3ec4fc1 | **Status:** keep

---

## Cycle 12 · 2026-04-06 08:55
**Priority:** P4 (Food polish)
**Change:** Food parser handles beverages/snacks/cooking: drank, snacked, made, i'm having
**Commit:** cc6dfef | **Status:** keep

---

## Cycle 13 · 2026-04-06 08:57
**Priority:** P3 (Eval harness)
**Change:** Eval 40→48: edge cases, robustness, truncation, disclaimers, dedup, weight units
**Commit:** a6e717d | **Status:** keep

---

## Cycles 14-26 · 2026-04-06 09:00-09:15

**Summary of changes:**
- P1: Few-shot examples in system prompt, dashboard fallback context, expanded keywords (deficit/surplus/carbs/plateau/stall), tightened keywords (fast→fasting, rest→rest day, press→space+press)
- P2: Direct template start handler, workout context suggests don't auto-start, CREATE_WORKOUT invites additions
- P3: Eval harness 35→58 methods (~380 test cases)
- P4: Synced multi-food parser verbs with single-food parser
- P6: Bullet regex line-start only, numbered list regex line-start only, weight false positive fix

**Commits:** 3381884, 1c33d34, 8b8b9a0, 377aa0f, 86f258a, 9af6908, 564e91a, 488bdf5, aeb707a, cd708a5, e1c346f, 0a7a577

---

## Sprint: Unified Service Layer · 2026-04-06

## b24799d TC-1: ToolSchema + ToolRegistry
## da6e4c8 TC-2: SpellCorrectService
## c8cc327 TC-3: JSON tool-call parser
## bc80c11 SVC-1: FoodService
## 7894260 SVC-2: WeightServiceAPI
## 17adc16 SVC-3: ExerciseService (smart builder, progressive overload)
## d72c698 SVC-4/5/6/7: SleepRecovery, Supplement, Glucose, Biomarker services
## 4b0750f WIRE-1: Register 20 tools in ToolRegistry
## cf9ce57 WIRE-2: System prompt injects tool schemas
## e7eacfb WIRE-3: AIChatView uses ToolRegistry.execute()
## af5f810 WIRE-5: Smart workout fallback
## db7fdc5 QA-1: Eval harness 63→69 (JSON tool-call tests)
## 7e5f461 QA-2/3/4: Service unit tests (69→80 eval tests)
## 7564b2f fix: Flaky session tests
