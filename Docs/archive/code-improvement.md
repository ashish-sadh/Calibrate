# Drift Code-Improvement Loop

Autonomous loop for code quality. Principle-driven, not prescriptive. Follow this exactly.

## Steering notes

**Re-read before every cycle.** Human may change at any time.

_Directive:_ **Improve code quality, readability, and maintainability. Read the principle files, find the worst violation in the codebase, fix it. No behavior changes — refactoring only. Biggest wins first.**

_Focus:_ DDD violations and design patterns only — NO more file splitting. File decomposition is done (15 cycles, 3500+ lines reorganized). Focus on: business logic in views, dependency injection, protocol abstractions, testability improvements.

_Override:_ STOP

---

## Starting up

**Fresh start:**
1. Read `CLAUDE.md`
2. Read this file's steering notes
3. Read ALL files in `Docs/principles/` — these are your quality standard
4. Read `Docs/code-improvement-log.md` — know what's already been done
5. Build to confirm green baseline:
   `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "OK" || echo "FAIL"`
6. Start the loop

**Recovery (interrupted mid-cycle):**
- `git status && git log --oneline -5`
- Uncommitted changes? Finish or `git checkout -- .`
- Resume the loop

---

## The loop

LOOP FOREVER — do NOT stop between improvements:

### 1. STEER
Re-read steering notes above. Stop only if override says STOP.

### 2. SURVEY — find target file
```bash
wc -l Drift/**/*.swift Drift/*.swift 2>/dev/null | sort -rn | head -20
```
- Check `Docs/code-improvement-log.md` — skip files refactored in the last 5 cycles
- Respect the _Focus_ directive (if set to "Views only", only look at Views/)
- Pick the largest un-recently-touched file

### 3. READ
Read the target file (first 300 lines if it's huge, then continue if needed). Understand what it does, how it's structured, what patterns it uses.

### 4. EVALUATE
Hold the file against ALL four principle files mentally:
- **Clean Code** — long functions? deep nesting? bad names? hidden side effects?
- **Design Patterns** — God class? switch-on-type? hardcoded dependencies? tight coupling?
- **DDD** — business logic in a view? raw DB queries in ViewModel? anemic model? naming mismatch?
- **SwiftUI** — @State explosion? view too large? .onAppear with async? direct service calls?

Find the single worst violation — the one where fixing it most improves readability and maintainability.

### 5. STATE (internal — do NOT output this to the user)
Decide in your head: file, principle, smell, recipe. Do NOT print it.

### 6. CHANGE
- **READ every file you plan to edit BEFORE editing.** Understand types, function signatures, imports, protocol conformances. Then edit. This is non-negotiable — blind edits cause build failures.
- One **LOGICAL refactoring unit.** This can be:
  - Extracting a 500-line ViewModel from a view (touches 2+ files, diff may be 300+ lines — that's fine)
  - Breaking a god class into 3 focused services (touches many files — that's fine)
  - Renaming a protocol and all its conformers (touches many files — that's fine)
- The constraint is logical cohesion, not line count. One refactoring = one concept. But it can span many files.
- If extracting to a new file, put it in the same directory

### 7. BUILD
```bash
xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "BUILD OK" || (tail -20 /tmp/drift-build.log && echo "BUILD FAILED")
```

### 8. TEST
**Classify your refactoring:**
- **Pure move** (extracting to new file, no logic change): BUILD only. Existing tests cover behavior.
- **Signature change** (renamed methods, changed parameters, new protocols): BUILD + targeted tests (`-only-testing:DriftTests/AffectedTestClass`).
- **Logic restructuring** (split service, new state management, changed control flow): FULL test suite.

For targeted or full tests:
```bash
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests > /tmp/drift-test.log 2>&1 && echo "TESTS OK" || echo "TESTS FAILED"
```
Then: `grep "✘" /tmp/drift-test.log`

### 9. COVER
If you extracted a new type, split a service, or moved logic:
- Add unit tests for the new/changed pieces in DriftTests
- Test the public API of the extracted type — not internals
- Run tests again to confirm the new tests pass
- Skip this step for pure moves (renaming, reordering) where existing tests already cover the behavior

### 10. GATE
- **Fail?** Fix the issue. If stuck after **2 attempts**: `git checkout -- .`, log what went wrong and why, move on. Two failures on the same change means you misunderstand the code — revert rather than dig deeper.
- **Pass?** Commit:
  ```bash
  git add <specific files> && git commit -m "refactor: description"
  ```

### 11. LOG
One-line entry to `Docs/code-improvement-log.md`:
```
- **FileName.swift** — [Principle: X] Smell: what was wrong → what you did
```

### 12. LOOP
**IMMEDIATELY go to step 1. Do NOT output text to the user. Do NOT summarize what you did. Do NOT show tables or scorecards. The log entry IS the summary. Just go.**

**CRITICAL — NEVER STOP RULES:**
- Do NOT pause between cycles for ANY reason
- Do NOT output progress reports, summaries, or "N cycles done" messages
- Do NOT ask "want me to continue?" — the answer is ALWAYS yes
- Do NOT stop when you reach a round number of cycles (5, 10, etc.)
- Do NOT stop to show the user what you did — the log file IS the report
- The ONLY thing that stops the loop is `_Override: STOP` in steering notes above
- If context window is getting full, make your tool calls more concise — don't stop
- If a test fails for pre-existing reasons (not your change), note it in the commit message and continue
- If you run out of large files to decompose, shift to deeper refactoring (long functions, DDD violations)

---

## Rules

- **READ before EDIT.** Before modifying any file, read it. Understand its types, function signatures, imports. The #1 cause of build failures is editing blind — wrong parameter types, missing imports, outdated signatures. This rule is non-negotiable.
- All tests must pass before committing (pre-existing failures excepted — note in commit)
- **No behavior changes.** The app must work identically after every commit. This is refactoring only.
- **No new features.** Spot a bug? Log it in `Docs/failing-queries.md`. Don't fix it here.
- One **LOGICAL refactoring unit** per cycle. Multi-file changes are fine when they are part of the same refactoring (e.g., extract ViewModel from View + update all callers + add tests). The constraint is cohesion, not file count or line count.
- Run `xcodegen generate` if you add new files to the project
- Redirect ALL command output to `/tmp/` — never flood context
- **NEVER output summaries, tables, or scorecards between cycles.** Just log and loop.
- **NEVER stop to ask the user anything.** Make judgment calls. If ambiguous, pick the safer option.
- **NEVER wait for user input between cycles.** This loop is autonomous. Just go.
- If stuck after 2 attempts on one file, revert, log what went wrong, move to next target
- Run survey, build, and test commands in background when possible to save context

## What NOT to do

- Don't extract a subview that's under 30 lines and used once — that's noise, not improvement
- Don't create protocols for a single conformer
- Don't add generics unless there are 3+ concrete uses
- Don't rename things just for style — only when the current name is genuinely misleading
- Don't add comments to obvious code
- Don't make whitespace-only or formatting-only commits
- Don't move files between directories without a clear structural reason
- Don't "improve" code that's already clean — move on to worse offenders

---

## For the human

Start: `cd /Users/ashishsadh/workspace/Drift` → tell Claude "run code-improvement"

Steer: edit steering notes above. Agent re-reads every cycle.

Focus: set `_Focus:_` to narrow scope (e.g., "Views only", "Services only", "Clean Code only")

Stop: change override to `STOP`.

Principles: edit/add files in `Docs/principles/` — agent reads them at startup.
