# Sprint Board

Priority: close AI chat parity gaps from `Docs/ai-parity.md`. AI chat is the showstopper.

## In Progress

_(pick from Ready)_

## Ready

### P0: Close AI Chat Parity Gaps (from ai-parity.md)
- [x] **Mark supplement taken via chat** — "took my creatine", "took vitamin D". Add handler + supplement tool to mark taken by name.
- [x] **Edit/delete food entry via chat** — "remove the rice", "delete last entry", "undo". Add delete tool that removes most recent matching entry.
- [x] **Copy yesterday's food** — "copy yesterday", "same as yesterday". Add tool that duplicates yesterday's food entries to today.
- [x] **Quick-add raw calories** — "just log 500 cal for lunch", "log 400 calories". Parse calorie-only intents, create manual entry.
- [x] **Set/update weight goal** — "set goal to 160 lbs", "change goal to 75 kg". Add goal tool that updates WeightGoal.

### P0.5: Fix Failing Queries (from failing-queries.md)
- [x] **"suggest me workout"** — Handle workout suggestion variants. Small model: keyword handler. Large model: ensure exercise_info tool called. Add eval tests for 5+ phrasings.
- [x] **"I did yoga today"** — Log completed workout by name. Small: parse "I did [activity]". Large: LLM calls tool. Eval tests.
- [x] **"how many workouts this week"** — Instant answer from WorkoutService. Add to rule engine. Eval tests.

### P1: AI Chat Quality + Multi-Turn (Gemma 4)
- [x] **Gemma 4 prompt tuning** — Added 5 new tool examples (mark_supplement, delete_food, set_goal, body_comp, copy_yesterday).
- [ ] **Multi-turn meal planning** — "plan my meals for today" → iterative macro-aware suggestions. Gemma 4 only.
- [x] **Cross-domain analysis** — "why am I not losing weight?", "should I eat more", "I feel tired" → auto-combine relevant domains.
- [ ] **Eval harness 212→300+** — Cross-domain queries, screen-bias regression, multi-turn scenarios, supplement/goal commands.

### P2: More Chat Features
- [x] **Body comp entry via chat** — "my body fat is 18%", "log body fat", "bmi 22.5". Hardcoded + log_body_comp tool.
- [ ] **Trigger barcode scan from chat** — "scan barcode", "scan food". Open camera sheet.
- [ ] **Manual food with inline macros** — "log 400 cal 30g protein lunch". Parse calorie+macro intent.
- [ ] **Add supplement to stack** — "add vitamin D 2000 IU". Supplement management tool.
- [x] **Weekly comparison** — "compare this week to last". Instant rule engine answer from comparisonContext().

### P3: UI Polish
- [ ] **Saved meals (one-tap re-log)** — Save multi-item meals for quick re-logging from UI.
- [ ] **Accessibility pass** — VoiceOver labels on key screens.

## Done

- [x] Dual-model architecture (SmolLM + Gemma 4)
- [x] Screen bias removal (fullDayContext, universal pills, all tools for Gemma)
- [x] Model-aware routing, universal suggestion pills, "Start smart workout" pill
- [x] Loading indicator ("Preparing AI assistant...")
- [x] 10 consolidated tools with JSON tool-calling
- [x] Gemma 4 integration (xcframework, Metal GPU, chat template)
- [x] Meal logging flow ("log lunch" → recipe builder)
- [x] Exercise logging flow ("add exercise" → parse exercises → template)
- [x] "Coach Me" button in Exercise tab with reasoning notes
- [x] Gram-based food logging ("log paneer biryani 300 gram")
- [x] "Start" after workout recommendation fix
- [x] End-of-turn tail buffer widened (16→32)
- [x] Body composition tracking, HealthKit sync, auto-refresh
- [x] 212+ eval tests + 100-query LLM eval
