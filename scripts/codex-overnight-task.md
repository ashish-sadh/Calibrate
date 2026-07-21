You are Codex working in an ISOLATED git worktree (branch codex/overnight) of the
Drift iOS/Android health app, running as an overnight fallback while Claude credit
is exhausted. Your work will be REVIEWED by a human before any merge — commit to
THIS branch only, never main, never push.

# Standing task: expand DriftCore pure-logic test coverage (ADD-ONLY)

DriftCore (DriftCore/Sources/DriftCore/) is cross-platform pure logic — calculators,
parsers, formatters, domain services. Many have thin test coverage.

Each run, do ONE small, self-contained unit of work:
1. Pick a DriftCore pure-logic type with weak/missing coverage that you have NOT
   already covered on this branch (check `git log --oneline` on this branch first
   to avoid repeats). Good targets: calculators (TDEE/BMR, macro math, weight
   trend), parsers, formatters, unit conversions.
2. Read the source fully. Add Tier-0 tests in DriftCore/Tests/DriftCoreTests/
   (Swift Testing `@Test`, matching the existing style in that directory).
3. ABSOLUTE RULE — ADD-ONLY: do NOT modify, convert, reorder, rename, or delete
   ANY existing test or any source file. You may ONLY add new test methods/files.
   If you believe a source bug exists, do NOT fix it — write a `// TODO(codex):`
   note in your commit message describing it for human review, and test the
   CURRENT behavior.
4. Verify: `cd DriftCore && swift test` must pass (ignore pre-existing failures in
   food/DB tests like deleteByEntryId/caloriesLeft — they are known shared-DB
   parallel flakes; confirm your NEW tests pass and you added no regressions).
5. Commit to this branch only: `git add` your new test file(s), commit with a
   message starting `test(codex-overnight):` summarizing what you covered and any
   TODO(codex) bug notes. Do NOT push. Do NOT touch main.

Keep each run small (one type, a handful of tests). Quality over quantity — a human
reviews every commit in the morning.
