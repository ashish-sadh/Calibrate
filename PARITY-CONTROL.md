# Android Parity Autopilot — Control Switch

**Current state: RUNNING — tiered autopilot** (since 2026-07-27).
Three complexity-routed lanes: **Fable** tester (scans iOS code + walks both apps
→ `drift-android/PARITY-MATRIX.md` + `needs-plan` issues) → **Opus** planner
(plans each issue → `planned`) → **Sonnet** executor (implements per plan,
verifies, publishes). Codex fallback underneath. Same single control file.

## The one control file

Everything (worker + scout + Codex fallback) is governed by a single file:

```
~/drift-android-parity.txt
```

It contains exactly one word. Three valid values:

| Command | Effect |
|---|---|
| `echo RUN   > ~/drift-android-parity.txt` | **Restart the autopilot.** Watchdogs resume spawning sessions. |
| `echo PAUSE > ~/drift-android-parity.txt` | Idle everything (watchdogs stay alive, spawn nothing). Current state. |
| `echo STOP  > ~/drift-android-parity.txt` | Exit the watchdog processes entirely. |

The watchdogs poll this file every ~60s, so a change takes effect within a minute.
**To restart remotely: SSH to the Mac and run the `RUN` line above.** That's the only step.

## What's running (idle) right now

Three launchd-managed watchdogs stay alive across reboots and idle while PAUSED:
- `com.drift.android-parity` — Sonnet executor loop (`scripts/android-parity-watchdog.sh`)
- `com.drift.android-parity-scout` — Fable tester (`scripts/android-parity-scout-watchdog.sh`)
- `com.drift.android-parity-planner` — Opus planner (`scripts/android-parity-planner-watchdog.sh`)
- `com.drift.codex-fallback` — Codex lane, only fires if Claude is fully exhausted

If `STOP` was used and you want them back:
```
launchctl load ~/Library/LaunchAgents/com.drift.android-parity.plist
launchctl load ~/Library/LaunchAgents/com.drift.android-parity-scout.plist
launchctl load ~/Library/LaunchAgents/com.drift.codex-fallback.plist
echo RUN > ~/drift-android-parity.txt
```

## Model configuration (as of handoff)

- Worker + scout sessions: **Sonnet primary → Fable fallback** (`--model claude-sonnet-5 --fallback-model claude-fable-5`).
  Edit the `--model` / `--fallback-model` lines in the two `*-watchdog.sh` scripts to change, then restart the watchdogs (`pkill -f parity-watchdog.sh` — launchd respawns them).
- Codex fallback: activates only when `~/drift-android-parity-logs/claude-exhausted.flag` exists (Claude out); commits to an isolated branch for review, never `main`.

## Operator directives

Standing instructions the sessions read every run live in `~/drift-android-parity-directives.txt`.
The parity backlog is GitHub epic **#1059** + `android-parity`-labeled issues.

## Health check anytime

```
cd ~/workspace/Drift && ./scripts/android-parity-health.sh
```
