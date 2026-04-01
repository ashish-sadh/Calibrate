# Claude Code Instructions for Drift

## Quick Start
Read `Docs/project-state.md` first - it has the complete project state, tech stack, all features, build commands, and pending work.

## Key Rules
- Build and test locally after every change: `xcodebuild build` then `xcodebuild test`
- All 566+ tests must pass before committing
- Don't upload to TestFlight unless the user says "publish"
- Internal group (Drift Myself) gets every build automatically
- Only push to external group when explicitly asked
- Always set encryption compliance after upload via API
- No MacroFactor references anywhere in code/docs
- Privacy-first: everything local, no cloud, no analytics

## Color Philosophy (Goal-Aware)
- Green (Theme.deficit) = aligned with goal (deficit when losing, surplus when gaining)
- Red (Theme.surplus) = against goal
- Default: assume losing weight

## Testing
- 566 tests across 12 files
- Run: `xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Check failures: pipe to `grep "✘"` - empty = all pass
- See `Docs/testing-process.md` for simulation testing

## Project Generation
Always run `xcodegen generate` after changing project.yml or adding new files.

## Self-Improvement Loop
When asked to run a self-improvement session, read `Docs/deep-self-improvement-plan.md` for the full multi-agent protocol. Check `.claude-stop` for control:
- `RUNNING` = continue
- `STOP` = halt
- `PAUSE` = wait
- `REDIRECT` = read Direction field for human feedback, apply it, continue

The human can give live feedback by editing `.claude-stop` without stopping the session.

## Working Directory
The project lives at `/Users/ashishsadh/workspace/Drift` (was renamed from Calibrate).
Shell may show old path - always `cd /Users/ashishsadh/workspace/Drift` first.
