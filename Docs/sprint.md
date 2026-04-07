# Sprint Board

## In Progress

_(pick from Ready)_

## Ready

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
- [ ] **BUG: Total calories error** — Investigate and fix calories calculation inaccuracy.
- [ ] **BUG: Flaky workout session tests** — Fix sessionSaveAndLoad, sessionRoundtripWithWarmups intermittent failures.
- [ ] **FEAT-001: Calorie estimation for unknown foods** — LLM fallback when DB lookup fails.

## Done

- [x] BUG-001: Calories left wrong number
- [x] Action tags in system prompt + all screens
- [x] Removed hardcoded handlers → LLM
- [x] Direct template start from chat
- [x] Food parser: beverages, snacks, cooking verbs
- [x] 41 self-improvement cycles, 63 eval tests, build 84
- [x] Docs rewrite: clean structure, tool-calling vision
- [x] Simplified program.md (220→76 lines)
