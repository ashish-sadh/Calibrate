# Sprint Board

Priority: AI chat quality — natural conversation, better tool calling, insightful responses.

## In Progress

_(pick from Ready)_

## Ready

### P0: Chat Response Quality
- [x] **Presentation prompt tuning** — Added time-of-day context, example response, "warm and brief" tone. Tuned for Gemma 4 2B.
- [x] **Include user query in presentation context** — bestQuery (normalizer output) now flows through Phase 3 tool execution + LLM presentation.
- [x] **Richer tool data for presentation** — food_info has progress status indicator, weight_info has total change + weekly trend.
- [x] **SmolLM fallback templates** — addInsightPrefix() adds "Looking good —" / "Heads up —" based on data content.

### P1: Tool Calling Accuracy
- [x] **Tool routing verification** — 12 new eval cases verifying removed StaticOverrides queries route correctly. daily summary→food_info, sleep trend→sleep_recovery, weight progress→weight_info.
- [ ] **LLM eval on tool routing** — Run 40+ queries through Gemma 4 tool-calling path on device. Requires LLM eval (not unit test).
- [x] **Normalizer → tool pick chain** — bestQuery flows from normalizer through Phase 3 tool execution.
- [x] **Tool param extraction quality** — food_info gets yesterday/weekly/suggest context. sleep_recovery gets period=week. General queries pass raw query for LLM context.
- [x] **Anti-keyword tuning** — Verified: "how much does chicken weigh" suppressed by "how" anti-keyword on log_weight. "reduce fat" caught by diet advice handler.

### P2: Latency & Streaming
- [ ] **Measure end-to-end latency** — Time each pipeline stage for 10 common queries. Where is time spent? Normalizer? Tool execution? LLM presentation? Find the bottleneck.
- [ ] **Progressive multi-item disclosure** — For "rice and dal", show each found item as it's discovered, don't batch.
- [ ] **Normalizer cache** — If the same query was normalized before (same session), skip the 3s normalizer call.

### P3: Conversation Feel
- [ ] **Vary response openings** — LLM tends to start every response the same way. Add variety hints in the presentation prompt (time of day, performance vs goal).
- [ ] **Multi-turn meal planning** — "plan my meals for today" → iterative macro-aware suggestions. Gemma 4 only.
- [ ] **Conversation memory** — Pass previous tool results to next turn so LLM can reference them ("you mentioned protein was low earlier").

### P0: UI Bugs & Features (human-reported)
- [ ] **BUG: Recent foods missing macros** — When a manual entry (quick-add) is saved, it doesn't copy calories/macros to the recent foods list. Re-logging from recents shows 0 cal. Investigate how quick-add saves to food_usage and whether it stores the nutrition data.
- [ ] **Copy to today from past day** — When viewing a past day's food log, show a "Copy to today" option on each item (or a bulk copy). Don't show when already viewing today. Show a brief toast/nudge confirming the item was added without navigating away.
- [ ] **Plant points date awareness** — "Today" label under plant points doesn't update when viewing a different date. Change to show the actual date when not viewing today (e.g. "Apr 5" instead of "Today"). Week and month sections are fine.

## Done

### This sprint
- [x] **LLM presentation layer** — Info queries route through tool execution → Gemma 4 streaming presentation instead of data dumps
- [x] **Parallel tool execution** — TaskGroup-based parallel info tool execution
- [x] **ToolRanker keyword expansion** — food_info, weight_info, sleep_recovery enriched with summary/yesterday/weekly/suggest/trend keywords
- [x] **Enriched weight_info** — Total change + weekly trend data for LLM presentation
- [x] **Food_info context routing** — yesterday/weekly/suggest queries get specific data paths
- [x] **Sleep_recovery period param** — "sleep trend" routes with period=week

### Previous sprint
- [x] Multi-turn via normalizer context + history detection
- [x] Normalizer accuracy tuning (330+ eval scenarios)
- [x] Multi-turn pronoun resolution
- [x] Eval harness 370+ scenarios
- [x] Multi-item meal continuation
- [x] Gram/unit parsing (200ml, half cup, ranges)
- [x] Food search ranking (singular-first + length tiebreaker)
- [x] All P0/P1 AI parity gaps closed
- [x] All failing queries fixed (except meal planning)
- [x] Cross-domain analysis, weekly comparison, calorie estimation
- [x] Delete/undo food, weight progress, TDEE/BMR, barcode scan from chat
