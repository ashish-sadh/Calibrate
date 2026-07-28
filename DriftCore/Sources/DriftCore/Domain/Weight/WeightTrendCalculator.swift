import Foundation

/// Pure-logic weight trend calculator. No side effects, highly testable.
///
/// Algorithm (the "heal", 2026-05-29): **smooth first, differentiate second.**
/// 1. Trend weight = time-weighted EMA of weigh-ins (water/glycogen noise absorbed).
/// 2. Weekly rate = slope of that EMA over a trailing window — stable AND
///    correctly signed, because the noise is already gone before we differentiate.
/// 3. Surplus/deficit = rate × energy-density (7700 kcal/kg), clamped to a
///    physiologically sane band so sparse/noisy data can never imply a 4000-kcal
///    swing.
///
/// This replaced a six-layer heuristic stack (two-window median endpoints on RAW
/// weights → adaptive window-widening → regime-gap clipping → sign-flip guards)
/// that let a single recent water-weight dip flip the sign — the root cause of
/// "shows a deficit while the user is gaining".
public enum WeightTrendCalculator {

    // MARK: - Configuration

    /// Tunable algorithm parameters. Deliberately small — smoothing happens once,
    /// up front, so the old noise-fighting knobs (widen thresholds, regime gaps)
    /// are gone.
    public struct AlgorithmConfig: Codable, Sendable {
        /// Time-weighted EMA half-life in days. After this many days an entry's
        /// contribution decays by 50%. Time-weighted (not entry-indexed) so a
        /// daily and a weekly weigher with the same real trajectory get the same
        /// Trend Weight.
        public var emaHalfLifeDays: Double

        /// Trailing window (days) over which the weekly rate is measured as the
        /// slope of the EMA trend.
        public var regressionWindowDays: Int

        /// Energy density of body-weight change, kcal per kg. Standard physiology
        /// value (≈3500 kcal/lb; adipose ≈ 0.87 × 9000). A fixed constant is fine:
        /// the adaptive expenditure loop absorbs per-individual body-composition
        /// error week over week.
        public var kcalPerKg: Double

        /// Weekly rate (kg/wk) below which the trend is classified "maintaining".
        public var maintainingThresholdKgPerWeek: Double

        /// Legacy field retained for Codable compatibility + the AlgorithmSettings
        /// preview slider. Not consumed by the calculator (the EMA uses
        /// `emaHalfLifeDays`, a time-weighted parameterization).
        public var emaAlpha: Double

        /// Which rate estimator runs inside the protective layers (estimation
        /// unification P1, 2026-07-13). `.kalman` = local-linear-trend filter
        /// with posterior-CI confidence; `.heuristic` = the 8d-resmooth OLS +
        /// Mann–Kendall stack, kept as the rollback/fallback engine. The
        /// layers around the estimator (outlier pre-filter, display EMA,
        /// evidence bound, insufficiency, maintaining band, clamp, conflict
        /// gate) are engine-independent.
        public enum Engine: String, Codable, Sendable {
            case heuristic, kalman
        }
        public var engine: Engine

        init(
            emaHalfLifeDays: Double,
            regressionWindowDays: Int,
            kcalPerKg: Double,
            maintainingThresholdKgPerWeek: Double,
            emaAlpha: Double = 0.1,
            engine: Engine = .heuristic
        ) {
            self.emaHalfLifeDays = emaHalfLifeDays
            self.regressionWindowDays = regressionWindowDays
            self.kcalPerKg = kcalPerKg
            self.maintainingThresholdKgPerWeek = maintainingThresholdKgPerWeek
            self.emaAlpha = emaAlpha
            self.engine = engine
        }

        // Custom Codable: configs persisted before the `engine` field decode
        // with the current default instead of failing.
        private enum CodingKeys: String, CodingKey {
            case emaHalfLifeDays, regressionWindowDays, kcalPerKg,
                 maintainingThresholdKgPerWeek, emaAlpha, engine
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            emaHalfLifeDays = try c.decode(Double.self, forKey: .emaHalfLifeDays)
            regressionWindowDays = try c.decode(Int.self, forKey: .regressionWindowDays)
            kcalPerKg = try c.decode(Double.self, forKey: .kcalPerKg)
            maintainingThresholdKgPerWeek = try c.decode(Double.self, forKey: .maintainingThresholdKgPerWeek)
            emaAlpha = try c.decodeIfPresent(Double.self, forKey: .emaAlpha) ?? 0.1
            engine = try c.decodeIfPresent(Engine.self, forKey: .engine) ?? .heuristic
        }

        public static let `default` = AlgorithmConfig(
            emaHalfLifeDays: 14,
            regressionWindowDays: 21,
            kcalPerKg: 7700,
            maintainingThresholdKgPerWeek: 0.05
        )

        public static let conservative = AlgorithmConfig(
            emaHalfLifeDays: 21,
            regressionWindowDays: 28,
            kcalPerKg: 7700,
            maintainingThresholdKgPerWeek: 0.05
        )

        public static let responsive = AlgorithmConfig(
            emaHalfLifeDays: 7,
            regressionWindowDays: 14,
            kcalPerKg: 7700,
            maintainingThresholdKgPerWeek: 0.05
        )
    }

    /// Hard clamp on the trend weekly rate (kg/wk). ±1.5 kg/wk (~3.3 lb/wk) is an
    /// extreme, rarely-sustained real-world rate; beyond it the input is noise or
    /// a sparse-data artefact. Clamping keeps the implied daily energy balance
    /// sane (≤ ~1650 kcal) — no 4000-kcal surplus from one bad weigh-in.
    public static let maxAbsWeeklyRateKg: Double = 1.5

    /// Largest lookback (days) the rate will reach to find enough signal for a
    /// sparse logger. Past this, older weigh-ins are stale and must not anchor the
    /// slope (issue #842, "stale-data dominance").
    static let maxRateLookbackDays = 45

    /// Minimum span (days) of weigh-ins required before publishing a rate. Below
    /// this the regression is more noise than trend. Span-based (not count-based)
    /// so a fortnightly logger qualifies as soon as two weigh-ins are ≥14d apart
    /// (issue #842, "sparse-logger lag").
    static let minRateSpanDays = 14

    /// A gap strictly greater than this (days) between consecutive weigh-ins
    /// restarts the EMA from the fresh reading — the prior trend is stale and
    /// must not bleed across the pause. 14 keeps fortnightly weighers smoothing
    /// (their 14-day cadence is not > 14) while resetting genuine absences.
    static let emaResetGapDays = 14

    /// Minimum entries before the median-relative outlier test is trusted. At
    /// two points the median IS one of them, so the other is scored against
    /// its partner and any honest pair differing by >~18% loses a point
    /// (2026-07-28 field report). Four is the smallest set where the median
    /// survives one bad reading.
    static let minEntriesForRelativeOutlier = 4

    /// Deviation from the median that is implausible for a HUMAN body weight
    /// regardless of gap or sample size (a 6.5 kg or 30 kg reading next to
    /// 80 kg is a typo or a unit slip, never a real weigh-in).
    static let absurdDeviationCap = 0.50

    /// Half-life (days) of the smoothing applied before the rate's OLS slope.
    /// 2026-07-07 recalibration: 5 → 8. At 5d a single bulk-start week read
    /// +0.57 kg/wk (+622 kcal/day) — a real gain, but overshot vs the ~0.38
    /// the smoothed trend supports (operator: "too much"). At the display
    /// EMA's 14d the SIGN stayed wrong for 3+ weeks after a regime change
    /// (the "+1.2 lbs but −213 deficit" class of bug — regimeChange_* tests).
    /// 8d damps spike/step overshoot meaningfully while a genuine reversal
    /// still flips the reported sign within ~1-1.5 weeks.
    static let rateSmoothingHalfLifeDays: Double = 8

    /// The rate is published scaled by a RAMP on the Mann–Kendall Z of the
    /// raw weigh-ins (see `trendZStatistic`): weight 0 at `reportRampStartZ`,
    /// full at `reportRampFullZ`. Below the ramp the slope's sign is set by
    /// which noisy endpoints the window caught — publishing it recreates the
    /// 2026-05-29 field bug (flat ±3 lb oscillator shown "Est. Deficit −248"
    /// / "Est. Surplus +185" depending on window). A ramp rather than a hard
    /// bar so one new weigh-in near the boundary can't flip the card between
    /// 0 and full value (the "changes constantly" complaint).
    ///
    /// Calibration (2026-07-08, measured on the pinned datasets — replaces
    /// the OLS-t gate, whose spike/gap fragility zeroed a REAL field trend
    /// at t=0.96 while pure noise reached t=0.89):
    ///   pure-noise seeds Z = 0.33–1.00 · the May flat-noisy user Z = 0.34 ·
    ///   the 2026-07-08 real bulk (9 points, one water spike, a 10-day
    ///   logging gap) Z = 1.68 · gentle-drift/established trends Z = 2.6–6.3
    ///   · weekly sparse logger Z = 2.6. The 1.15–1.65 ramp sits in the
    ///   empirical gap: noise stays zeroed, a genuine young trend gets
    ///   REPORTED (operator decision: "it's fine to report surplus — don't
    ///   say holding steady under a climbing chart").
    static let reportRampStartZ: Double = 1.15
    static let reportRampFullZ: Double = 1.65

    /// The stricter bar at which the trend is flagged CONFIDENT
    /// (`trendIsSignificant`). Between the ramp and this, the rate is shown
    /// with "Early trend — firming up" framing; above it, "Based on last N
    /// days".
    static let significanceZThreshold: Double = 2.0

    /// Kalman-engine publication ramp (estimation unification P1,
    /// 2026-07-13). The posterior z = |rate|/std lives on a different scale
    /// than Mann–Kendall Z — probe measurements with the default filter
    /// config: flat noise ≈ 0.4, sparse/weekly real trends ≈ 0.75–0.85,
    /// 10-day regime change ≈ 0.95, steady 0.35 kg/wk ≈ 1.2. Calibrated so
    /// the pinned gold scenarios publish and the Monte-Carlo flat families
    /// hold their phantom bounds; recalibrate ONLY with both suites green.
    static let kalmanRampStartZ = 0.65
    static let kalmanRampFullZ = 0.95
    static let kalmanSignificanceZ = 1.15

    /// Escalation window for SLOW trends (operator directive 2026-07-08:
    /// "Holding steady should be rare"). A real 0.15–0.3 kg/wk trend often
    /// can't clear the report ramp on 21 days of noisy points — but it can
    /// on a longer window (more Mann–Kendall pairs = more power, and for a
    /// SUSTAINED slow trend the older points are still representative).
    /// Escalation is guarded (see calculateTrend): only when the recent
    /// window itself shows an above-band slope of the SAME sign — recent
    /// flatness is affirmative evidence of maintaining and must never be
    /// overridden by stale history (#842 / regimeChange_recentMaintenance).
    static let slowTrendWindowDays = 35

    /// Minimum raw weigh-ins in the window before the trend test can even be
    /// assessed. With ≤3 points there are too few pairs for Mann–Kendall to
    /// mean anything; treat as not-reportable → maintaining.
    static let minPointsForSignificance = 4

    // MARK: - Public Types

    public struct WeightTrend: Sendable {
        public let currentEMA: Double
        public let previousEMA: Double
        public let weeklyRateKg: Double
        public let estimatedDailyDeficit: Double
        public let trendDirection: TrendDirection
        public let projection30Day: Double?
        public let dataPoints: [WeightDataPoint]
        public let weightChanges: WeightChanges
        public let config: AlgorithmConfig
        /// Actual window (days) used to compute weeklyRateKg — may exceed
        /// config.regressionWindowDays when the sparse-logger lookback widens it.
        public let rateWindowDays: Int
        /// True when there aren't enough weigh-ins for a trustworthy rate. In that
        /// case `weeklyRateKg`/`estimatedDailyDeficit` are 0; the UI must render
        /// "—" / a "calibrating" state instead of the value.
        public let hasInsufficientData: Bool

        /// The pre-band weekly rate (kg/wk): the clamped EMA slope BEFORE the
        /// maintaining-band collapse zeroes tiny values. Display transparency
        /// (field ask 2026-07-07: "say whatever number it is — don't hide the
        /// math"). 0 when calibrating.
        public let rawWeeklyRateKg: Double

        /// Daily energy balance implied by the pre-band rate — same
        /// transparency caveat as `rawWeeklyRateKg`.
        public var rawEstimatedDailyDeficit: Double { rawWeeklyRateKg * config.kcalPerKg / 7 }

        /// Weekly rate (kg/wk) measured over the wide 35-day window
        /// (`slowTrendWindowDays`) — the second opinion the conflict gate
        /// checks the published short-window rate against. nil when the wide
        /// window lacks sufficient span.
        public let longWindowWeeklyRateKg: Double?

        /// True when the short-window energy estimate disagrees in SIGN with
        /// the longer-horizon picture. Two triggers:
        ///
        /// 1. The 30-day EMA trend change points the other way — e.g.
        ///    "Est. Deficit −170/day" printed next to "30-day +1.0 lbs
        ///    Increase" (field report 2026-07-13: a 5-day water plunge bent
        ///    the 20-day slope negative on a body that gained over the month).
        ///    The 0.15 kg dead-band keeps a young-but-real trend (30-day near
        ///    zero) publishing normally.
        /// 2. The 35-day window slope points the other way at above-band
        ///    magnitude (field report 2026-07-17: a week-long water/refeed
        ///    rise on a steadily-losing body read "Est. Surplus +204,
        ///    confident" while the reference app showed a deficit — the
        ///    30-day EMA delta sat inside the dead-band because the rise
        ///    itself dragged the current EMA up, so trigger 1 missed it).
        ///
        /// The UI renders the soft gray treatment instead of goal-colored
        /// confidence while the signals argue; a genuine regime change clears
        /// as the wide window's slope rolls over (probe 2026-07-17: a real
        /// bulk's 35-day slope flips sign by the time the short rate does).
        public var energySignalConflicts: Bool {
            guard weeklyRateKg != 0 else { return false }
            if let thirtyDay = weightChanges.thirtyDay {
                let deadbandKg = 0.15
                if (weeklyRateKg < 0 && thirtyDay > deadbandKg)
                    || (weeklyRateKg > 0 && thirtyDay < -deadbandKg) { return true }
            }
            if let long = longWindowWeeklyRateKg,
               abs(long) >= config.maintainingThresholdKgPerWeek,
               (long > 0) != (weeklyRateKg > 0) { return true }
            return false
        }

        /// True when the raw weigh-ins' slope clears the statistical noise
        /// threshold. Since 2026-07-07 this is a CONFIDENCE hint for the UI
        /// ("early trend" vs "based on last N days") — it no longer zeroes
        /// the published rate.
        public let trendIsSignificant: Bool

        init(currentEMA: Double, previousEMA: Double, weeklyRateKg: Double, estimatedDailyDeficit: Double, trendDirection: TrendDirection, projection30Day: Double?, dataPoints: [WeightDataPoint], weightChanges: WeightChanges, config: AlgorithmConfig, rateWindowDays: Int, hasInsufficientData: Bool = false, rawWeeklyRateKg: Double = 0, trendIsSignificant: Bool = false, longWindowWeeklyRateKg: Double? = nil) {
            self.currentEMA = currentEMA
            self.previousEMA = previousEMA
            self.weeklyRateKg = weeklyRateKg
            self.estimatedDailyDeficit = estimatedDailyDeficit
            self.trendDirection = trendDirection
            self.projection30Day = projection30Day
            self.dataPoints = dataPoints
            self.weightChanges = weightChanges
            self.config = config
            self.rateWindowDays = rateWindowDays
            self.hasInsufficientData = hasInsufficientData
            self.rawWeeklyRateKg = rawWeeklyRateKg
            self.trendIsSignificant = trendIsSignificant
            self.longWindowWeeklyRateKg = longWindowWeeklyRateKg
        }
    }

    public struct WeightDataPoint: Sendable {
        public let date: Date
        public let dateString: String
        public let actualWeight: Double?
        public let emaWeight: Double

        init(date: Date, dateString: String, actualWeight: Double?, emaWeight: Double) {
            self.date = date
            self.dateString = dateString
            self.actualWeight = actualWeight
            self.emaWeight = emaWeight
        }
    }

    public struct WeightChanges: Sendable {
        public let threeDay: Double?
        public let sevenDay: Double?
        public let fourteenDay: Double?
        public let thirtyDay: Double?
        public let ninetyDay: Double?

        init(threeDay: Double?, sevenDay: Double?, fourteenDay: Double?, thirtyDay: Double?, ninetyDay: Double?) {
            self.threeDay = threeDay
            self.sevenDay = sevenDay
            self.fourteenDay = fourteenDay
            self.thirtyDay = thirtyDay
            self.ninetyDay = ninetyDay
        }
    }

    public enum TrendDirection: Sendable {
        case losing, maintaining, gaining

        public var displayText: String {
            switch self {
            case .losing: "Decrease"
            case .maintaining: "Stable"
            case .gaining: "Increase"
            }
        }

        public var systemImage: String {
            switch self {
            case .losing: "arrow.down.right"
            case .maintaining: "arrow.right"
            case .gaining: "arrow.up.right"
            }
        }
    }

    // MARK: - Core Calculation

    public static func calculateTrend(
        entries: [(date: String, weightKg: Double)],
        config: AlgorithmConfig = loadConfig()
    ) -> WeightTrend? {
        guard !entries.isEmpty else { return nil }

        let sorted = entries
            .compactMap { entry -> (date: Date, dateString: String, weight: Double)? in
                // DateFormatters.dateOnly pins the local time zone — an ad-hoc
                // DateFormatter() here defaults to UTC on Android (Foundation
                // difference from Apple platforms), so every date-only round
                // trip lost a day west of UTC (#1092: chart date labels read
                // one day early).
                guard let date = DateFormatters.dateOnly.date(from: entry.date), entry.weightKg > 0 else { return nil }
                return (date, entry.date, entry.weightKg)
            }
            .sorted { $0.date < $1.date }

        guard !sorted.isEmpty else { return nil }

        // Outlier removal: gap-aware threshold (allows more deviation after long gaps).
        let weights = sorted.map(\.weight)
        let med = weights.sorted()[weights.count / 2]
        // Below `minEntriesForRelativeOutlier` the median is degenerate — with
        // two entries it IS one of them, so the other is scored against its
        // partner and any honest pair differing by >15-18% loses a point. Field
        // report 2026-07-28: weights 9 days apart (56.0 → 72.6 kg) collapsed to
        // ONE data point, so the chart (which needs 2) vanished entirely. For
        // small sets only the absurd-value cap applies — a 6.5 kg or 30 kg typo
        // is still implausible on its face, without a trustworthy median.
        let relativeFilterTrustworthy = sorted.count >= Self.minEntriesForRelativeOutlier
        let filtered = sorted.filter { entry in
            let deviation = abs(entry.weight - med) / med
            guard relativeFilterTrustworthy else { return deviation <= Self.absurdDeviationCap }
            let gapDays = sorted.compactMap { other -> Int? in
                guard other.date != entry.date else { return nil }
                return abs(Calendar.current.dateComponents([.day], from: entry.date, to: other.date).day ?? 0)
            }.min() ?? 0
            let gapAllowance = (Double(gapDays) / 7.0) * (1.5 / med)
            let threshold = min(0.15 + gapAllowance, Self.absurdDeviationCap)
            return deviation <= threshold
        }
        guard !filtered.isEmpty else { return nil }

        // Time-weighted EMA: decay depends on elapsed days between entries, not on
        // entry count — a weekly and a daily weigher with the same trajectory get
        // the same Trend Weight.
        var dataPoints: [WeightDataPoint] = []
        var ema = filtered[0].weight
        var prevDate = filtered[0].date
        dataPoints.append(WeightDataPoint(date: filtered[0].date, dateString: filtered[0].dateString, actualWeight: filtered[0].weight, emaWeight: ema))
        for entry in filtered.dropFirst() {
            let deltaDays = max(1.0, Double(Calendar.current.dateComponents([.day], from: prevDate, to: entry.date).day ?? 1))
            if deltaDays > Double(Self.emaResetGapDays) {
                // Long gap → the prior trend is stale. Restart smoothing from the
                // fresh weigh-in instead of letting a pre-gap weight bleed forward
                // (standard practice: a post-absence reading is a fresh, low-
                // confidence start). Without this, a drop-then-pause-then-flat
                // pattern reads as an ongoing loss — issue #842 "stale-data
                // dominance" and the deficit-while-flat case.
                ema = entry.weight
            } else {
                // alpha = 1 - (1/2)^(Δt / halfLife): at Δt = halfLife the new entry
                // contributes 50% and the prior EMA 50%.
                let alpha = 1.0 - pow(0.5, deltaDays / config.emaHalfLifeDays)
                ema = alpha * entry.weight + (1 - alpha) * ema
            }
            dataPoints.append(WeightDataPoint(date: entry.date, dateString: entry.dateString, actualWeight: entry.weight, emaWeight: ema))
            prevDate = entry.date
        }

        guard let lastPoint = dataPoints.last else { return nil }
        let currentEMA = lastPoint.emaWeight
        let previousEMA = dataPoints.count >= 2 ? dataPoints[dataPoints.count - 2].emaWeight : currentEMA

        // ── Weekly rate = OLS slope of the medium-smoothed (8d) series over
        // the trailing window, published on a TWO-TIER Mann–Kendall test
        // (2026-07-08 recalibration of the 2026-05-29 gate):
        //   Z below the 1.15–1.65 ramp  → pure oscillation; publish 0 /
        //     maintaining (the May phantom-deficit fix, unchanged in spirit)
        //   inside the ramp             → real-but-young trend fades in,
        //     scaled by confidence (no hard boundary to flap across)
        //   Z ≥ significanceZThreshold  → full value, confident framing.
        var rate: (kgPerWeek: Double, windowDays: Int, zStat: Double)?
        let engineRampFull: Double
        switch config.engine {
        case .kalman:
            // Estimation-unification engine (P1): local-linear-trend Kalman
            // over the same 45d evidence bound; recency weighting is
            // intrinsic (rate time-constant ≈ 6–7d), confidence
            // z = |rate|/posteriorStd feeds the engine-calibrated ramp below.
            // No re-smooth, no spike seed — those were OLS compensations.
            rate = kalmanRateForWindow(points: dataPoints)
            engineRampFull = Self.kalmanRampFullZ
        case .heuristic:
            rate = weeklyRateForWindow(points: dataPoints, windowDays: config.regressionWindowDays)
            engineRampFull = Self.reportRampFullZ
        }
        // Slow-trend escalation — a PROTECTIVE LAYER shared by both engines
        // (operator 2026-07-13: keep the learned fallbacks around the simpler
        // core). A genuine 0.1–0.35 kg/wk trend is below any short-window
        // estimator's confidence floor; the 35d Mann–Kendall window certifies
        // it (more pairs = more power) when it is CONFIDENT (Z≥2.0 — flatNoise
        // seed 99 reaches 1.7 by chance) and agrees in sign. Recent-flat
        // (sub-band) never escalates: recent flat is affirmative evidence of
        // maintaining (#842 / regimeChange_recentMaintenance).
        // The wide-window second opinion, computed once: feeds slow-trend
        // escalation below AND the conflict gate's trigger 2
        // (`longWindowWeeklyRateKg`).
        let wide = weeklyRateForWindow(points: dataPoints, windowDays: Self.slowTrendWindowDays)
        if let p = rate, p.zStat < engineRampFull,
           abs(p.kgPerWeek) >= config.maintainingThresholdKgPerWeek,
           let wide,
           wide.zStat >= Self.significanceZThreshold,
           (wide.kgPerWeek > 0) == (p.kgPerWeek > 0) {
            // The certified rate carries MK confidence (Z≥2.0 > both engines'
            // full-ramp constants) — publishes at full weight either way.
            rate = (wide.kgPerWeek, wide.windowDays, wide.zStat)
        }
        let hasInsufficientData = (rate == nil)
        let rawRate = clampRate(rate?.kgPerWeek ?? 0)
        let zStat = rate?.zStat ?? 0
        // The ramp is engine-calibrated: Mann–Kendall Z and a Kalman
        // posterior z are different statistics on different scales (probe
        // 2026-07-13: real trends land ~1.7–2.6 on MK, ~0.75–1.15 on the
        // posterior). Same ramp semantics, engine-specific constants.
        let (rampStart, rampFull, significanceZ) = config.engine == .kalman
            ? (Self.kalmanRampStartZ, Self.kalmanRampFullZ, Self.kalmanSignificanceZ)
            : (Self.reportRampStartZ, Self.reportRampFullZ, Self.significanceZThreshold)
        let rampWeight = min(1, max(0, (zStat - rampStart) / (rampFull - rampStart)))
        let reportedRate = rawRate * rampWeight
        // Below the maintaining band ⇒ report exactly flat (rate 0): a slope
        // that tiny is "holding steady", and a non-zero deficit beside a
        // "maintaining" label only confuses.
        let weeklyRateKg = abs(reportedRate) < config.maintainingThresholdKgPerWeek ? 0 : reportedRate
        let rateWindowDays = rate?.windowDays ?? config.regressionWindowDays
        let estimatedDailyDeficit = weeklyRateKg * config.kcalPerKg / 7

        let trendDirection: TrendDirection
        if weeklyRateKg < -config.maintainingThresholdKgPerWeek {
            trendDirection = .losing
        } else if weeklyRateKg > config.maintainingThresholdKgPerWeek {
            trendDirection = .gaining
        } else {
            trendDirection = .maintaining
        }

        // Project from the smooth trend, not the noisy latest scale reading, and
        // never from a placeholder rate.
        let projection30Day: Double? = (!hasInsufficientData && dataPoints.count >= 2)
            ? currentEMA + (weeklyRateKg / 7 * 30)
            : nil

        return WeightTrend(
            currentEMA: currentEMA,
            previousEMA: previousEMA,
            weeklyRateKg: weeklyRateKg,
            estimatedDailyDeficit: estimatedDailyDeficit,
            trendDirection: trendDirection,
            projection30Day: projection30Day,
            dataPoints: dataPoints,
            weightChanges: calculateWeightChanges(dataPoints: dataPoints),
            config: config,
            rateWindowDays: rateWindowDays,
            hasInsufficientData: hasInsufficientData,
            rawWeeklyRateKg: rawRate,
            trendIsSignificant: zStat >= significanceZ,
            longWindowWeeklyRateKg: wide.map { clampRate($0.kgPerWeek) }
        )
    }

    // MARK: - Rate (slope of the smooth trend)

    /// Clamp a weekly rate (kg/wk) to the physiologically sane band.
    static func clampRate(_ kgPerWeek: Double) -> Double {
        min(maxAbsWeeklyRateKg, max(-maxAbsWeeklyRateKg, kgPerWeek))
    }

    /// Weekly rate (kg/wk) = OLS slope of a MEDIUM-smoothed series over the
    /// trailing window, plus the span used (for the UI's "based on last N days"
    /// label).
    ///
    /// 2026-07-07 operator decision: the rate is ALWAYS reported (the old
    /// significance gate zeroed it to "holding steady" next to a visibly
    /// climbing chart — read as the app hiding the math). The noise defense
    /// is the smoothing weight, recalibrated 5d → 8d (see
    /// `rateSmoothingHalfLifeDays`): heavy enough that a water spike or a
    /// bulk-start step doesn't balloon the number, light enough that a
    /// genuine reversal flips the sign within ~1-1.5 weeks (the full 14d
    /// display EMA kept the WRONG sign for 3+ weeks after a regime change —
    /// the "+1.2 lbs but −213 deficit" bug class, pinned by regimeChange_*).
    /// Significance survives only as the `significant` confidence flag.
    ///
    /// Extends the lookback up to `maxRateLookbackDays` for sparse loggers so a
    /// weekly/fortnightly weigher still gets a rate — but never past it, so stale
    /// weigh-ins can't anchor the slope (#842). Sparse cadences stay safe because
    /// the smoothing is time-weighted (decay by elapsed days).
    static func weeklyRateForWindow(points: [WeightDataPoint], windowDays: Int) -> (kgPerWeek: Double, windowDays: Int, zStat: Double)? {
        func windowed(_ days: Int) -> [WeightDataPoint] {
            guard let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return [] }
            return points.filter { $0.date >= start }
        }
        var pts = windowed(windowDays)
        var used = windowDays
        if !isSufficient(pts) {
            pts = windowed(maxRateLookbackDays)
            used = maxRateLookbackDays
        }
        guard isSufficient(pts), let first = pts.first, let last = pts.last else { return nil }

        // Medium re-smoothing for the slope: a time-weighted EMA
        // (`rateSmoothingHalfLifeDays`) over the window's actual weights,
        // then OLS on the smoothed series.
        //
        // Spike-proof the smoother's seed: when the window's opening weigh-in
        // is an OUTLIER against its first-5 cohort (>0.75 kg — a water spike,
        // not day-to-day noise), seed with the cohort median instead. A
        // single-point seed anchored the whole smoothed series on the spike
        // and every estimator read "fell from the spike" ≈ −400 kcal/day
        // (field scenario 2026-07-13: the Jun 23 56.1 spike was day 1 of the
        // 21-day window). Conditional on purpose — an unconditional median
        // seed nudged the cycle28 Monte-Carlo family over its phantom bound
        // (95.8% vs <95); normal openings keep the exact tuned baseline.
        let openers = pts.prefix(5).map { $0.actualWeight ?? $0.emaWeight }
        let firstY = pts[0].actualWeight ?? pts[0].emaWeight
        let openerMedian = median(of: openers)
        var smoothed: [(date: Date, weight: Double)] = []
        var s = abs(firstY - openerMedian) > 0.75 ? openerMedian : firstY
        var prev = pts[0].date
        smoothed.append((pts[0].date, s))
        for p in pts.dropFirst() {
            let y = p.actualWeight ?? p.emaWeight
            let deltaDays = max(1.0, Double(daysBetween(prev, p.date)))
            let alpha = 1.0 - pow(0.5, deltaDays / rateSmoothingHalfLifeDays)
            s = alpha * y + (1 - alpha) * s
            smoothed.append((p.date, s))
            prev = p.date
        }
        let slopePerDay = slopeOfSeries(smoothed)
        let span = max(1, daysBetween(first.date, last.date))
        // The Z-statistic is judged on the RAW weigh-ins of the SAME window
        // the magnitude uses — a smoothed series' autocorrelation fakes
        // confidence on genuinely flat data.
        return (slopePerDay * 7, min(used, span), trendZStatistic(pts))
    }

    /// Kalman-engine rate: run the local-linear-trend filter over the same
    /// 45-day evidence bound the heuristic uses (stale weigh-ins can't anchor
    /// the rate either way, #842 — a protective layer, not an estimator
    /// choice), with the same span-based sufficiency contract. `zStat` is the
    /// posterior confidence |rate|/std, consumed by the identical publication
    /// ramp downstream.
    static func kalmanRateForWindow(
        points: [WeightDataPoint],
        config: KalmanWeightTrend.Config = .default
    ) -> (kgPerWeek: Double, windowDays: Int, zStat: Double)? {
        guard let start = Calendar.current.date(byAdding: .day, value: -maxRateLookbackDays, to: Date()) else { return nil }
        let pts = points.filter { $0.date >= start }
        guard isSufficient(pts), let first = pts.first, let last = pts.last else { return nil }
        let observations = pts.map { (date: $0.date, weightKg: $0.actualWeight ?? $0.emaWeight) }
        guard let out = KalmanWeightTrend.run(observations: observations, config: config) else { return nil }
        let span = max(1, daysBetween(first.date, last.date))
        return (out.weeklyRateKg, min(maxRateLookbackDays, span), out.rateZ)
    }

    /// How statistically distinguishable from flat is the trailing trend?
    /// Mann–Kendall Z on the raw weigh-ins: counts concordant vs discordant
    /// pairs (does each later reading sit above each earlier one?) instead
    /// of fitting a line. Rank-based, so it is robust to exactly the two
    /// shapes OLS-t failed on in the field (2026-07-08): a single water
    /// spike (one huge squared residual craters R²) and a logging gap
    /// (thin points inflate the slope's standard error). A real-but-young
    /// bulk with a spike + 10-day gap scored t≈0.96 (indistinguishable from
    /// the 0.89 noise ceiling) but MK Z≈1.67 — cleanly separated.
    /// 0 when there are too few points (the caller's report ramp then keeps
    /// the rate unpublished). Ties count 0 and shrink the variance term.
    static func trendZStatistic(_ points: [WeightDataPoint]) -> Double {
        let ys = points.map { $0.actualWeight ?? $0.emaWeight }
        let n = ys.count
        guard n >= minPointsForSignificance else { return 0 }

        var s = 0
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                let d = ys[j] - ys[i]
                if d > 0 { s += 1 } else if d < 0 { s -= 1 }
            }
        }

        // Variance with tie correction: group identical values, subtract
        // t(t-1)(2t+5)/18 per tie group of size t.
        var variance = Double(n * (n - 1) * (2 * n + 5)) / 18.0
        var counts: [Double: Int] = [:]
        for y in ys { counts[y, default: 0] += 1 }
        for (_, t) in counts where t > 1 {
            variance -= Double(t * (t - 1) * (2 * t + 5)) / 18.0
        }
        guard variance > 0 else { return 0 }

        // Continuity correction (±1) — standard for the normal approximation.
        let sAdj = s > 0 ? Double(s) - 1 : (s < 0 ? Double(s) + 1 : 0)
        return abs(sAdj) / variance.squareRoot()
    }

    /// Span-based sufficiency: ≥2 points spanning ≥ `minRateSpanDays` — OR a
    /// DENSE short run (≥6 points spanning ≥10 days). The span floor exists
    /// for sparse loggers (#842: two weigh-ins 5 days apart are noise, not a
    /// trend); a 9-point 12-day run is statistically rich. Without the dense
    /// branch, a 10-day logging gap before a regime change left the 21-day
    /// window 2 days short of span, and the fallback widened straight to 45
    /// days — burying the operator's real 3-week cut under the prior bulk's
    /// climb (field 2026-07-17: reference app −0.15 kg/wk / −165 kcal vs
    /// Drift "+0.09 gaining" from the 45d window).
    static func isSufficient(_ points: [WeightDataPoint]) -> Bool {
        guard points.count >= 2, let f = points.first, let l = points.last else { return false }
        let span = daysBetween(f.date, l.date)
        if span >= minRateSpanDays { return true }
        return points.count >= 6 && span >= 10
    }

    // MARK: - Linear Regression

    /// OLS slope (per day) over (date, weight) pairs.
    static func slopeOfSeries(_ samples: [(date: Date, weight: Double)]) -> Double {
        guard samples.count >= 2 else { return 0 }
        let referenceDate = samples[0].date
        let n = Double(samples.count)
        var sumX: Double = 0, sumY: Double = 0, sumXY: Double = 0, sumX2: Double = 0
        for s in samples {
            let x = Double(Calendar.current.dateComponents([.day], from: referenceDate, to: s.date).day ?? 0)
            let y = s.weight
            sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x
        }
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return 0 }
        return (n * sumXY - sumX * sumY) / denominator
    }

    /// Slope (kg/day) of the EMA-smoothed series. This IS the production rate
    /// source now (× 7 = kg/wk). Public for the algorithm-preview tool + tests.
    public static func linearRegressionSlope(points: [WeightDataPoint]) -> Double {
        slopeOfSeries(points.map { (date: $0.date, weight: $0.emaWeight) })
    }


    /// Median of a numeric array. For even-count, mean of the two middle elements.
    static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        // Crash-audit (cycle 13107): empty input → n = 0 → the even-count branch
        // evaluates `sorted[n/2 - 1]` = `sorted[-1]`, an out-of-bounds trap. No
        // production path passes empty today (the only callers are tests), but the
        // guard makes the helper total so a future caller can't reintroduce the trap.
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    /// Whole-day count between two dates (positive when `b` is after `a`).
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Weight Changes

    /// Change over each horizon measured on the smoothed TREND (EMA), not raw
    /// scale weight. A raw "today vs N-days-ago" delta compares two single noisy
    /// readings — a 120.5 high today vs a 115.2 dip 30 days ago reads "+5.3" of
    /// mostly water — which contradicts the "Holding steady" trend verdict shown
    /// on the same screen. The EMA delta is the honest movement of the trend line
    /// (and matches the chart's trend-based Difference). The raw ups/downs are
    /// still visible as the actual line on the chart.
    public static func calculateWeightChanges(dataPoints: [WeightDataPoint]) -> WeightChanges {
        guard let latest = dataPoints.last else {
            return WeightChanges(threeDay: nil, sevenDay: nil, fourteenDay: nil, thirtyDay: nil, ninetyDay: nil)
        }
        let latestTrend = latest.emaWeight

        func changeOverDays(_ days: Int) -> Double? {
            guard let target = Calendar.current.date(byAdding: .day, value: -days, to: latest.date) else { return nil }
            let closest = dataPoints.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
            guard let closest, closest.date != latest.date else { return nil }
            let daysDiff = abs(Calendar.current.dateComponents([.day], from: closest.date, to: target).day ?? 0)
            guard daysDiff <= 3 else { return nil }
            return latestTrend - closest.emaWeight
        }

        return WeightChanges(
            threeDay: changeOverDays(3), sevenDay: changeOverDays(7),
            fourteenDay: changeOverDays(14), thirtyDay: changeOverDays(30),
            ninetyDay: changeOverDays(90)
        )
    }

    // MARK: - Config Persistence

    private static let configKey = "drift_algorithm_config"

    public static func loadConfig() -> AlgorithmConfig {
        guard let data = DriftPlatform.keyValueStore.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AlgorithmConfig.self, from: data) else {
            return .default
        }
        return config
    }

    public static func saveConfig(_ config: AlgorithmConfig) {
        if let data = try? JSONEncoder().encode(config) {
            DriftPlatform.keyValueStore.set(data, forKey: configKey)
        }
    }
}
