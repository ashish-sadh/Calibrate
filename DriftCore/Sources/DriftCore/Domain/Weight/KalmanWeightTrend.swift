import Foundation

/// Structural state-space filter for scale weight — the principled core of
/// the estimation unification (Docs/refactor/estimation-unification.md,
/// 2026-07-13). Three states:
///
///   w — true (persistent) body weight, kg
///   r — daily rate of change of w, kg/day
///   u — TRANSIENT water/glycogen level, kg: mean-reverting (OU) with a
///       ~3.5-day half-life. A salt night, a carb load, or a 5-day post-peak
///       plunge loads into `u` and decays; only persistent change reaches
///       w/r. This is what makes the filter tell the "3-week energy balance"
///       story instead of chasing the latest water swing (field scenario
///       2026-07-13: 5 consecutive plunge days scored z=1.37 on a 2-state
///       filter — consistent innovations are invisible to a Huber gate; they
///       need a STATE to live in). Also the model-level treatment of the two
///       Monte-Carlo weak families (AR(1) water episodes, cyclical water).
///
/// Observation: scale reading z = w + u + white noise.
///
/// What this replaces when `AlgorithmConfig.engine == .kalman`: the 8-day
/// re-smooth + OLS slope + spike-proof seed. What stays as protective layers
/// around any engine: outlier pre-filter, display EMA + gap reset, 45-day
/// evidence bound, span sufficiency, slow-trend MK escalation, maintaining
/// band, ±1.5 kg/wk clamp, energySignalConflicts, projection guards
/// (operator 2026-07-13: "simpler core + protective layers we learn over
/// time").
///
/// Robustness: huberized measurement variance — when the normalized
/// innovation exceeds `huberK`, R is inflated by (ν/k)², down-weighting the
/// reading smoothly (one reweight pass; standard robust-KF form).
///
/// The posterior rate variance P₁₁ is the publication currency: confidence
/// z = |r|/√P₁₁ feeds the engine-calibrated ramp in WeightTrendCalculator.
public enum KalmanWeightTrend {

    public struct Config: Sendable {
        /// Rate process noise — THE responsiveness knob. Implied rate
        /// time-constant ≈ √(measurementStd/rateProcessStd) days.
        public var rateProcessStd: Double
        /// Extra persistent-weight process noise (kg/√day).
        public var weightProcessStd: Double
        /// White measurement noise of one reading (kg) — same-day scale/
        /// hydration jitter NOT carried to the next day (multi-day water
        /// belongs to the `u` state).
        public var measurementStd: Double
        /// Stationary std of the transient water state (kg).
        public var waterStd: Double
        /// Half-life of water-state decay (days).
        public var waterHalfLifeDays: Double
        /// Huber threshold on the normalized innovation.
        public var huberK: Double
        /// Prior rate uncertainty at the first reading (kg/day).
        public var initialRateStd: Double

        public init(rateProcessStd: Double, weightProcessStd: Double,
                    measurementStd: Double, waterStd: Double,
                    waterHalfLifeDays: Double, huberK: Double,
                    initialRateStd: Double) {
            self.rateProcessStd = rateProcessStd
            self.weightProcessStd = weightProcessStd
            self.measurementStd = measurementStd
            self.waterStd = waterStd
            self.waterHalfLifeDays = waterHalfLifeDays
            self.huberK = huberK
            self.initialRateStd = initialRateStd
        }

        /// Calibrated 2026-07-13 against the pinned real datasets, the gold
        /// suite, and the Monte-Carlo families (see KalmanProbeTests history
        /// in the estimation-unification commit).
        public static let `default` = Config(
            rateProcessStd: 0.016, weightProcessStd: 0.02,
            measurementStd: 0.35, waterStd: 0.55,
            waterHalfLifeDays: 3.5, huberK: 2.5, initialRateStd: 0.1)
    }

    public struct Output: Sendable {
        /// Filtered persistent weight at the last observation (kg).
        public let weight: Double
        /// Transient water estimate at the last observation (kg).
        public let waterKg: Double
        /// Rate of the persistent component (kg/week).
        public let weeklyRateKg: Double
        /// Posterior std of the weekly rate (kg/week).
        public let weeklyRateStd: Double
        /// |rate| / rateStd — confidence fed to the publication ramp.
        public var rateZ: Double { weeklyRateStd > 0 ? abs(weeklyRateKg) / weeklyRateStd : 0 }
        /// Filtered persistent weight per observation date.
        public let filteredSeries: [(date: Date, weight: Double)]
    }

    /// Run the filter over date-sorted observations. Returns nil for < 2
    /// observations. Same-day repeats update without a predict step.
    public static func run(
        observations: [(date: Date, weightKg: Double)],
        config: Config = .default
    ) -> Output? {
        guard observations.count >= 2, let first = observations.first else { return nil }

        let rNoise = config.measurementStd * config.measurementStd
        let sr2 = config.rateProcessStd * config.rateProcessStd
        let sw2 = config.weightProcessStd * config.weightProcessStd
        let uVar = config.waterStd * config.waterStd

        // State
        var w = first.weightKg, r = 0.0, u = 0.0
        // Covariance (symmetric)
        var p00 = rNoise, p01 = 0.0, p02 = 0.0
        var p11 = config.initialRateStd * config.initialRateStd
        var p12 = 0.0
        var p22 = uVar
        var series: [(date: Date, weight: Double)] = [(first.date, w)]
        var prevDate = first.date

        for obs in observations.dropFirst() {
            let dt = max(0, obs.date.timeIntervalSince(prevDate) / 86_400)

            if dt > 0 {
                // Predict: w += r·dt, u decays with per-interval factor φ.
                let phi = pow(0.5, dt / config.waterHalfLifeDays)
                w += r * dt
                u *= phi
                let q00 = sr2 * dt * dt * dt / 3 + sw2 * dt
                let q01 = sr2 * dt * dt / 2
                let q11 = sr2 * dt
                let qU = uVar * (1 - phi * phi)   // keeps u stationary at waterStd
                let np00 = p00 + 2 * dt * p01 + dt * dt * p11 + q00
                let np01 = p01 + dt * p11 + q01
                let np02 = phi * (p02 + dt * p12)
                let np11 = p11 + q11
                let np12 = phi * p12
                let np22 = phi * phi * p22 + qU
                p00 = np00; p01 = np01; p02 = np02
                p11 = np11; p12 = np12; p22 = np22
            }

            // Update, H = [1, 0, 1]
            let hp0 = p00 + p02        // (H P)ᵀ components
            let hp1 = p01 + p12
            let hp2 = p02 + p22
            let hph = p00 + 2 * p02 + p22
            var rEff = rNoise
            var s = hph + rEff
            let y = obs.weightKg - (w + u)
            let nu = y / s.squareRoot()
            if abs(nu) > config.huberK {
                let scale = abs(nu) / config.huberK
                rEff = rNoise * scale * scale
                s = hph + rEff
            }
            let k0 = hp0 / s, k1 = hp1 / s, k2 = hp2 / s
            w += k0 * y
            r += k1 * y
            u += k2 * y
            // P ← P − K ⊗ (H P)
            p00 -= k0 * hp0
            p01 -= k0 * hp1
            p02 -= k0 * hp2
            p11 -= k1 * hp1
            p12 -= k1 * hp2
            p22 -= k2 * hp2

            series.append((obs.date, w))
            prevDate = obs.date
        }

        return Output(
            weight: w,
            waterKg: u,
            weeklyRateKg: r * 7,
            weeklyRateStd: 7 * max(p11, 0).squareRoot(),
            filteredSeries: series)
    }
}
