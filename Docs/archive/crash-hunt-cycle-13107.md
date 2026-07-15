# Crash Hunt — Cycle 13107

**Date:** 2026-06-03
**Trigger:** Tenet #8 auto-firing (periodic crash hunt; last hunt was cycle 10950, #802).
**Issue:** #824
**Range audited:** baseline `46ec7d41` (cycle-10888 review merge, PR #787, 2026-05-16) → HEAD `74396f45` (TestFlight build 291, 2026-06-03).
**Scope:** 211 commits, 99 production Swift files changed (DriftCore/Sources + Drift app), ~+226k/−144k lines incl. generated/vendored.

## Methodology

Swept the **added** production lines in `46ec7d41..HEAD` for the crash-prone patterns named in the scope, then read the live code at every genuine hit (not just the grep line) to classify it FIX / SAFE-guarded / SAFE-annotated. Test code is excluded from fixes — idiomatic `try!`/force-unwrap in test setup is in-scope only for the doc. Method is deliberately a focused scan + read-at-site rather than an exhaustive per-hunk derivation.

Pattern results in added production lines:

| Pattern | Hits in added prod code | Notes |
|---|---|---|
| `try!` | 0 | none introduced |
| `as!` | 0 | none introduced |
| `.unsafelyUnwrapped` | 0 | none introduced |
| `fatalError(` | 0 | none introduced |
| `.first!` / `.last!` | 0 live | the 3 grep hits are prior-audit annotation **comments**, not code |
| force-unwrap `()!` | 2 | both in `LlamaCppBackend`, provably safe — annotated |
| numeric subscript `[i]` | 5 | 4 guarded (see table); **1 latent trap fixed** (`median`) |
| `JSONDecoder().decode` | 1 | `try?` + `else` fallback — safe |

## Commit-sha table

| Commit | Role in this audit |
|---|---|
| `46ec7d41` | **Baseline** — cycle-10888 review merge (PR #787), 2026-05-16 |
| `74396f45` | **HEAD** — chore: TestFlight build 291, 2026-06-03 |
| `9dba457f` | Prior in-range crash-audit: dropped force-unwraps in 7 hot-path files |
| `c5a04c15` | Prior in-range crash-audit (#802): removed force-unwraps in cycle-10262 code |
| `cf73e753` | Weight-trend rework — added the `filtered[0]`/`pts[0]`/`samples[0]` subscript sites |
| `e820f95c` | Weight-trend significance gate — `samples.count >= 2` guarded rate calc |
| `4063336b` | Weight chart delta — trend-following endpoints |
| `69c31eb1` | LlamaCpp load race + Body placeholder small crash fixes |

Two prior in-range passes (`9dba457f`, `c5a04c15`) had already hardened the dict / `.first!` / `.last!` hot paths, which is why the live force-unwrap surface in this range is near zero.

## Findings table

| file:line | pattern | verdict |
|---|---|---|
| `WeightTrendCalculator.swift:474` `median(of:)` | empty-array subscript: `n=0` → even-branch `sorted[n/2-1]` = `sorted[-1]` OOB trap | **FIXED** — `guard !sorted.isEmpty else { return 0 }` (line 480) + Tier-0 test `median_emptyInput_returnsZeroWithoutTrapping` (Tests:1081). Latent today (only callers are tests), guarded so a future caller cannot reintroduce the trap. |
| `WeightTrendCalculator.swift:259–261` `filtered[0]` | array subscript | SAFE — guarded by `guard !filtered.isEmpty else { return nil }` (line 253) |
| `WeightTrendCalculator.swift:376–378` `pts[0]` | array subscript | SAFE — guarded by `guard isSufficient(pts), let first = pts.first, let last = pts.last else { return nil }` (line 371) |
| `WeightTrendCalculator.swift:425,454` `samples[0]` | array subscript | SAFE — each guarded by `guard samples.count >= 2 else { return 0 }` (lines 424 / 453) |
| `WeightTrendCalculator.swift:528` `JSONDecoder().decode(AlgorithmConfig.self,…)` | JSON decode | SAFE — `try?` + `else` fallback to `.default` in a `guard let` |
| `LlamaCppBackend.swift:47` `modelPath.path.cString(using: .utf8)!` | force-unwrap | SAFE-annotated — UTF-8 encodes every Swift `String`, so the unwrap cannot fail for any real on-disk path |
| `LlamaCppBackend.swift:133` `llama_sampler_chain_init(…)!` | force-unwrap | SAFE-annotated — non-optional C contract; nil only on unrecoverable allocation failure when a model is already loaded |

## Fix detail

`WeightTrendCalculator.median(of:)` computed the even-count branch `(sorted[n/2 - 1] + sorted[n/2]) / 2` unconditionally. For an empty input `n == 0`, `sorted[n/2 - 1]` is `sorted[-1]` — an out-of-bounds trap (hard crash). No production caller passes an empty array today (the live caller is the trend pipeline, which is already non-empty by its own guards; the only direct callers are tests), so this was a **latent** trap rather than a live one. The fix returns `0` for empty input, making the helper total, and a Tier-0 test pins the safe path so the trap cannot regress. The separate `TDEEEstimator.median([])` was already empty-safe (returns nil) and was left unchanged.

## Conclusion

The 211-commit range introduced **one** genuine (latent) crash trap — `median(of:)` on empty input — now fixed and tested. No new `try!`, `as!`, `.unsafelyUnwrapped`, or `fatalError` were added to production code; every added numeric subscript except `median` is bounds-guarded at its call site; the single JSON decode uses `try?` + fallback; and the two `LlamaCppBackend` force-unwraps are provably safe and now carry justification comments. Two prior in-range crash-audit passes (`9dba457f`, `c5a04c15`) account for the otherwise-clean force-unwrap surface. Tier-0 + Tier-1 test counts do not drop (one Tier-0 test added). No new force-unwraps introduced.
