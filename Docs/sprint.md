# Sprint Board

Priority: close AI chat parity gaps from `Docs/ai-parity.md`. AI chat is the showstopper.

## In Progress

_(pick from Ready)_

## Ready

### P0: Close AI Chat Parity Gaps (from ai-parity.md)
- [x] **Mark supplement taken via chat** — "took my creatine", "took vitamin D". Add handler + supplement tool to mark taken by name.
- [x] **Edit/delete food entry via chat** — "remove the rice", "delete last entry", "undo". Add delete tool that removes most recent matching entry.
- [x] **Copy yesterday's food** — "copy yesterday", "same as yesterday". Add tool that duplicates yesterday's food entries to today.
- [ ] **Quick-add raw calories** — "just log 500 cal for lunch", "log 400 calories". Parse calorie-only intents, create manual entry.
- [ ] **Set/update weight goal** — "set goal to 160 lbs", "change goal to 75 kg". Add goal tool that updates WeightGoal.

### P0.5: Fix Failing Queries (from failing-queries.md)
- [ ] **"suggest me workout"** — Handle workout suggestion variants. Small model: keyword handler. Large model: ensure exercise_info tool called. Add eval tests for 5+ phrasings.
- [ ] **"I did yoga today"** — Log completed workout by name. Small: parse "I did [activity]". Large: LLM calls tool. Eval tests.
- [ ] **"how many workouts this week"** — Instant answer from WorkoutService. Add to rule engine. Eval tests.

### P1: AI Chat Quality + Multi-Turn (Gemma 4)
- [ ] **Gemma 4 prompt tuning** — More per-tool examples, better tool selection accuracy. Test with 100-query eval.
- [ ] **Multi-turn meal planning** — "plan my meals for today" → iterative macro-aware suggestions. Gemma 4 only.
- [ ] **Cross-domain analysis** — "why am I not losing weight?" → combine food + weight + exercise context in one answer.
- [ ] **Eval harness 212→300+** — Cross-domain queries, screen-bias regression, multi-turn scenarios, supplement/goal commands.

### P2: More Chat Features
- [ ] **Body comp entry via chat** — "my body fat is 18%", "log body fat". Add body comp tool.
- [ ] **Trigger barcode scan from chat** — "scan barcode", "scan food". Open camera sheet.
- [ ] **Manual food with inline macros** — "log 400 cal 30g protein lunch". Parse calorie+macro intent.
- [ ] **Add supplement to stack** — "add vitamin D 2000 IU". Supplement management tool.
- [ ] **Weekly comparison** — "compare this week to last". Trend analysis response.

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
