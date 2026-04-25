import Foundation

/// Diet style affects how macros are distributed across protein, carbs, and fat.
public enum DietPreference: String, Codable, CaseIterable, Sendable {
    case balanced    = "balanced"
    case highProtein = "high_protein"
    case lowCarb     = "low_carb"
    case lowFat      = "low_fat"
    case custom      = "custom"

    public var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .highProtein: "High Protein"
        case .lowCarb: "Low Carb"
        case .lowFat: "Low Fat"
        case .custom: "Custom"
        }
    }

    /// Protein g/kg bodyweight. Sources: ISSN position stand, USDA.
    public var proteinPerKg: Double {
        switch self {
        case .balanced: 1.6
        case .highProtein: 2.2
        case .lowCarb: 1.8
        case .lowFat: 1.4
        case .custom: 1.6
        }
    }

    /// Fat as fraction of total calories (before floor). Sources: USDA DGA, WHO, ISSN.
    public var fatCalorieFraction: Double {
        switch self {
        case .balanced: 0.30
        case .highProtein: 0.25
        case .lowCarb: 0.45
        case .lowFat: 0.20
        case .custom: 0.30
        }
    }

    public var subtitle: String {
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
public struct WeightGoal: Codable, Sendable {
    public var targetWeightKg: Double
    public var monthsToAchieve: Int
    public var startDate: String       // YYYY-MM-DD
    public var startWeightKg: Double
    public var proteinTargetG: Double?
    public var carbsTargetG: Double?
    public var fatTargetG: Double?
    public var dietPreference: DietPreference?
    public var calorieTargetOverride: Double?

    public static let storageKey = "drift_weight_goal"

    public init(targetWeightKg: Double, monthsToAchieve: Int, startDate: String, startWeightKg: Double,
                proteinTargetG: Double? = nil, carbsTargetG: Double? = nil, fatTargetG: Double? = nil,
                dietPreference: DietPreference? = nil, calorieTargetOverride: Double? = nil) {
        self.targetWeightKg = targetWeightKg
        self.monthsToAchieve = monthsToAchieve
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG
        self.fatTargetG = fatTargetG
        self.dietPreference = dietPreference
        self.calorieTargetOverride = calorieTargetOverride
    }

    // MARK: - Current-Weight-Based Calculations

    public func isLosing(currentWeightKg: Double) -> Bool {
        currentWeightKg > targetWeightKg
    }

    public func remainingKg(currentWeightKg: Double) -> Double {
        targetWeightKg - currentWeightKg
    }

    public func requiredWeeklyRate(currentWeightKg: Double) -> Double {
        guard let weeks = weeksRemaining, weeks > 0 else { return 0 }
        let raw = remainingKg(currentWeightKg: currentWeightKg) / weeks
        return max(-1.0, min(0.5, raw))
    }

    public func requiredDailyDeficit(currentWeightKg: Double) -> Double {
        let config = WeightTrendCalculator.loadConfig()
        return requiredWeeklyRate(currentWeightKg: currentWeightKg) * config.kcalPerKg / 7
    }

    public var totalChangeKg: Double { targetWeightKg - startWeightKg }

    /// Minimum fat intake — sex-aware, protects hormones, vitamin absorption, and satiety.
    public static func minimumFatG(bodyweightKg: Double, calorieTarget: Double?, isFemale: Bool? = nil) -> Double {
        let female: Bool? = isFemale ?? {
            guard let data = UserDefaults.standard.data(forKey: "drift_tdee_config"),
                  let config = try? JSONDecoder().decode(TDEEEstimator.TDEEConfig.self, from: data) else { return nil }
            return config.sex == .female
        }()
        let gPerKg: Double = switch female {
        case true:  0.8
        case false: 0.6
        case nil:   0.7
        }
        let absoluteFloor = bodyweightKg * gPerKg
        let twentyPct = (calorieTarget ?? 2000) * 0.20 / 9
        return max(absoluteFloor, twentyPct)
    }

    /// Compute daily calorie target using CURRENT weight for deficit calculation.
    public func resolvedCalorieTarget(currentWeightKg: Double? = nil, actualTDEE: Double? = nil) -> Double? {
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
        return max(1200, raw)
    }

    /// Describes how the calorie target was determined.
    @MainActor
    public func calorieTargetExplanation(currentWeightKg: Double? = nil) -> (source: String, detail: String) {
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
    public func macroTargets(currentWeightKg: Double? = nil, actualTDEE: Double? = nil) -> MacroTargets? {
        let weight = currentWeightKg ?? startWeightKg
        let pref = dietPreference ?? .balanced
        let isLosing = weight > targetWeightKg
        let fatFloor = Self.minimumFatG(bodyweightKg: weight, calorieTarget: nil)

        if let p = proteinTargetG, let c = carbsTargetG, let f = fatTargetG {
            let fat = max(f, fatFloor)
            let calTarget = p * 4 + c * 4 + fat * 9
            return MacroTargets(proteinG: p, carbsG: c, fatG: fat,
                                fiberG: Self.defaultFiberG(calories: calTarget),
                                calorieTarget: calTarget, isLosing: isLosing, preference: pref,
                                fatWasClamped: fat > f)
        }

        guard let tdeeAnchor = resolvedCalorieTarget(currentWeightKg: currentWeightKg, actualTDEE: actualTDEE) else { return nil }

        let protein = proteinTargetG ?? (weight * pref.proteinPerKg)

        let fat: Double
        let carbs: Double
        let userSetFat = fatTargetG

        if fatTargetG == nil, let c = carbsTargetG {
            let remainingForFat = tdeeAnchor - protein * 4 - c * 4
            fat = max(remainingForFat / 9, fatFloor)
            carbs = c
        } else {
            let fatFromPref = tdeeAnchor * pref.fatCalorieFraction / 9
            let fatBase = fatTargetG ?? max(fatFromPref, fatFloor)
            fat = max(fatBase, fatFloor)
            let remainingCal = tdeeAnchor - protein * 4 - fat * 9
            carbs = carbsTargetG ?? max(0, remainingCal / 4)
        }

        let effectiveCal = protein * 4 + carbs * 4 + fat * 9
        return MacroTargets(proteinG: protein, carbsG: carbs, fatG: fat,
                            fiberG: Self.defaultFiberG(calories: effectiveCal),
                            calorieTarget: effectiveCal, isLosing: isLosing, preference: pref,
                            fatWasClamped: userSetFat != nil && fat > userSetFat!)
    }

    /// Default fiber target: USDA 14 g per 1000 kcal, rounded up, with floor of 25 g.
    public static func defaultFiberG(calories: Double) -> Double {
        let raw = calories * 14 / 1000
        let rounded = (raw / 5).rounded(.up) * 5
        return max(25, rounded)
    }

    public struct MacroTargets: Sendable {
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double
        public let fiberG: Double
        public let calorieTarget: Double
        public let isLosing: Bool
        public let preference: DietPreference
        public var fatWasClamped: Bool = false

        init(proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, calorieTarget: Double, isLosing: Bool, preference: DietPreference, fatWasClamped: Bool = false) {
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
            self.fiberG = fiberG
            self.calorieTarget = calorieTarget
            self.isLosing = isLosing
            self.preference = preference
            self.fatWasClamped = fatWasClamped
        }
    }

    public var targetDate: Date? {
        guard let start = DateFormatters.dateOnly.date(from: startDate) else { return nil }
        return Calendar.current.date(byAdding: .month, value: monthsToAchieve, to: start)
    }

    public var daysRemaining: Int? {
        guard let target = targetDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 0)
    }

    public var weeksRemaining: Double? {
        daysRemaining.map { Double($0) / 7 }
    }

    public func progress(currentWeightKg: Double) -> Double {
        let totalDistance = abs(targetWeightKg - startWeightKg)
        guard totalDistance > 0.5 else { return 1 }
        let remainingDistance = abs(targetWeightKg - currentWeightKg)
        if remainingDistance < 0.5 { return 1 }
        let startToTarget = targetWeightKg - startWeightKg
        let startToCurrent = currentWeightKg - startWeightKg
        guard startToTarget != 0 else { return 1 }
        let ratio = startToCurrent / startToTarget
        if ratio >= 1.0 && remainingDistance <= totalDistance * 0.5 { return 1.0 }
        if ratio < 0 { return 0.0 }
        let fromRatio = min(1, ratio)
        let fromRemaining = max(0, 1 - remainingDistance / max(totalDistance, remainingDistance))
        return min(fromRatio, fromRemaining)
    }

    public func isOnTrack(actualWeeklyRateKg: Double, currentWeightKg: Double? = nil) -> OnTrackStatus {
        let cw = currentWeightKg ?? startWeightKg
        let remaining = abs(remainingKg(currentWeightKg: cw))
        guard remaining > 0.5 else { return .onTrack }
        let required = requiredWeeklyRate(currentWeightKg: cw)
        guard abs(required) > 0.001 else { return .onTrack }
        let ratio = actualWeeklyRateKg / required

        if ratio < 0 { return .wrongDirection }
        if ratio > 1.2 { return .ahead }
        if ratio >= 0.8 { return .onTrack }
        return .behind
    }

    public enum OnTrackStatus {
        case ahead, onTrack, behind, wrongDirection

        public var label: String {
            switch self {
            case .ahead: "Ahead of schedule"
            case .onTrack: "On track"
            case .behind: "Behind schedule"
            case .wrongDirection: "Wrong direction"
            }
        }
    }

    // MARK: - Persistence

    public static func load() -> WeightGoal? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let goal = try? JSONDecoder().decode(WeightGoal.self, from: data) else { return nil }
        return goal
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
            Log.app.info("Weight goal saved: target=\(targetWeightKg)kg in \(monthsToAchieve) months")
        } else {
            Log.app.error("Failed to encode weight goal")
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.synchronize()
    }
}
