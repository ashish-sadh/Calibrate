# Replicate the Drift Command Center

One-page quickstart for adapting this harness to your own repo.

## What you're getting

```
drift-command-center-replicate/
├── program.md                    # the autopilot program (planning/senior/junior/standalone)
├── CLAUDE.md                     # project instructions for Claude Code
├── .claude/
│   ├── settings.json             # hook wiring — Pre/Post/Stop/SessionStart
│   └── hooks/*.sh                # every enforcement hook
├── scripts/
│   ├── self-improve-watchdog.sh  # the supervisor loop
│   ├── sprint-service.sh         # atomic next --claim / done / refresh
│   ├── planning-service.sh       # 11-item planning checklist
│   ├── issue-service.sh          # bug investigation + feedback drain
│   ├── design-service.sh         # design-doc lifecycle
│   ├── report-service.sh         # exec-report + product-review PR merge (self-healing label)
│   ├── session-monitor.sh        # Haiku-driven live session summaries
│   ├── session-compliance.sh     # session-end overhead + summary
│   ├── heartbeat-snapshot.sh     # session-heartbeat.log → heartbeat.json
│   ├── install-watchdog.sh       # install/uninstall/restart launchd
│   ├── com.drift.watchdog.plist  # launchd unit for supervising the watchdog
│   ├── check-rate-limit.sh       # GitHub API budget check
│   └── test-drift-control.sh     # harness regression suite (~200 tests)
└── command-center/
    ├── index.html                # dashboard (stats + ECG + events)
    ├── app.js                    # fetches GitHub state, renders, OAuth exchange
    ├── style.css                 # dark theme, monospace
    └── callback.html             # OAuth redirect landing page
```

## Conceptual dependencies

- **Claude Code** (`https://claude.com/claude-code`) as the agent runtime. Hooks wire into its PreToolUse / PostToolUse / Stop / SessionStart lifecycle.
- **GitHub** as the durable task store (issues labeled `sprint-task`, `SENIOR`, `in-progress`, `P0-bug`, `report`, etc.). The harness treats GitHub as source of truth; if you prefer Linear or Jira, swap `gh` calls for their CLI.
- **`gh` CLI** authenticated with `repo` scope.
- **launchd** (macOS) for supervising the watchdog. On Linux, port to systemd user units — the pattern translates cleanly.

## The minimum viable port

1. **Fork this folder** into your own repo as `drift/` or `harness/`.
2. **Find-and-replace identifying strings** — see §Paths to change below.
3. **Write a `program.md`** for your project — copy `program.md` as the template, replace the Drift-specific sections (AI pipeline, TestFlight, design docs) with your stages.
4. **Decide the shape of "a task"** — `sprint-service.sh` assumes a task is a GitHub issue with a `sprint-task` label. Adapt the label taxonomy to yours.
5. **Wire `.claude/settings.json`** in the root of your project (not in the replicate folder) so Claude Code picks the hooks up.
6. **Install the watchdog** — `./scripts/install-watchdog.sh install` (after editing paths in the plist).
7. **Start the loop** — `echo "RUN" > ~/drift-control.txt`. Kill with `echo "PAUSE"` / `echo "DRAIN"`.

## Paths to change

Every hardcoded reference below needs replacement for your environment:

| What | Where | Replace with |
|---|---|---|
| `/Users/ashishsadh/workspace/Drift` | everywhere | your repo path |
| `ashish-sadh` | `program.md`, `.claude/hooks/cycle-counter.sh`, `command-center/app.js`, `scripts/design-service.sh` | your GitHub username (for admin-comment reply detection, OAuth redirect URL) |
| `nimisha-26` | `program.md` | second admin user, if any — or remove |
| `ZJ5H5XH82A`, `623N7AD6BJ`, `ad762446-bede-4bcd-9776-a3613c669447` | `CLAUDE.md`, `.claude/hooks/testflight-check.sh` | your Apple Team ID, App Store Connect API key ID, issuer ID — or rip out the TestFlight flow entirely if you're not shipping iOS |
| `/Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_*.p8` | same | path to your own `.p8` Apple API key — **keep this outside the repo** |
| `Drift` as scheme/project name | `CLAUDE.md`, `testflight-check.sh` | your Xcode scheme or drop the archive/export steps |
| `github.com/ashish-sadh/Drift` | `command-center/app.js` | your repo — the dashboard filters issues/PRs by the `owner/repo` set here |
| `drift-command-center-auth.asheesh-sadh.workers.dev` | `command-center/app.js`, `callback.html` | your own Cloudflare Worker for OAuth code→token exchange, or use a GH PAT client-side if the dashboard is private |

## Control commands

Once running:

```bash
echo "RUN"   > ~/drift-control.txt    # autonomous loop active
echo "PAUSE" > ~/drift-control.txt    # finish current tool call, then stop spawning new sessions
echo "DRAIN" > ~/drift-control.txt    # finish current task, then stop
echo "STOP"  > ~/drift-control.txt    # immediate halt
```

`_Override:_` at the top of `program.md` is a second channel — flipping it between `CONTINUE` and `STOP` in `program.md` itself triggers a graceful wind-down at the next session boundary. The watchdog re-reads `program.md` on every tick.

## The four patterns (copy these even if you skip everything else)

1. **Reconcile with ground truth** — every gate that reads state should read from git log / GitHub API / filesystem, not from a stamp an earlier session wrote. See `self-improve-watchdog.sh :: is_planning_due` and `:: sync_stamps_from_main`.
2. **Atomic `next --claim`** — see `sprint-service.sh :: cmd_next`. Returns the next task AND marks it `in-progress` under one lock. The PreToolUse hook `require-claim.sh` refuses to let `Edit` or `Write` fire unless a claim is held.
3. **Tool-call heartbeat** — `session-heartbeat.sh` is wired as both Pre and Post ToolUse hooks; it stamps a timestamp file the watchdog reads (preferred over log-mtime, which lies during long generations).
4. **Launchd supervision** — `com.drift.watchdog.plist` + `install-watchdog.sh`. `KeepAlive=true`, `ThrottleInterval=30`. The watchdog itself has a supervisor.

## Regression tests

Before making changes to the harness, run:

```bash
bash scripts/test-drift-control.sh
```

~200 test cases covering: `next --claim` atomicity, planning-due detection, stamp reconciliation, orphan-label sweep, TestFlight self-heal, queue cap. Green here means you haven't broken the core state machine.

## Diagnostics

- `~/drift-state/session-heartbeat` — last tool-call timestamp
- `~/drift-state/session-heartbeat.log` — full tool-call log (bucketized into `heartbeat.json`)
- `~/drift-state/watchdog.log` — watchdog tick log (spawns, reconciliations, commits)
- `~/drift-control.txt` — control state
- `gh issue list --label in-progress` — what's currently being worked on

## What's NOT in this zip

- **The Drift app code itself** — this is harness-only; the thing that produces iOS binaries is a separate concern.
- **Your `.p8` Apple signing key** — keep that outside version control.
- **GitHub personal access tokens** — `gh auth login` before starting; the harness reuses the gh CLI's stored credentials.

## Questions worth thinking about before you port

- What's your durable store of "work to do"? (GitHub issues / Linear / a markdown file / a queue)
- What's your "ship" action? (TestFlight / npm publish / Vercel deploy / just a merge)
- What's your supervisor? (launchd / systemd / a cloud VM that auto-restarts)
- What's your source of truth for liveness? (tool-call heartbeat is the most reliable I've found)
- What's your kill switch? (`~/drift-control.txt` works; so does `killall -TERM`)

If you can answer those four, you have most of a harness.

---

*Full blog post: `../the-app-that-ships-itself.md`.*
