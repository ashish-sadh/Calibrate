# Sprint Board

Priority: AI chat quality — natural conversation, better tool calling, insightful responses.

## In Progress

_(pick from Ready)_

## Ready

### P0: Chat Response Quality
- [ ] **Presentation prompt tuning** — Current prompt is generic. Test 5+ prompt variants on real queries ("how am I doing", "calories left", "sleep trend"). Measure: does the LLM lead with insight? Does it feel like a friend? Tune for Gemma 4 2B specifically.
- [ ] **Include user query in presentation context** — Pass the (possibly rewritten) query from normalizer to streamPresentation so LLM knows what was actually asked. Currently only raw tool data is passed — LLM doesn't know if user said "how am I doing" vs "calories left".
- [ ] **Richer tool data for presentation** — food_info returns bare numbers. Add context: time of day, how far through the day, whether protein is lagging, trending up/down vs yesterday. Give LLM material to form an insight.
- [ ] **SmolLM fallback templates** — Small model can't stream presentation. Improve the raw data strings it returns — add one-line insight prefix based on data (e.g. "On track — " or "Watch out — ").

### P1: Tool Calling Accuracy
- [ ] **LLM eval on tool routing** — Run 40+ queries through Gemma 4 tool-calling path. Measure: does it pick the right tool? Does it extract the right params? Track accuracy and fix misroutes.
- [ ] **Normalizer → tool pick chain** — After normalizer rewrites, does tryRulePick find the right tool? Test messy variants: "hows my protien", "wat shud i eat", "cals left".
- [ ] **Tool param extraction quality** — ToolRanker.extractParamsForTool is basic regex. Test: does food_info get the right query param? Does sleep_recovery get "week" when user says "sleep this week"?
- [ ] **Anti-keyword tuning** — "how much does chicken weigh" should NOT trigger log_weight. "I want to reduce fat" should NOT trigger log_food. Audit anti-keywords across all 19 tool profiles.

### P2: Latency & Streaming
- [ ] **Measure end-to-end latency** — Time each pipeline stage for 10 common queries. Where is time spent? Normalizer? Tool execution? LLM presentation? Find the bottleneck.
- [ ] **Progressive multi-item disclosure** — For "rice and dal", show each found item as it's discovered, don't batch.
- [ ] **Normalizer cache** — If the same query was normalized before (same session), skip the 3s normalizer call.

### P3: Conversation Feel
- [ ] **Vary response openings** — LLM tends to start every response the same way. Add variety hints in the presentation prompt (time of day, performance vs goal).
- [ ] **Multi-turn meal planning** — "plan my meals for today" → iterative macro-aware suggestions. Gemma 4 only.
- [ ] **Conversation memory** — Pass previous tool results to next turn so LLM can reference them ("you mentioned protein was low earlier").

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
