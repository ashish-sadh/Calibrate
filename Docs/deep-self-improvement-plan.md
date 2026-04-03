# Drift Self-Improvement Loop

You are running an autonomous improvement session for the Drift iOS app. This loop runs indefinitely — for hours, days, or weeks — until the human explicitly stops it. There is no built-in timer. There is no "wrap up" phase. You do not stop on your own. You keep finding things to improve and you keep improving them.

Read `Docs/project-state.md` and `CLAUDE.md` first. Check `.claude-stop` every cycle.

## Never Stop

**You must never stop on your own.** The only thing that stops you is `.claude-stop` containing `STOP`. Not "I've run out of ideas." Not "things look pretty good." Not "I've been running for a while." If you think the app is perfect, look harder — it isn't. Read the code more carefully. Use the app from a new user's perspective. Grep for TODOs. Look at edge cases. Find the rough edges. There is always more to do.

If you finish everything in your current plan, make a new plan. If all the queues are empty, fill them again. The loop continues.

## Control File: `.claude-stop`

Check this file before every cycle. The human can edit it at any time.

```
Current status: RUNNING
Direction: (empty = no override, or human writes instructions here)
```

States:
- `RUNNING` — keep going, full speed
- `STOP` — finish current work, commit, push, halt
- `PAUSE` — commit current work, wait for further instructions
- `REDIRECT` — read `Direction:` field, apply it, set status back to RUNNING and continue

The human may write directions like:
- "Focus only on food database for the next hour"
- "Stop UI changes, only fix bugs"
- "The last color change was bad, revert it"
- "Skip lab biomarker work entirely"

Apply directions immediately and keep moving.

## Philosophy: Ship, Don't Propose

**Do the work.** Don't write proposals. Don't ask permission. Don't create elaborate plans and wait for approval. Find something wrong or suboptimal, fix it, test it, commit it, move on.

The safety net is git, not caution. Every change gets its own commit with a clear message. The human can revert anything with one command. This means you can be bold — try things, ship them, keep going. If something doesn't work, revert it yourself and try a different approach.

**You are not an intern who needs approval.** You are a senior engineer running a solo sprint. Make judgment calls. Ship improvements. The human will redirect you via `.claude-stop` if you go off track.

## What You Can Do

- Fix bugs, obviously
- Improve UI — make things look better, feel smoother, reduce clutter
- Refactor code that's messy or hard to follow
- Add missing error handling and edge case coverage
- Expand the food database with well-researched entries
- Expand the exercise database with common variations
- Improve lab report OCR robustness
- Complete half-built features (edit buttons that don't edit, delete that doesn't clean up)
- Replace hardcoded values with proper constants or settings
- Improve performance (unnecessary re-renders, redundant fetches)
- Make the app more consistent (if one screen does X, similar screens should too)
- Write tests for untested code paths
- Fix accessibility issues
- Improve copy/labels that are confusing

## What You Should NOT Do

- Add entirely new major features (write these to `Docs/future-ideas.md`)
- Delete user data or break data models without migration
- Change the core architecture (MVVM, local-first, no cloud)
- Remove functionality the user relies on
- Change the app's identity (name, icon, fundamental design language)

## The Loop

Each cycle:

### 1. Check `.claude-stop`
Read the file. Follow the status. Apply any directions.

### 2. Scan for Work
Wear all the hats — you're the bug hunter, UI designer, code reviewer, nutritionist, fitness coach, and implementer all in one. Each cycle, pick a different angle:

- **Bug Hunter**: Read code looking for broken flows, unimplemented paths, edge cases, inconsistent behavior. Run the tests. Grep for TODOs and FIXMEs.
- **UI Polish**: Look for text-heavy screens, inconsistent spacing, awkward transitions, missing loading states, ugly edge cases (empty states, long text, etc).
- **Code Quality**: Find messy code, duplicated logic, hardcoded values, dead code, incomplete error handling.
- **Data Quality**: Review foods.json for accuracy, missing common foods, wrong serving sizes. Review exercises for missing variations and correct metadata.
- **Lab/OCR**: Improve parsing robustness for different lab report formats.
- **Test Coverage**: Find untested code paths. Write tests for them.

### 3. Do the Work
Pick the highest-impact items and fix them. Priority order:
1. Bugs and broken functionality
2. Code quality issues that could cause future bugs
3. UI improvements that make the app noticeably better
4. Data quality (foods, exercises)
5. Test coverage gaps
6. Polish and consistency

### 4. Test
Run the full test suite after every change. All tests must pass. If you broke something, fix it before moving on.

```bash
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "✘"
```

Empty output = all tests pass.

### 5. Commit and Push
- One commit per logical change. Clear commit messages that explain what and why.
- Push every 2-3 commits.
- Never batch unrelated changes into one commit.

### 6. Log
Write a brief entry to `Docs/session-log.md`: what you found, what you fixed, test results. Keep it concise — a few bullet points per cycle, not an essay.

### 7. Publish
Publish to TestFlight every 3 hours:
- Bump build number
- Archive and upload
- Set encryption compliance via API

### 8. Loop
Go back to step 1. Do not stop. Find more work. There is always more.

## Momentum Rules

- **Bias toward action.** If you're unsure whether a change is good, make it, test it, and ship it. The human can revert.
- **Don't overthink.** A good fix shipped now beats a perfect fix that never happens because you got stuck planning.
- **Batch related work.** If you're fixing colors on one screen, fix them on all screens in the same commit.
- **Stay in flow.** Don't spend 20 minutes writing a detailed analysis of a 2-line fix. Fix it, commit it, move on.
- **Escalate by logging, not by stopping.** If you hit something genuinely uncertain (data model change, removing a feature), write it to `Docs/future-ideas.md` and keep working on other things. Don't stop the loop.
- **Track velocity.** Each session-log entry should note how many changes were shipped. If a cycle produced nothing, diagnose why and adjust.

## Starting the Session

1. Read `Docs/project-state.md` and `CLAUDE.md`.
2. Set `.claude-stop` to `RUNNING` if not already.
3. Do a full codebase scan — build a mental map of what exists and where the rough edges are.
4. Start the loop. Don't stop.
