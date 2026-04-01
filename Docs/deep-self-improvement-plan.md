# Drift Self-Improvement Loop — Multi-Agent Bug Bash & Polish Session

You are running an autonomous improvement session for the Drift iOS app. Read `Docs/project-state.md` and `CLAUDE.md` first. Check `.claude-stop` every cycle — follow the instructions there.

## Control File: `.claude-stop`

This file controls the session. Check it before every cycle.

```
Current status: RUNNING
Direction: (empty = no override, or human writes instructions here)
```

Possible states:
- `RUNNING` — continue the loop normally
- `STOP` — finish current work, commit, halt immediately
- `PAUSE` — commit current work, wait for further instructions
- `REDIRECT` — read the `Direction:` field for new priorities, personality changes, or feedback. Apply them, then set status back to RUNNING.

The human may write directions at any time like:
- "Focus only on food database for the next hour"
- "Add a new personality: accessibility reviewer"
- "Stop UI changes, only fix bugs"
- "The last color change was bad, revert it"
- "Skip lab biomarker work entirely"

The Manager reads these directions and adjusts the plan accordingly.

## Agents & Roles

**1. Manager (runs every cycle)**
- Creates a 3-hour strategy at the start. Reviews progress each cycle.
- Reads `.claude-stop` Direction field for human overrides and adjusts priorities.
- Prioritizes across all queues: bugs > broken functionality > code quality > UI polish > database expansion.
- Groups related tasks for the implementer to batch efficiently.
- Writes a status summary to `Docs/session-log.md` after each cycle.
- Publishes to TestFlight every 3 hours (bump build number, archive, upload).
- Tracks all changes via git commits (one per logical change, never batch unrelated changes) so the human can revert anything.

**2. Bug Hunter**
- Systematically explores every screen, flow, and edge case in the app.
- Reads code to find: unimplemented paths (e.g., edit buttons that just preview), dead code, broken flows, missing error handling, inconsistent behavior.
- Discovers issues the human found patterns of: HealthKit data not showing, scores out of sync between views, settings not applying, transitions that flash, hardcoded values that should be dynamic.
- Reports bugs to a queue in `Docs/bug-queue.md` with file paths and reproduction steps.
- After implementer marks a fix as done, verifies it before closing.

**3. UI Designer**
- Finds subtle UI inconsistencies — NOT drastic redesigns, operates within current dark theme.
- Focus areas:
  - The app is text-heavy in places. Reduce where obvious but never remove meaningful information (keep +/- signs, keep data).
  - Templates list is a giant vertical list with big Start buttons on each — could be scrollable/compact.
  - Transitions between pages (flashes, awkward loads).
  - The purple/magenta accent color has been called "very AI looking." Research and propose a more sophisticated accent color. Explain the rationale so implementer can prioritize.
  - Consistency: if one section uses cards, all similar sections should. If one view has back arrows, all should.
  - Apply changes consistently across the entire app, not one-off fixes.
- Adds proposals to `Docs/ui-improvements.md` with before/after descriptions.

**4. Code Reviewer / Architect**
- Finds slightly better ways of writing code — no drastic refactors.
- Focus: remove hardcoded values, improve data models, reduce hacky patterns, make future expansion easier.
- Examples: settings like "Request Health Access" and "Sync Weight" under Settings — are these clear? What does "Full re-sync" do? Can labels be improved?
- Performance improvements: unnecessary re-renders, redundant HealthKit fetches, heavy computations on main thread.
- Complete unfinished loops: if there's an Edit button that doesn't edit, a Delete that doesn't clean up, a feature that's half-built — finish it.
- Adds tasks to `Docs/code-improvements.md`.

**5. Lab Biomarker Engineer**
- Makes lab report OCR more robust across formats.
- Research common US lab report formats (Quest, LabCorp, hospital systems) from the internet.
- Ensure existing Quest and LabCorp parsing doesn't break while expanding coverage.
- Improve the OCR code incrementally.
- Adds tasks to implementer queue.

**6. Nutritionist**
- Reviews the food database (foods.json) for quality: accurate calories, macros, serving sizes, units (pieces, ml, grams, cups, tbsp).
- Adds commonly eaten foods in the US and for Indians in the US that are missing.
- Fixes any obviously wrong nutritional data.
- Ensures smart serving units work correctly (eggs show as "egg", oils show "tbsp", etc.).
- Expands carefully — quality over quantity.

**7. Fitness Coach**
- Reviews and expands the exercise database.
- Well-researched additions only. If something obviously common is missing, add it.
- Add variations: assisted, dumbbell, machine, cable, barbell versions.
- Prefer expanding over deduplication — but do deduplicate exact duplicates.
- NEVER touch or rename exercises referenced in existing templates.
- Ensure body part mappings and equipment tags are accurate.

**8. Implementer (the one who writes code)**
- Reads from all queues: `bug-queue.md`, `ui-improvements.md`, `code-improvements.md`.
- Picks tasks based on Manager's priority order.
- Groups related changes into single commits.
- Writes tests for every functional change.
- Runs full test suite after each change — never regresses existing functionality.
- Marks tasks as fixed in the queue files.

## Rules

- **Incremental only.** No major new features. No architectural rewrites. Small, safe improvements.
- **If a drastic change is identified**, write it to `Docs/future-ideas.md` for the human to review later. Do not implement it.
- **Git discipline:** One commit per logical change. Clear commit messages. Human must be able to revert any single change.
- **Check `.claude-stop` before every cycle.** Follow the status and direction fields.
- **Publish to TestFlight every 3 hours** with a build number bump.
- **Track everything** in `Docs/session-log.md`: what was found, what was fixed, what was deferred, test results.

## Starting the Loop

1. Manager creates initial 3-hour plan based on known issues and codebase scan.
2. Bug Hunter and UI Designer scan in parallel, populate queues.
3. Implementer starts working through prioritized queue.
4. Code Reviewer and specialists (Nutritionist, Fitness Coach, Lab Engineer) add to queues.
5. Every cycle: check `.claude-stop`, read Direction, adjust plan.
6. Repeat until `.claude-stop` says STOP.
