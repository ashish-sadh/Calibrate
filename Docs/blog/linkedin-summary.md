# LinkedIn version (~280 words)

I've never built an iOS app before. **Drift** is my first.

It has 25 beta users on TestFlight right now — friends, friends of friends, teammates, family. When one of them reports a bug, it usually gets diagnosed, patched, tested, and committed within ten minutes. Unless the loop is mid-market-research, in which case I might have to wait an hour. That shouldn't be possible for a first-time iOS developer on a Saturday morning. It is, because Drift isn't the only thing I built. I also built the *harness* that builds Drift.

In the last seven days the harness pushed **409 commits**, shipped **9 user-visible features** (cross-domain insight tool, weight-trend prediction, photo-log overhaul with multi-provider AI, expanded eval harness to 175+ cases, …), closed **~20 bugs**, published **10 daily exec reports** as merged PRs, and wrote a full product review — studying MyFitnessPal's Winter 2026 AI release and Whoop's Behavior Trends, then *telling me* that two of our queued features had slipped behind competitive parity and needed to be re-prioritized. Its personas (Product Designer + Principal Engineer) have now been through 54 reviews — the early entries are surface-level; recent ones read like senior-engineer RFCs.

Think [Ralph loop](https://ghuntley.com/ralph/) grown up: the inner `while true` is still there, wrapped in a supervisor tree, a domain-specific state machine (GitHub issues + labels), enforcement hooks, and a live dashboard. Deliberately *not* a general-purpose personal agent — narrow beats broad.

Four patterns turned out to be non-negotiable: reconcile with ground truth every tick (don't trust session memory), atomic claim (peek-without-claim is a distributed-systems bug), tool-call heartbeats (not log-file mtime), and launchd-over-the-watchdog (every supervisor needs a supervisor).

The higher-level takeaway: the agent is not the product you own. The scaffolding around it is.

Full post + zip of every hook, script, and dashboard wire so you can replicate it: [link]

#iOSDevelopment #AgenticEngineering #SoloDev #BuildInPublic
