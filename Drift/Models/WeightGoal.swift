import Foundation
import DriftCore

/// Diet style affects how macros are distributed across protein, carbs, and fat.
enum DietPreference: String, Codable, CaseIterable, Sendable {
    case balanced    = "balanced"
    case highProtein = "high_protein"
    case lowCarb     = "low_carb"
    case lowFat      = "low_fat"
    case custom      = "custom"

    var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .highProtein: "High Protein"
        case .lowCarb: "Low Carb"
        case .lowFat: "Low Fat"
        case .custom: "Custom"
        }
    }

    /// Protein g/kg bodyweight
    /// Sources: ISSN position stand (1.6-2.2 g/kg for active), USDA (0.8 g/kg sedentary)
    var proteinPerKg: Double {
        switch self {
        case .balanced: 1.6     // Active general: 1.6 g/kg (ISSN lower bound)
        case .highProtein: 2.2  // Muscle-sparing deficit: 2.2 g/kg (ISSN upper bound)
        case .lowCarb: 1.8     // Moderate-high protein for satiety
        case .lowFat: 1.4      // Lower protein allows more carb calories
        case .custom: 1.6      // Fallback if fields left blank — same as balanced
        }
    }

    /// Fat as fraction of total calories (before floor)
    /// Sources: USDA DGA 20-35%, WHO 15-30%, ISSN 0.5-1.5 g/kg
    /// Key: fat is essential for hormones, satiety, vitamin absorption
    var fatCalorieFraction: Double {
        switch self {
        case .balanced: 0.30    // Was 0.25 — 30% is mid-range of USDA 20-35%, better for satiety
        case .highProtein: 0.25 // Lower fat to make room for high protein
        case .lowCarb: 0.45    // Was 0.40 — keto-adjacent, fat replaces carbs
        case .lowFat: 0.20     // Was 0.15 — 20% is USDA minimum, 15% was too aggressive
        case .custom: 0.30     // Fallback if fields left blank — same as balanced
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: "30% fat, 1.6 g/kg protein, flexible"
        case .highProtein: "2.2 g/kg protein, muscle-focused"
        case .lowCarb: "45% fat, fewer carbs, keto-friendly"
        case .lowFat: "20% fat, higher carbs, endurance-friendly"
        case .custom: "Set your own protein, carbs & fat in grams"
        }
    }
}

/// Persisted weight goal configuration.
struct WeightGoal: Codable, Sendable {
    var targetWeightKg: Double
    var monthsToAchieve: Int
    var startDate: String       // YYYY-MM-DD
    var startWeightKg: Double
    var proteinTargetG: Double?      // manual override (nil = auto-calculate)
    var carbsTargetG: Double?
    var fatTargetG: Double?
    var dietPreference: DietPreference?
    var calorieTargetOverride: Double? // user-input daily calorie target (nil = derive from TDEE)

    static let storageKey = "drift_weight_goal"

    // MARK: - Current-Weight-Based Calculations

    /// Is the user trying to lose weight? Based on CURRENT weight vs target, not start.
    func isLosing(currentWeightKg: Double) -> Bool {
        currentWeightKg > targetWeightKg
    }

    /// How much remains from CURRENT weight to target (negative = need to lose).
    func remainingKg(currentWeightKg: Double) -> Double {
        targetWeightKg - currentWeightKg
    }

    /// Required weekly rate based on CURRENT weight and remaining time.
    func requiredWeeklyRate(currentWeightKg: Double) -> Double {
        guard let weeks = weeksRemaining, weeks > 0 else { return 0 }
        let raw = remainingKg(currentWeightKg: currentWeightKg) / weeks
        // Cap at safe limits: max 1 kg/week loss, 0.5 kg/week gain
        // Beyond this the math produces nonsensical calorie targets
        return max(-1.0, min(0.5, raw))
    }

    /// Required daily deficit based on CURRENT weight and remaining time.
    func requiredDailyDeficit(currentWeightKg: Double) -> Double {
        let config = WeightTrendCalculator.loadConfig()
        return requiredWeeklyRate(currentWeightKg: currentWeightKg) * config.kcalPerKg / 7
    }

    /// Total planned change from start (for progress bar).
    var totalChangeKg: Double { targetWeightKg - startWeightKg }

    /// Minimum fat intake — sex-aware, protects hormones, vitamin absorption, and satiety.
    /// Women need more fat for estrogen/progesterone production and bone density.
    /// Sources: ISSN position stand, Helms et al. (2014), WHO guidelines.
    static func minimumFatG(bodyweightKg: Double, calorieTarget: Double?, isFemale: Bool? = nil) -> Double {
        // Determine sex: explicit param > stored config > default to middle
        let female: Bool? = isFemale ?? {
            guard let data = UserDefaults.standard.data(forKey: "drift_tdee_config"),
                  let config = try? JSONDecoder().decode(TDEEEstimator.TDEEConfig.self, from: data) else { return nil }
            return config.sex == .female
        }()
        let gPerKg: Double = switch female {
        case true:  0.8   // women: higher for hormonal health (estrogen, fertility, bone density)
        case false: 0.6   // men: lower threshold but still needed for testosterone
        case nil:   0.7   // unknown: middle ground
        }
        let absoluteFloor = bodyweightKg * gPerKg
        let twentyPct = (calorieTarget ?? 2000) * 0.20 / 9  // USDA: >=20% of calories from fat
        return max(absoluteFloor, twentyPct)
    }

    /// Compute daily calorie target using CURRENT weight for deficit calculation.
    func resolvedCalorieTarget(currentWeightKg: Double? = nil, actualTDEE: Double? = nil) -> Double? {
        if let override = calorieTargetOverride { return override }
        let cw = currentWeightKg ?? startWeightKg
        let deficit = requiredDailyDeficit(currentWeightKg: cw)
        let raw: Double
        if let tdee = actualTDEE {
            raw = tdee + deficit
        } else if Thread.isMainThread {
            let est = MainActor.assumeIsolated { TDEEEstimator.shared.cachedOrSync() }
            raw = est.tdee + deficit
        } else {
            raw = TDEEEstimator.computeBase(weightKg: cw, activityMultiplier: 29) + deficit
        }
        // Floor: never suggest eating less than 1200 kcal (unsafe)
        return max(1200, raw)
    }

    /// Describes how the calorie target was determined.
    @MainActor
    func calorieTargetExplanation(currentWeightKg: Double? = nil) -> (source: String, detail: String) {
        if calorieTargetOverride != nil {
            return ("Manual", "You set this calorie target manually.")
        }
        let cw = currentWeightKg ?? startWeightKg
        let deficit = requiredDailyDeficit(currentWeightKg: cw)
        let est = TDEEEstimator.shared.cachedOrSync()
        let rawTarget = est.tdee + deficit
        let actualTarget = max(1200, rawTarget)
        let deficitStr = deficit < 0
            ? "- \(Int(abs(deficit))) deficit"
            : "+ \(Int(abs(deficit))) surplus"
        let floorNote = rawTarget < 1200 ? " (floored to 1200 for safety)" : ""
        return (est.source.rawValue,
                "TDEE \(Int(est.tdee)) \(deficitStr) = \(Int(actualTarget)) kcal/day.\(floorNote)\(est.confidence == .low ? " Log weight & food for better accuracy." : "")")
    }

    /// Effective macro targets.
    /// - Fat floor is always enforced (sex-aware safety minimum), even on explicit user input.
    /// - Reported calorieTarget = actual macro sum, not TDEE anchor. TDEE only auto-fills unset carbs.
    func macroTargets(currentWeightKg: Double? = nil, actualTDEE: Double? = nil) -> MacroTargets? {
        let weight = currentWeightKg ?? startWeightKg
        let pref = dietPreference ?? .balanced
        let isLosing = weight > targetWeightKg
        let fatFloor = Self.minimumFatG(bodyweightKg: weight, calorieTarget: nil)

        // All 3 custom macros set → calorie IS the sum of macros (fully determined, no TDEE needed).
        // calorieTargetOverride is ignored (UI disables the calorie field when all 3 macros are set).
        if let p = proteinTargetG, let c = carbsTargetG, let f = fatTargetG {
            let fat = max(f, fatFloor)
            let calTarget = p * 4 + c * 4 + fat * 9
            return MacroTargets(proteinG: p, carbsG: c, fatG: fat,
                                fiberG: Self.defaultFiberG(calories: calTarget),
                                calorieTarget: calTarget, isLosing: isLosing, preference: pref,
                                fatWasClamped: fat > f)
        }

        // Partial or no overrides: TDEE anchors auto-fill of unset macros.
        // Fill rule: the unset flexible macro fills the remaining TDEE budget.
        //   - Fat not set, carbs set → fat fills remaining (carbs can't flex)
        //   - Fat set (or both unset) → carbs fill remaining (standard path)
        // Fat floor always enforced. Reported calorie = actual macro sum.
        guard let tdeeAnchor = resolvedCalorieTarget(currentWeightKg: currentWeightKg, actualTDEE: actualTDEE) else { return nil }

        let protein = proteinTargetG ?? (weight * pref.proteinPerKg)

        let fat: Double
        let carbs: Double
        let userSetFat = fatTargetG

        if fatTargetG == nil, let c = carbsTargetG {
            // Carbs fixed, fat is the fill macro — avoid unexpected deficit
            let remainingForFat = tdeeAnchor - protein * 4 - c * 4
            fat = max(remainingForFat / 9, fatFloor)
            carbs = c
        } else {
            // Standard: fat from preference %, carbs fill remaining
            let fatFromPref = tdeeAnchor * pref.fatCalorieFraction / 9
            let fatBase = fatTargetG ?? max(fatFromPref, fatFloor)
            fat = max(fatBase, fatFloor)                        // floor always wins, even on explicit input
            let remainingCal = tdeeAnchor - protein * 4 - fat * 9
            carbs = carbsTargetG ?? max(0, remainingCal / 4)    // floor at 0, can't go negative
        }

        // Always report what the user will actually eat, not the TDEE anchor.
        let effectiveCal = protein * 4 + carbs * 4 + fat * 9
        return MacroTargets(proteinG: protein, carbsG: carbs, fatG: fat,
                            fiberG: Self.defaultFiberG(calories: effectiveCal),
                            calorieTarget: effectiveCal, isLosing: isLosing, preference: pref,
                            fatWasClamped: userSetFat != nil && fat > userSetFat!)
    }

    /// Default fiber target: USDA 14 g per 1000 kcal, rounded up to the nearest 5 g,
    /// with a hard floor of 25 g (ICMR/ADA consensus minimum).
    static func defaultFiberG(calories: Double) -> Double {
        let raw = calories * 14 / 1000
        let rounded = (raw / 5).rounded(.up) * 5
        return max(25, rounded)
    }

    struct MacroTargets: Sendable {
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double
        let calorieTarget: Double
        let isLosing: Bool
        let preference: DietPreference
        var fatWasClamped: Bool = false
    }

    /// Target date.
    var targetDate: Date? {
        guard let start = DateFormatters.dateOnly.date(from: startDate) else { return nil }
        return Calendar.current.date(byAdding: .month, value: monthsToAchieve, to: start)
    }

    /// Days remaining.
    var daysRemaining: Int? {
        guard let target = targetDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 0)
    }

    /// Weeks remaining.
    var weeksRemaining: Double? {
        daysRemaining.map { Double($0) / 7 }
    }

    /// Progress percentage (0 to 1). Based on how close current is to target
    /// relative to the total distance from start to target.
    func progress(currentWeightKg: Double) -> Double {
        let totalDistance = abs(targetWeightKg - startWeightKg)
        guard totalDistance > 0.5 else { return 1 }
        let remainingDistance = abs(targetWeightKg - currentWeightKg)
        // Within 0.5 kg of target → done
        if remainingDistance < 0.5 { return 1 }
        // Ratio: how far current has moved from start toward target
        let startToTarget = targetWeightKg - startWeightKg
        let startToCurrent = currentWeightKg - startWeightKg
        guard startToTarget != 0 else { return 1 }
        let ratio = startToCurrent / startToTarget
        // Past target in goal direction → 100% (if overshoot is reasonable)
        if ratio >= 1.0 && remainingDistance <= totalDistance * 0.5 { return 1.0 }
        // Wrong direction from start → 0%
        if ratio < 0 { return 0.0 }
        // Normal progress — but never show > remaining-based estimate
        // This prevents 100% when start is stale and current is far from target
        let fromRatio = min(1, ratio)
        let fromRemaining = max(0, 1 - remainingDistance / max(totalDistance, remainingDistance))
        return min(fromRatio, fromRemaining)
    }

    /// Whether on track: actual rate vs required rate. Uses current weight for direction.
    func isOnTrack(actualWeeklyRateKg: Double, currentWeightKg: Double? = nil) -> OnTrackStatus {
        let cw = currentWeightKg ?? startWeightKg
        let remaining = abs(remainingKg(currentWeightKg: cw))
        guard remaining > 0.5 else { return .onTrack }  // at target
        let required = requiredWeeklyRate(currentWeightKg: cw)
        guard abs(required) > 0.001 else { return .onTrack }
        let ratio = actualWeeklyRateKg / required

        // Negative ratio = moving opposite direction (losing when should gain, or vice versa)
        if ratio < 0 { return .wrongDirection }
        if ratio > 1.2 { return .ahead }
        if ratio >= 0.8 { return .onTrack }
        return .behind
    }

    enum OnTrackStatus {
        case ahead, onTrack, behind, wrongDirection

        var label: String {
            switch self {
            case .ahead: "Ahead of schedule"
            case .onTrack: "On track"
            case .behind: "Behind schedule"
            case .wrongDirection: "Wrong direction"
            }
        }
    }

    // MARK: - Persistence

    static func load() -> WeightGoal? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let goal = try? JSONDecoder().decode(WeightGoal.self, from: data) else { return nil }
        return goal
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)


            Log.app.info("Weight goal saved: target=\(targetWeightKg)kg in \(monthsToAchieve) months")
        } else {
            Log.app.error("Failed to encode weight goal")
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.synchronize()
    }
}
