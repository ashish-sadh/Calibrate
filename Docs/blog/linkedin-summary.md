# LinkedIn version (~230 words)

I built an iOS app called **Drift** — a privacy-first health tracker with an on-device LLM, no cloud, Indian food coverage. That's the product.

The part I want to write about is *how* it gets built. Drift ships itself, most days. A supervised autonomous loop — Claude Code + a shell-based watchdog + `launchd` — plans sprints, picks tickets, writes code, runs tests, publishes TestFlight builds, and files daily reports into a GitHub repo. I watch a dashboard. I course-correct when something looks off.

Four patterns turned out to be non-negotiable, and each came from an embarrassing failure:

1. **Reconcile with ground truth every tick** — don't trust any state a session wrote, because sessions die mid-stamp.
2. **Make work visible, atomically** — `next --claim` is one operation; hooks refuse to let code get written without a held claim.
3. **Liveness needs its own signal** — tool-call heartbeats, not log-file mtime (which lies during long generations).
4. **Every supervisor needs a supervisor** — `launchd` watches the watchdog.

OpenAI recently named this discipline [harness engineering](https://openai.com/index/harness-engineering) — the scaffolding around AI agents matters at least as much as the agents themselves. My small contribution: it **scales down**. A solo dev with bash and a GitHub repo can build a harness correct enough to run without them.

Full post + zip of every hook, script, and dashboard wire so you can replicate it: [link to blog post]

#iOSDevelopment #AgenticEngineering #HarnessEngineering #SoloDev #BuildInPublic
