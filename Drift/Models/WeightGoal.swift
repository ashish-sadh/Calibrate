import Foundation

/// Diet style affects how macros are distributed across protein, carbs, and fat.
enum DietPreference: String, Codable, CaseIterable, Sendable {
    case balanced    = "balanced"
    case highProtein = "high_protein"
    case lowCarb     = "low_carb"
    case lowFat      = "low_fat"

    var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .highProtein: "High Protein"
        case .lowCarb: "Low Carb"
        case .lowFat: "Low Fat"
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
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: "30% fat, 1.6 g/kg protein, flexible"
        case .highProtein: "2.2 g/kg protein, muscle-focused"
        case .lowCarb: "45% fat, fewer carbs, keto-friendly"
        case .lowFat: "20% fat, higher carbs, endurance-friendly"
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
    func macroTargets(currentWeightKg: Double? = nil, actualTDEE: Double? = nil) -> MacroTargets? {
        guard let calTarget = resolvedCalorieTarget(currentWeightKg: currentWeightKg, actualTDEE: actualTDEE) else { return nil }

        let weight = currentWeightKg ?? startWeightKg
        let pref = dietPreference ?? .balanced
        let isLosing = weight > targetWeightKg  // current-based direction

        // Protein
        let protein = proteinTargetG ?? (weight * pref.proteinPerKg)

        // Fat: from preference %, enforce research-based minimum
        let fatFromPref = calTarget * pref.fatCalorieFraction / 9
        let fatFloor = Self.minimumFatG(bodyweightKg: weight, calorieTarget: calTarget)
        let fat = fatTargetG ?? max(fatFromPref, fatFloor)

        // Carbs: fill remaining calories, floor at 0
        let remainingCal = calTarget - (protein * 4) - (fat * 9)
        let carbs = carbsTargetG ?? max(0, remainingCal / 4)

        return MacroTargets(proteinG: protein, carbsG: carbs, fatG: fat,
                            calorieTarget: calTarget, isLosing: isLosing, preference: pref)
    }

    struct MacroTargets: Sendable {
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let calorieTarget: Double
        let isLosing: Bool
        let preference: DietPreference
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
