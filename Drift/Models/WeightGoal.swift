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
    var proteinPerKg: Double {
        switch self {
        case .balanced: 1.6
        case .highProtein: 2.2
        case .lowCarb: 1.8
        case .lowFat: 1.4
        }
    }

    /// Fat as fraction of total calories (before floor)
    var fatCalorieFraction: Double {
        switch self {
        case .balanced: 0.25
        case .highProtein: 0.25
        case .lowCarb: 0.40
        case .lowFat: 0.15
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: "25% fat, 1.6 g/kg protein"
        case .highProtein: "2.2 g/kg protein, muscle-sparing"
        case .lowCarb: "40% fat, fewer carbs"
        case .lowFat: "15% fat, higher carbs"
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

    var targetWeightLbs: Double { targetWeightKg * 2.20462 }
    var startWeightLbs: Double { startWeightKg * 2.20462 }

    /// Total weight to lose/gain in kg (negative = lose).
    var totalChangeKg: Double { targetWeightKg - startWeightKg }
    var totalChangeLbs: Double { totalChangeKg * 2.20462 }

    /// Required weekly rate in kg/week.
    var requiredWeeklyRateKg: Double {
        let weeks = Double(monthsToAchieve) * 4.33
        return weeks > 0 ? totalChangeKg / weeks : 0
    }

    /// Required daily deficit/surplus in kcal (using configurable energy density).
    var requiredDailyDeficit: Double {
        let config = WeightTrendCalculator.loadConfig()
        return requiredWeeklyRateKg * config.kcalPerKg / 7
    }

    /// Minimum fat: research-based.
    /// - Absolute floor: 0.3 g/kg (essential fatty acid synthesis, hormone production)
    /// - Recommended floor: max(0.5 g/kg, 15% of calorie target)
    /// Sources: ISSN position stand on diets, WHO dietary fat guidelines,
    ///          Helms et al. (2014) natural bodybuilding contest prep review.
    static func minimumFatG(bodyweightKg: Double, calorieTarget: Double?) -> Double {
        let absoluteFloor = bodyweightKg * 0.3  // essential minimum
        let recommended = bodyweightKg * 0.5     // safe minimum for hormones
        let fifteenPct = (calorieTarget ?? 2000) * 0.15 / 9  // WHO: >=15% of energy from fat
        return max(absoluteFloor, max(recommended, fifteenPct))
    }

    /// Compute daily calorie target.
    /// When called from UI (no actualTDEE passed), uses the shared TDEEEstimator.
    /// When called from tests or with explicit TDEE, uses that directly.
    func resolvedCalorieTarget(actualTDEE: Double? = nil) -> Double? {
        if let override = calorieTargetOverride { return override }
        if let tdee = actualTDEE { return tdee + requiredDailyDeficit }
        // Use shared estimator on MainActor, or weight-based fallback
        if Thread.isMainThread {
            let est = MainActor.assumeIsolated { TDEEEstimator.shared.cachedOrSync() }
            return est.tdee + requiredDailyDeficit
        }
        // Off main thread fallback — use the proper base formula (with soft cap)
        return TDEEEstimator.computeBase(weightKg: startWeightKg, activityMultiplier: 29) + requiredDailyDeficit
    }

    /// Describes how the calorie target was determined.
    @MainActor
    func calorieTargetExplanation() -> (source: String, detail: String) {
        if calorieTargetOverride != nil {
            return ("Manual", "You set this calorie target manually.")
        }
        let est = TDEEEstimator.shared.cachedOrSync()
        let target = est.tdee + requiredDailyDeficit
        let deficitStr = requiredDailyDeficit < 0
            ? "- \(Int(abs(requiredDailyDeficit))) deficit"
            : "+ \(Int(abs(requiredDailyDeficit))) surplus"
        return (est.source.rawValue,
                "TDEE \(Int(est.tdee)) \(deficitStr) = \(Int(target)) kcal/day. \(est.confidence == .low ? "Log weight & food for better accuracy." : "")")
    }

    /// Effective macro targets.
    func macroTargets(currentWeightKg: Double? = nil, actualTDEE: Double? = nil) -> MacroTargets? {
        guard let calTarget = resolvedCalorieTarget(actualTDEE: actualTDEE) else { return nil }

        let weight = currentWeightKg ?? startWeightKg
        let pref = dietPreference ?? .balanced
        let isLosing = totalChangeKg < 0

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

    /// Weight remaining to lose/gain from current.
    func remainingKg(currentWeightKg: Double) -> Double {
        targetWeightKg - currentWeightKg
    }

    /// Progress percentage (0 to 1).
    func progress(currentWeightKg: Double) -> Double {
        guard abs(totalChangeKg) > 0.01 else { return 1 }
        let achieved = currentWeightKg - startWeightKg
        return min(1, max(0, achieved / totalChangeKg))
    }

    /// Whether on track: actual rate vs required rate.
    func isOnTrack(actualWeeklyRateKg: Double) -> OnTrackStatus {
        // If target ≈ current weight, consider it achieved
        guard abs(totalChangeKg) > 0.1 else { return .onTrack }
        let required = requiredWeeklyRateKg
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
            UserDefaults.standard.synchronize()
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
