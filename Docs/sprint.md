# Sprint Board

## In Progress

_(pick from Ready)_

## Ready

### Tool-Calling Polish (Phase 2b)
- [ ] **TC-11: Pre-tool validation hooks** — Add optional `validate` closure to ToolSchema. Check weight in range, food name non-empty before executing.
- [ ] **TC-12: Post-tool response hooks** — After tool executes, suggest follow-up ("Want to log something else?", "Say 'start push day' to begin").
- [ ] **TC-13: Remove old keyword routing** — Delete AIChainOfThought keyword matching for domains where tools handle it. Keep rule engine for instant answers only.
- [ ] **TC-14: Screen-aware tool filtering** — Only inject relevant tools per screen in system prompt. Reduces prompt tokens.
- [ ] **MQ-1: Test tool-calling models** — Try Hermes-3-Llama-3.2-1B for structured JSON output. Compare with Qwen2.5-1.5B on eval harness.
- [ ] **MQ-2: Grammar-constrained sampling** — Use llama.cpp grammar to force valid JSON tool calls.
- [ ] **Multi-turn workout accumulation** — "I did bench" → "also did OHP" → combine in Swift state.
- [ ] **Eval harness to 100+ methods** — Expand from 80. Focus: tool-call JSON, multi-turn, ambiguous.

### Previous Sprint (remaining)

### Infrastructure
- [x] **TC-1: ToolSchema + ToolRegistry** — b24799d
- [x] **TC-2: SpellCorrectService** — da6e4c8
- [x] **TC-3: JSON tool-call parser** — da6e4c8+

### Services (one per domain — UI and AI share these)
- [x] **SVC-1: FoodService** — c8cc327+
- [x] **SVC-2: WeightService** — bc80c11+
- [x] **SVC-3: ExerciseService** — 7894260+
- [x] **SVC-4: SleepRecoveryService** — 17adc16+
- [x] **SVC-5: SupplementService** — 17adc16+
- [x] **SVC-6: GlucoseService** — 17adc16+
- [x] **SVC-7: BiomarkerService** — 17adc16+

### Wiring
- [x] **WIRE-1: Register all tools** — d72c698+
- [x] **WIRE-2: Update system prompt** — 6042fee+
- [x] **WIRE-3: Replace AIChatView routing** — cf9ce57+
- [x] **WIRE-4: Block health questions** — Done in WIRE-2 (system prompt)
- [x] **WIRE-5: Smart workout when no template** — e7eacfb+

### Quality
- [x] **QA-1: Eval tests for tool-call format** — af5f810+
- [x] **QA-2: Service unit tests** — db7fdc5+
- [x] **QA-3: Progressive overload tests** — db7fdc5+
- [x] **QA-4: Smart session builder tests** — db7fdc5+

### Bugs
- [ ] **BUG: Total calories error** — Needs reproduction steps from user. Calories math looks correct in FoodService/AIRuleEngine/AIContextBuilder.
- [x] **BUG: Flaky workout session tests** — 7564b2f+
- [x] **FEAT-001: Calorie estimation** — DB lookup instant, LLM fallback works via chain-of-thought

## Done

- [x] BUG-001: Calories left wrong number
- [x] Action tags in system prompt + all screens
- [x] Removed hardcoded handlers → LLM
- [x] Direct template start from chat
- [x] Food parser: beverages, snacks, cooking verbs
- [x] 41 self-improvement cycles, 63 eval tests, build 84
- [x] Docs rewrite: clean structure, tool-calling vision
- [x] Simplified program.md (220→76 lines)
