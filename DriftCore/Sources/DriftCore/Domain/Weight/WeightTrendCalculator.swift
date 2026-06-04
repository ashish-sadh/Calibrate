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

        init(
            emaHalfLifeDays: Double,
            regressionWindowDays: Int,
            kcalPerKg: Double,
            maintainingThresholdKgPerWeek: Double,
            emaAlpha: Double = 0.1
        ) {
            self.emaHalfLifeDays = emaHalfLifeDays
            self.regressionWindowDays = regressionWindowDays
            self.kcalPerKg = kcalPerKg
            self.maintainingThresholdKgPerWeek = maintainingThresholdKgPerWeek
            self.emaAlpha = emaAlpha
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

    /// Half-life (days) of the LIGHT smoothing applied before the rate's OLS
    /// slope. Short enough (~5d) to follow a genuine direction change within days
    /// rather than the display EMA's ~2-week lag, long enough to damp daily
    /// water/glycogen jitter so the reported surplus/deficit stops bouncing.
    static let rateSmoothingHalfLifeDays: Double = 5

    /// |t| (slope ÷ its standard error) the trailing trend must clear before we
    /// report a *direction* at all. Below it the weight is statistically flat —
    /// the slope's sign is set by which noisy endpoints the window caught, not by
    /// real signal — so we report "maintaining" / zero energy balance instead.
    ///
    /// Field bug (2026-05-29): a user oscillating ±3 lb around a flat ~118 mean
    /// saw "Est. Deficit −248 kcal/day" on the 1M view and "Est. Surplus +185" on
    /// the 3M view — same DB, opposite signs — because each window fit a confident
    /// slope to noise (R² ≈ 0.00–0.08). Calibration: genuine cuts/bulks clear
    /// |t| ≈ 2.3–12; flat-noisy maintainers sit at 0.2–1.5. 2.0 ≈ the 95%
    /// two-sided level across the 4–40 weigh-ins a window holds — it sits in the
    /// gap between a real (if short or spiky) trend and pure noise, and biases
    /// toward honesty ("we can't call it") when the data won't support a verdict.
    static let significanceTThreshold: Double = 2.0

    /// Minimum raw weigh-ins in the window before significance can even be
    /// assessed. With ≤3 points the OLS fits (near-)perfectly by construction, so
    /// the t-test is meaningless; treat as not-significant → maintaining.
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

        init(currentEMA: Double, previousEMA: Double, weeklyRateKg: Double, estimatedDailyDeficit: Double, trendDirection: TrendDirection, projection30Day: Double?, dataPoints: [WeightDataPoint], weightChanges: WeightChanges, config: AlgorithmConfig, rateWindowDays: Int, hasInsufficientData: Bool = false) {
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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let sorted = entries
            .compactMap { entry -> (date: Date, dateString: String, weight: Double)? in
                guard let date = formatter.date(from: entry.date), entry.weightKg > 0 else { return nil }
                return (date, entry.date, entry.weightKg)
            }
            .sorted { $0.date < $1.date }

        guard !sorted.isEmpty else { return nil }

        // Outlier removal: gap-aware threshold (allows more deviation after long gaps).
        let weights = sorted.map(\.weight)
        let med = weights.sorted()[weights.count / 2]
        let filtered = sorted.filter { entry in
            let deviation = abs(entry.weight - med) / med
            let gapDays = sorted.compactMap { other -> Int? in
                guard other.date != entry.date else { return nil }
                return abs(Calendar.current.dateComponents([.day], from: entry.date, to: other.date).day ?? 0)
            }.min() ?? 0
            let gapAllowance = (Double(gapDays) / 7.0) * (1.5 / med)
            let threshold = min(0.15 + gapAllowance, 0.50)
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

        // ── Weekly rate = OLS slope over the trailing window (the heal) ──
        // Gated on statistical significance: a slope that doesn't clear the noise
        // (|t| < significanceTThreshold) is reported as flat (rate 0 → maintaining),
        // never as a confident surplus/deficit whose SIGN is decided by which
        // noisy endpoints the window happened to catch. Without this gate a
        // weight oscillating ±3 lb around a flat mean reads "Est. Deficit" on a
        // short window and "Est. Surplus" on a long one (field bug 2026-05-29).
        let rate = weeklyRateForWindow(points: dataPoints, windowDays: config.regressionWindowDays)
        let hasInsufficientData = (rate == nil)
        let significantRate = (rate?.significant == true) ? clampRate(rate?.kgPerWeek ?? 0) : 0
        // Below the maintaining band ⇒ report exactly flat (rate 0): a sub-threshold
        // slope — even a chance-significant one on pure noise — is "holding steady",
        // and a non-zero deficit beside a "maintaining" label only confuses.
        let weeklyRateKg = abs(significantRate) < config.maintainingThresholdKgPerWeek ? 0 : significantRate
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
            hasInsufficientData: hasInsufficientData
        )
    }

    // MARK: - Rate (slope of the smooth trend)

    /// Clamp a weekly rate (kg/wk) to the physiologically sane band.
    static func clampRate(_ kgPerWeek: Double) -> Double {
        min(maxAbsWeeklyRateKg, max(-maxAbsWeeklyRateKg, kgPerWeek))
    }

    /// Weekly rate (kg/wk) = OLS slope of a LIGHTLY smoothed series over the
    /// trailing window, plus the span used (for the UI's "based on last N days"
    /// label).
    ///
    /// Why a *light* (short half-life) smooth and then OLS — the stability vs
    /// responsiveness balance:
    ///  - Raw actual weights → the slope jitters day-to-day from ±1–2 kg water
    ///    noise (≈±275 kcal), which is the "surplus/deficit changes constantly"
    ///    complaint.
    ///  - The heavy display EMA (14-day) → its slope lags a genuine direction
    ///    change by ~2 weeks (it's still "catching down" from the prior regime),
    ///    reporting the OLD, now-wrong direction.
    ///  - A SHORT EMA (~`rateSmoothingHalfLifeDays`) kills the daily jitter
    ///    (≈±80 kcal) yet lags only a few days, so a real reversal still shows
    ///    through. OLS over that smoothed series is the stable-but-responsive
    ///    middle ground — one method, no fragile EMA-vs-actual mode switching.
    ///
    /// Extends the lookback up to `maxRateLookbackDays` for sparse loggers so a
    /// weekly/fortnightly weigher still gets a rate — but never past it, so stale
    /// weigh-ins can't anchor the slope (#842).
    static func weeklyRateForWindow(points: [WeightDataPoint], windowDays: Int) -> (kgPerWeek: Double, windowDays: Int, significant: Bool)? {
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

        // Light re-smoothing for the slope: a short, time-weighted EMA over the
        // window's actual weights, then OLS on the smoothed series.
        var smoothed: [(date: Date, weight: Double)] = []
        var s = pts[0].actualWeight ?? pts[0].emaWeight
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
        // Significance is judged on the RAW weigh-ins of the SAME window the
        // magnitude uses (NOT the smoothed series, NOT a wider window):
        //  • raw, because the 5d pre-smooth's autocorrelation inflates the fit and
        //    waves flat water-noise through as a false "trend" (|t| 3–11 on data
        //    that is genuinely flat).
        //  • same window, because magnitude and direction must agree in sign — a
        //    *wider* significance window let a 45d up-trend gate a 21d down-slice's
        //    magnitude and report "Est. Deficit −242" for a flat-to-up user (the
        //    field bug), and it also blinded the rate to recent regime changes the
        //    responsive window is meant to catch. Judging both on `pts` means a
        //    flat/oscillating window reads maintaining while a clear recent trend
        //    (loss or gain) still registers.
        let significant = isTrendSignificant(pts)
        return (slopePerDay * 7, min(used, span), significant)
    }

    /// Is the trailing trend statistically distinguishable from flat? Runs OLS on
    /// the raw weigh-ins and tests the slope's t-statistic,
    /// `|t| = sqrt(R²·(n-2)/(1-R²))`, against `significanceTThreshold`. False ⇒
    /// the weight is just oscillating and the slope's sign is noise; the caller
    /// reports maintaining instead of a fabricated surplus/deficit.
    static func isTrendSignificant(_ points: [WeightDataPoint]) -> Bool {
        let samples = points.map { (date: $0.date, weight: $0.actualWeight ?? $0.emaWeight) }
        guard samples.count >= minPointsForSignificance else { return false }
        let r2 = rSquared(samples)
        guard r2 < 1 else { return true }      // exact fit on ≥4 points ⇒ real line
        let n = Double(samples.count)
        let t = (r2 * (n - 2) / (1 - r2)).squareRoot()
        return t >= significanceTThreshold
    }

    /// Coefficient of determination (R²) of a least-squares line through
    /// (day-offset, weight) samples. 0 = the line explains nothing (flat noise),
    /// 1 = perfect fit. Clamped to [0, 1].
    static func rSquared(_ samples: [(date: Date, weight: Double)]) -> Double {
        guard samples.count >= 2 else { return 0 }
        let ref = samples[0].date
        let xs = samples.map { Double(Calendar.current.dateComponents([.day], from: ref, to: $0.date).day ?? 0) }
        let ys = samples.map(\.weight)
        let n = Double(samples.count)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return 0 }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        let meanY = sumY / n
        let ssTot = ys.reduce(0) { $0 + ($1 - meanY) * ($1 - meanY) }
        let ssRes = zip(xs, ys).reduce(0) { $0 + pow($1.1 - (slope * $1.0 + intercept), 2) }
        guard ssTot > 0 else { return 0 }
        return min(1, max(0, 1 - ssRes / ssTot))
    }

    /// Span-based sufficiency: ≥2 points spanning ≥ `minRateSpanDays`.
    static func isSufficient(_ points: [WeightDataPoint]) -> Bool {
        guard points.count >= 2, let f = points.first, let l = points.last else { return false }
        return daysBetween(f.date, l.date) >= minRateSpanDays
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
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AlgorithmConfig.self, from: data) else {
            return .default
        }
        return config
    }

    public static func saveConfig(_ config: AlgorithmConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
}
