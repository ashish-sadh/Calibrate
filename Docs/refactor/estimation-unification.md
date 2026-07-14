# Estimation Unification — one model instead of seven patches

**Status:** proposed 2026-07-13 (operator-directed). **Owner:** estimation epic.
**Inputs:** online research sweep (state-space literature, reference-app methodology, NIH energy-balance models) + full requirements ledger of current pinned behaviors (39 items, inventoried 2026-07-13).

## 1. Problem

The weight/energy stack is seven stacked heuristics, each a patch for the last one's failure mode:
display EMA (14d) → gap reset → outlier filter → 8d re-smooth + OLS rate → Mann–Kendall
two-tier ramp → slow-trend 35d escalation → maintaining band → hard clamp → spike-proof seed
(2026-07-13) → energySignalConflicts gate (2026-07-13). Plus a TDEE estimator with its own
blend weights, and an AI tool (`weight_trend_prediction`) running a *divergent* raw-OLS
algorithm. Every new field report adds a gate; gates interact; the Monte-Carlo harness is the
only thing keeping the interactions honest. Two structural weaknesses are unfixable in this
architecture (MC-documented): 28-day cyclical water (cycle28 phantom ≈91%) and persistent AR(1)
water episodes (25–33% phantom).

## 2. Research conclusion (2026-07-13 sweep)

The entire industry sits on the EWMA→Holt spectrum (Hacker's Diet/TrendWeight = EWMA; Happy
Scale advanced = Holt/fixed-lag smoother; the leading adaptive-expenditure app = recency-weighted
moving average + weekly reverse-solved expenditure, no uncertainty shown). The principled step
past all of them, and the standard answer in the state-estimation literature, is a
**local-linear-trend Kalman filter**:

- **State** `x = [trueWeight w, dailyRate r]`; transition `w += r·Δt + ε_w`, `r += ε_r`;
  observation = scale reading with noise R. Process noise σ_r is the one responsiveness knob
  (maps 1:1 onto today's responsive/default/conservative presets).
- **Robust innovations**: Huber-clip normalized innovation at |ν|>3 → water spikes down-weighted
  *in the model*, retiring the outlier filter and the spike-proof seed.
- **Posterior variance** on the rate → publication = "95% credible interval excludes zero".
  This single rule replaces: Mann–Kendall Z + two-tier ramp + slow-trend escalation +
  significance flag + (largely) the energySignalConflicts gate — a tail plunge inflates the
  innovation sequence, which inflates P, which widens the CI, which softens publication,
  automatically.
- **Gaps**: skip updates, keep predicting; covariance grows → uncertainty widens honestly.
  Replaces interpolation-free gap rules; the 14d EMA reset becomes "prior drowned by grown
  covariance" (same observable behavior, no special case).
- **Energy coupling** (phase 3): expenditure reverse-solved weekly from
  `TDEE = median(qualified intake) − rate×7700`, exactly the adaptive-expenditure design the
  operator's reference app uses, with our existing ledger-trust floor kept verbatim.
  Accuracy ceiling per CALERIE validation (Sanghvi/Hall 2015): ~±200 kcal/day individual RMS —
  UI language must respect that floor.
- **Cycle water** (phase 4, differentiator nobody ships): optional ~28d seasonal state (or
  R-inflation during logged luteal windows) — the only known fix for the cycle28 canary.
- Reference implementations for intuition/porting: rlabbe/filterpy (+ book), pykalman (EM
  auto-tuning of Q/R per user history — candidate for per-user calibration later).

Key sources: Harvey local-linear-trend; Agamennoni outlier-robust KF; Student-t/VB KF family;
PMC5726602 (Kalman for weight-control interventions); Hall arXiv 0802.3234 + Lancet 2011;
Sanghvi PMC4515869; reference-app algorithm & expenditure articles; Hacker's Diet signal/noise.

## 3. Ledger mapping — every learned behavior, its fate

Legend: **N** = falls out of the model naturally · **K** = kept verbatim (product choice,
outside the model) · **S** = consciously superseded (rationale required) · **T** = becomes an
acceptance test only.

| # | Behavior | Fate |
|---|---|---|
| A1 | Time-weighted EMA, cadence-equal | **N** (Kalman Δt-aware by construction; display trend = filtered w) |
| A2 | 14d gap reset | **N/S** (covariance growth; verify drop→pause→flat scenario as test) |
| A3 | Gap-aware outlier filter | **N** (Huber innovation clip; gap term = grown P widens acceptance) |
| A4 | Smooth-first-differentiate-second | **N** (rate is a state, not a derivative of a smoother) |
| A5 | 8d re-smooth + OLS + 5→8d calibration | **S** (estimator replaced; regime-change latency pinned by A37 tests) |
| A6 | Spike-proof seed (0.75kg/first-5) | **N** (no window seeding exists) |
| A7 | MK two-tier ramp (1.15/1.65/2.0) | **S** (CI-based publication; ramp semantics → smooth P(trend) 0..1) |
| A8 | 35d slow-trend escalation + flatNoise-99 guard | **S** (long-horizon power is inherent: P shrinks as evidence accrues; detection bounds A31 must hold) |
| A9 | Maintaining band 0.05 kg/wk | **K** (product rounding choice, applied after publication) |
| A10 | ±1.5 kg/wk clamp | **K** (safety net; should never bind — add MC assert it binds <0.1%) |
| A11 | Sparse-logger span rules, 45d lookback | **N/T** (filter consumes any cadence; keep the three sparse tests as acceptance) |
| A12 | energySignalConflicts | **S** (CI widening subsumes it; keep the field-pair test — new engine must render soft on that data) |
| A13 | raw transparency fields | **K** (raw = unpublished rate state) |
| A14 | insufficient-data placeholder contract | **K** (CI too wide OR <14d span → same placeholder semantics) |
| A15 | 7700 kcal/kg | **K** (pragmatic constant per Hall; two-compartment only if composition-aware projections ever wanted) |
| A16 | changes measured on trend ±3d | **K** (report from filtered w) |
| A17 | 30d projection guards | **K** (project state; nil rules unchanged) |
| A18 | median() total guard | **K** |
| A19–A21 | TDEE base/activity/blend weights | **K phase 1-2** (untouched until phase 3) |
| A22 | qualified-day rules (28d median, ≥5 days, >500) | **K** (feeds phase-3 reverse-solve unchanged) |
| A23 | ledger plausibility floor 0.9×BMR | **K verbatim** (thermodynamic distrust is model-independent) |
| A24 | recentTDEE two-track | **K** |
| A25 | adaptive TDEE disabled | **S phase 3 only** — reintroduced as weekly reverse-solve with floor + holding/updating states; explicit operator sign-off before enabling |
| A26–A29 | consistency window, AH multi-signal, cache, 1200 floor | **K** |
| A30–A32 | MC family bounds | **T** — new engine must meet EVERY bound; cycle28 <95 and AR1 <36 are explicitly expected to IMPROVE (that's half the point); lower the bounds when they do |
| A33–A38 | field/regression pins (water plunge, flat maintainer, gap+spike bulk, regime changes, stability, pathological) | **T** — run identically against the new engine |
| A39 | chart series contracts | **K** (feed filtered series into same WeightDataPoint shape) |
| C1 (#977) | three-weight-base disagreement | **fixed in phase 2**: single basis = WeightTrendService.trendWeight routed everywhere + Tier-0 guard |
| C3 | weight_trend_prediction divergent OLS | **fixed in phase 2**: tool reads the engine, thresholds unified |
| C6 | dead emaAlpha field | removed with the old engine (Codable migration note) |
| C7 | 2-pt extrapolation guard | **T** (evidence-window label must match data used) |

Method rule (decisions.md, pinned): calibrate on the REAL pinned datasets first — the t-ramp
shipped on a reconstructed dataset and was field-falsified next morning. The MC harness plus
A33–A38 real series are the gate; no engine flip on synthetic evidence alone.

## 4. Architecture

```
DriftCore/Domain/Weight/
  KalmanWeightTrend.swift      // pure filter: states, robust update, CI; no Date()/DB
  WeightTrendEngine.swift      // enum .heuristic | .kalman on AlgorithmConfig (Codable default .heuristic)
  WeightTrendCalculator.swift  // becomes the adapter: entries → engine → WeightTrend struct (same fields)
```
- Output struct `WeightTrend` unchanged → zero consumer churn (12 consumers inventoried).
- `trendIsSignificant` := CI excludes 0; ramp weight := smooth function of P(rate sign);
  `rateWindowDays` := effective evidence span (for the "based on last N days" label honesty, C7).
- Presets: responsive/default/conservative map to σ_r values calibrated so the A37 regime tests
  hold at parity or better.

## 5. Migration plan (phased, each phase shippable)

1. **P1 — engine + dual harness** (Tier-0 only): implement KalmanWeightTrend; parameterize the
   ENTIRE gold/regression/MC suite over both engines; tune Q/R until the Kalman column meets
   every A30–A38 bound (expect cycle28/AR1 to improve; document the numbers).
2. **P2 — cutover + unification**: default engine flips after P1 numbers are reviewed; dark-run
   logging of divergence (both engines computed, delta logged locally) for one build; fix #977
   single weight basis; re-route weight_trend_prediction; UI gains the CI band on the chart and
   CI-driven soft/confident presentation (replaces conflict-gate rendering).
3. **P3 — adaptive expenditure**: weekly reverse-solve (A22 inputs, A23 floor, holding/updating
   states, carry-forward on sparse weeks). Supersedes A25 with operator sign-off. Honest ±200
   kcal/day language per CALERIE.
4. **P4 — cycle-aware component** (opt-in, uses logged cycle data when present; R-inflation
   fallback without it). Success = cycle28 bound lowered from <95 to <40 or better.

Rollback: `engine=.heuristic` config flip; old code deleted only after a full release soak on P2.

## 6. Success criteria

- Net-negative code: the seven gates + their interaction surface deleted; one filter + one
  publication rule + retained product choices (bands/floors/clamps).
- Every A30–A38 bound met or beaten; cycle28 + AR1 bounds LOWERED with evidence.
- Zero consumer-visible field changes in P1/P2 except honest CI presentation.
- The 2026-07-13 field data renders as "holding steady, soft ~number" on the new engine with
  no bespoke gate involved.
