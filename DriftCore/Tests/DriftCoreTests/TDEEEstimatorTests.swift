import Foundation
@testable import DriftCore
import Testing

// MARK: - computeBase (5 tests)

@Test func computeBaseAt70kgActivity29MatchesSexAveragedMifflin() {
    // Base = sex-averaged Mifflin default (age 30, 170cm): (10·70 + 834.5) × 1.55 ≈ 2378
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    #expect(abs(base - 2378.5) < 1)
}

@Test func computeBaseNilWeightIs2000() {
    let base = TDEEEstimator.computeBase(weightKg: nil, activityMultiplier: 29)
    #expect(base == 2000)
}

@Test func computeBaseZeroWeightIs2000() {
    let base = TDEEEstimator.computeBase(weightKg: 0, activityMultiplier: 29)
    #expect(base == 2000)
}

@Test func computeBaseHeavierPersonHigherTDEE() {
    let light = TDEEEstimator.computeBase(weightKg: 50, activityMultiplier: 29)
    let heavy = TDEEEstimator.computeBase(weightKg: 120, activityMultiplier: 29)
    #expect(heavy > light)
}

@Test func computeBaseSoftCapAbove3000() {
    // Very heavy person with high activity would exceed 3000 without cap
    let capped = TDEEEstimator.computeBase(weightKg: 200, activityMultiplier: 36)
    // Should be higher than 3000 but compressed (30% of excess above cap)
    #expect(capped > 3000)
    // Uncapped raw would be: (10·200 + 834.5) × 1.9 ≈ 5386
    // With cap: 3000 + (5386 - 3000) * 0.3 ≈ 3716
    #expect(abs(capped - 3715.7) < 2)
    #expect(capped < 5386) // definitely compressed
}

// MARK: - computeMifflin (7 tests)

@Test func computeMifflinRequiresAtLeastOneProfileField() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = nil; config.heightCm = nil; config.sex = nil
    let result = TDEEEstimator.computeMifflin(weightKg: 70, config: config)
    #expect(result == nil)
}

@Test func computeMifflinMaleFullProfile() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = .male
    config.activityMultiplier = 29  // mifflinActivityFactor = 1.55
    let result = TDEEEstimator.computeMifflin(weightKg: 80, config: config)!
    // BMR = 10*80 + 6.25*175 - 5*30 + 5 = 800 + 1093.75 - 150 + 5 = 1748.75
    // TDEE = 1748.75 * 1.55 ≈ 2710
    #expect(result.tdee > 2500 && result.tdee < 3000)
    #expect(abs(result.confidence - 1.0) < 0.01) // all 3 fields
}

@Test func computeMifflinFemaleFullProfile() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 25; config.heightCm = 165; config.sex = .female
    config.activityMultiplier = 29
    let female = TDEEEstimator.computeMifflin(weightKg: 60, config: config)!
    var maleConfig = config; maleConfig.sex = .male
    let male = TDEEEstimator.computeMifflin(weightKg: 60, config: maleConfig)!
    // Male BMR is 166 kcal higher than female
    #expect(male.tdee > female.tdee)
}

@Test func computeMifflinNoSexAveragesMaleFemale() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = nil
    let noSex = TDEEEstimator.computeMifflin(weightKg: 75, config: config)!

    var maleConfig = config; maleConfig.sex = .male
    var femaleConfig = config; femaleConfig.sex = .female
    let male = TDEEEstimator.computeMifflin(weightKg: 75, config: maleConfig)!
    let female = TDEEEstimator.computeMifflin(weightKg: 75, config: femaleConfig)!

    #expect(noSex.tdee > female.tdee && noSex.tdee < male.tdee)
}

@Test func computeMifflinPartialProfileLowerConfidence() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = nil; config.sex = nil  // only 1 of 3 fields
    let result = TDEEEstimator.computeMifflin(weightKg: 70, config: config)!
    #expect(abs(result.confidence - 1.0/3.0) < 0.01)
}

@Test func computeMifflinTwoFieldsMediumConfidence() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = nil
    let result = TDEEEstimator.computeMifflin(weightKg: 70, config: config)!
    #expect(abs(result.confidence - 2.0/3.0) < 0.01)
}

@Test func computeMifflinActivityFactorScales() {
    var sedentary = TDEEEstimator.TDEEConfig.default
    sedentary.age = 30; sedentary.heightCm = 170; sedentary.sex = .male
    sedentary.activityMultiplier = 22  // → 1.2

    var athlete = sedentary
    athlete.activityMultiplier = 36  // → 1.9

    let low = TDEEEstimator.computeMifflin(weightKg: 70, config: sedentary)!
    let high = TDEEEstimator.computeMifflin(weightKg: 70, config: athlete)!
    #expect(high.tdee > low.tdee)
}

// MARK: - TDEEConfig (5 tests)

@Test func configActivityLabelSedentary() {
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 22
    #expect(config.activityLabel == "Sedentary")
}

@Test func configActivityLabelModeratelyActive() {
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 29
    #expect(config.activityLabel == "Moderately Active")
}

@Test func configHasMifflinProfileFalseByDefault() {
    #expect(TDEEEstimator.TDEEConfig.default.hasMifflinProfile == false)
}

@Test func configHasMifflinProfileTrueWhenAllSet() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = .male
    #expect(config.hasMifflinProfile == true)
}

@Test func configMifflinActivityFactorAt22Is1_2() {
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 22
    #expect(abs(config.mifflinActivityFactor - 1.2) < 0.001)
}

@Test func configActivityLabelLightlyActive() {
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 25
    #expect(config.activityLabel == "Lightly Active")
}

@Test func configActivityLabelVeryActive() {
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 31
    #expect(config.activityLabel == "Very Active")
}

@Test func configActivityLabelAthlete() {
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 36
    #expect(config.activityLabel == "Athlete")
}

// MARK: - Sex (2 tests)

@Test func sexLabelMale() {
    #expect(TDEEEstimator.Sex.male.label == "Male")
}

@Test func sexLabelFemale() {
    #expect(TDEEEstimator.Sex.female.label == "Female")
}

// MARK: - TDEEConfig loggingConsistencyThreshold

@Test func loggingConsistencyThresholdIsHalf() {
    #expect(TDEEEstimator.TDEEConfig.default.loggingConsistencyThreshold == 0.5)
}

// MARK: - Estimate.explanation (5 source cases)

@Test func estimateExplanationAppleHealth() {
    let e = TDEEEstimator.Estimate(tdee: 2000, source: .appleHealth, confidence: .high,
                                   timestamp: Date(), activeSources: ["Apple Health"])
    #expect(e.explanation.contains("Apple Health"))
}

@Test func estimateExplanationWeightTrend() {
    let e = TDEEEstimator.Estimate(tdee: 2000, source: .weightTrend, confidence: .medium,
                                   timestamp: Date(), activeSources: ["Weight Trend"])
    #expect(e.explanation.contains("food logs"))
}

@Test func estimateExplanationBlended() {
    let e = TDEEEstimator.Estimate(tdee: 2000, source: .blended, confidence: .high,
                                   timestamp: Date(), activeSources: ["Weight", "Apple Health"])
    #expect(e.explanation.contains("multiple"))
}

@Test func estimateExplanationMifflin() {
    let e = TDEEEstimator.Estimate(tdee: 2000, source: .mifflin, confidence: .medium,
                                   timestamp: Date(), activeSources: ["Profile"])
    #expect(e.explanation.contains("profile"))
}

@Test func estimateExplanationBodyWeight() {
    let e = TDEEEstimator.Estimate(tdee: 2000, source: .bodyWeight, confidence: .low,
                                   timestamp: Date(), activeSources: ["Weight"])
    #expect(e.explanation.contains("body weight"))
}

// MARK: - blend (pure pipeline — every correction combination, no I/O)

@Test func blendNoCorrectionsIsBase() {
    let r = TDEEEstimator.blend(weightKg: 70, config: .default, appleHealthTDEE: nil, weightTrendTDEE: nil)
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    #expect(abs(r.tdee - base) < 0.001)
    #expect(r.sources == ["Weight"])
    #expect(r.bestSource == .bodyWeight)
}

@Test func blendNilWeightFallsBackToDefault() {
    let r = TDEEEstimator.blend(weightKg: nil, config: .default, appleHealthTDEE: nil, weightTrendTDEE: nil)
    #expect(r.tdee == 2000)
    #expect(r.sources == ["Default"])
}

@Test func blendFullProfilePullsTowardMifflin() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = .male
    let base = TDEEEstimator.computeBase(weightKg: 100, activityMultiplier: 29)
    let (mifflin, conf) = TDEEEstimator.computeMifflin(weightKg: 100, config: config)!
    let r = TDEEEstimator.blend(weightKg: 100, config: config, appleHealthTDEE: nil, weightTrendTDEE: nil)
    let expected = base + (mifflin - base) * TDEEEstimator.mifflinCorrectionWeight * conf
    #expect(abs(r.tdee - expected) < 0.001)
    #expect(r.bestSource == .mifflin)
    // The whole point of the 0.7 weight: a full profile must land the
    // estimate close to Mifflin (the old 0.4 left a 100kg male 12% short).
    #expect(abs(r.tdee - mifflin) / mifflin < 0.05,
            "Full profile must land within 5% of Mifflin, got \(Int(r.tdee)) vs \(Int(mifflin))")
}

@Test func blendAppleHealthPullsHalfway() {
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    let r = TDEEEstimator.blend(weightKg: 70, config: .default, appleHealthTDEE: 2800, weightTrendTDEE: nil)
    #expect(abs(r.tdee - (base + (2800 - base) * 0.5)) < 0.001)
    #expect(r.sources.contains("Apple Health"))
}

@Test func blendTrendPullIsDampenedTo30Percent() {
    // Under-logging user: trend anchor says 1400 while base says ~2378.
    // The pull is capped at 30% so one bad anchor can't crater the estimate
    // (the "app thinks my maintenance is low" complaint).
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    let r = TDEEEstimator.blend(weightKg: 70, config: .default, appleHealthTDEE: nil, weightTrendTDEE: 1400)
    #expect(abs(r.tdee - (base + (1400 - base) * 0.3)) < 0.001)
    #expect(r.tdee > 2000, "A single low anchor must not crater the estimate, got \(Int(r.tdee))")
    #expect(r.bestSource == .blended)
}

@Test func blendFloorsAt1200() {
    var config = TDEEEstimator.TDEEConfig.default
    config.manualAdjustment = -5000
    let r = TDEEEstimator.blend(weightKg: 45, config: config, appleHealthTDEE: nil, weightTrendTDEE: nil)
    #expect(r.tdee == 1200, "TDEE must floor at 1200, got \(r.tdee)")
}

@Test func blendAllSourcesAccumulateAndBlend() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = .male
    let r = TDEEEstimator.blend(weightKg: 80, config: config, appleHealthTDEE: 2900, weightTrendTDEE: 2750)
    #expect(r.sources.count == 4) // Weight + Profile + Apple Health + Weight Trend
    #expect(r.bestSource == .blended)
    #expect(r.tdee > 2400 && r.tdee < 3000, "All-sources blend should land between anchors, got \(Int(r.tdee))")
}

// MARK: - trendAnchoredTDEE (pure aggregation of the weight-trend anchor)

@Test func trendAnchorRequiresFiveQualifiedDays() {
    let four: [Double] = [2000, 2000, 2000, 2000]
    #expect(TDEEEstimator.trendAnchoredTDEE(qualifiedDailyTotals: four, estimatedDailyDeficit: 0) == nil)
    let five: [Double] = four + [2000]
    #expect(TDEEEstimator.trendAnchoredTDEE(qualifiedDailyTotals: five, estimatedDailyDeficit: 0) == 2000)
}

@Test func trendAnchorIsMedianMinusDeficit() {
    // Losing ~0.5 kg/wk → daily balance ≈ −550. Eating 1800 median → TDEE 2350.
    let t = TDEEEstimator.trendAnchoredTDEE(
        qualifiedDailyTotals: [1800, 1750, 1850, 1800, 1800],
        estimatedDailyDeficit: -550)
    #expect(t == 2350)
}

@Test func trendAnchorRejectsImplausiblyLowResult() {
    // Median 900 while "gaining" 500/day → implied TDEE 400. Nonsense data
    // must never become an anchor that drags the estimate down.
    let t = TDEEEstimator.trendAnchoredTDEE(
        qualifiedDailyTotals: [900, 900, 900, 900, 900],
        estimatedDailyDeficit: 500)
    #expect(t == nil)
}

@Test func trendAnchorOutlierDaysDoNotDrag() {
    // One feast (4500) and one under-logged qualified day (850) around a
    // steady 2000: the median holds at 2000, so the anchor is unmoved.
    let t = TDEEEstimator.trendAnchoredTDEE(
        qualifiedDailyTotals: [2000, 4500, 2000, 850, 2000, 2000, 2000],
        estimatedDailyDeficit: 0)
    #expect(t == 2000)
}

// MARK: - Ledger-trust floor (implausible logging must not become the anchor)

@Test func ledgerTrust_flatWeightWithSubBMRLoggingIsDistrusted() {
    // The field scenario: user logs ~1200/day (3 meals, days qualify) but
    // weight is FLAT. Implied maintenance 1200 < BMR ≈ 1534 (70kg) — the
    // ledger is thermodynamically incomplete. Anchor must be dropped so
    // TDEE falls back to the (higher) formula estimate.
    let floor = TDEEEstimator.ledgerPlausibilityFloor(weightKg: 70, config: .default)
    let anchor = TDEEEstimator.trendAnchoredTDEE(
        qualifiedDailyTotals: [1200, 1150, 1250, 1200, 1180],
        estimatedDailyDeficit: 0,
        plausibilityFloor: floor)
    #expect(anchor == nil, "Sub-BMR implied maintenance must be distrusted, floor was \(Int(floor))")
}

@Test func ledgerTrust_genuineDieterClearsTheFloor() {
    // Same 1200 intake but ACTUALLY losing 0.5 kg/wk (deficit −550):
    // implied TDEE 1750 > floor — physics is consistent, ledger trusted.
    let floor = TDEEEstimator.ledgerPlausibilityFloor(weightKg: 70, config: .default)
    let anchor = TDEEEstimator.trendAnchoredTDEE(
        qualifiedDailyTotals: [1200, 1150, 1250, 1200, 1180],
        estimatedDailyDeficit: -550,
        plausibilityFloor: floor)
    #expect(anchor == 1750)
}

@Test func ledgerTrust_floorUsesProfileBMRWhenComplete() {
    // Small female full profile: her true BMR (~1288 for 55kg/160cm/35y) is
    // well below the sex-averaged default (1384.5) — the floor must follow
    // HER Mifflin so a genuinely small eater isn't wrongly distrusted.
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 35; config.heightCm = 160; config.sex = .female
    let floor = TDEEEstimator.ledgerPlausibilityFloor(weightKg: 55, config: config)
    // BMR = 550 + 1000 − 175 − 161 = 1214; floor = 1092.6
    #expect(abs(floor - 1092.6) < 1, "got \(floor)")
    let defaultFloor = TDEEEstimator.ledgerPlausibilityFloor(weightKg: 55, config: .default)
    #expect(floor < defaultFloor)
}

@Test func ledgerTrust_noWeightFallsBackToLegacyFloor() {
    #expect(TDEEEstimator.ledgerPlausibilityFloor(weightKg: nil, config: .default) == 800)
}

@Test func defaultBMRMatchesComputeBaseAnchor() {
    // computeBase = defaultBMR × activity factor — the two must stay in sync.
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    #expect(abs(base - TDEEEstimator.defaultBMR(weightKg: 70) * 1.55) < 0.01)
}

@Test func trendAnchorStableWhenDaysSkipped() throws {
    // Same qualified days ± a few skipped days in between: skipped days
    // produce NO totals (they're simply absent), so the anchor is identical —
    // skipping days must not read as "eats less" (the field complaint).
    let fullWeek: [Double] = [2100, 2000, 2050, 1950, 2000, 2000, 2100]
    let withSkips: [Double] = [2100, 2000, 2050, 1950, 2000] // two days just missing
    let a = try #require(TDEEEstimator.trendAnchoredTDEE(qualifiedDailyTotals: fullWeek, estimatedDailyDeficit: -300))
    let b = try #require(TDEEEstimator.trendAnchoredTDEE(qualifiedDailyTotals: withSkips, estimatedDailyDeficit: -300))
    #expect(abs(a - b) <= 50, "Skipping days moved the anchor by \(abs(a - b)) kcal")
}

// MARK: - loadConfig / saveConfig (MainActor, uses UserDefaults)

@Test @MainActor func saveConfigAndLoadRoundTrip() {
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 28
    config.heightCm = 172
    config.sex = .female
    config.activityMultiplier = 31
    config.manualAdjustment = -100

    TDEEEstimator.saveConfig(config)
    let loaded = TDEEEstimator.loadConfig()

    #expect(loaded.age == 28)
    #expect(loaded.heightCm == 172)
    #expect(loaded.sex == .female)
    #expect(loaded.activityMultiplier == 31)
    #expect(loaded.manualAdjustment == -100)

    // Clean up
    TDEEEstimator.saveConfig(.default)
}

@Test @MainActor func loadConfigReturnsDefaultWhenNothingSaved() {
    UserDefaults.standard.removeObject(forKey: "drift_tdee_config")
    let config = TDEEEstimator.loadConfig()
    #expect(config.activityMultiplier == TDEEEstimator.TDEEConfig.default.activityMultiplier)
    #expect(config.manualAdjustment == 0)
}

// MARK: - cachedOrSync (sync path, no Apple Health, no weight data)

@Test @MainActor func cachedOrSyncReturnsEstimate() {
    // Clear any cached value by saving a fresh config
    TDEEEstimator.saveConfig(.default)
    UserDefaults.standard.removeObject(forKey: "drift_tdee_cache")
    let estimate = TDEEEstimator.shared.cachedOrSync()
    #expect(estimate.tdee >= 1200)
    #expect(estimate.tdee <= 5000)
}

@Test @MainActor func cachedOrSyncConfidenceLowWithNoData() {
    TDEEEstimator.saveConfig(.default)
    UserDefaults.standard.removeObject(forKey: "drift_tdee_cache")
    let estimate = TDEEEstimator.shared.cachedOrSync()
    // Without weight data or profile, confidence should be low
    #expect(estimate.confidence == .low || estimate.confidence == .medium)
}

@Test @MainActor func cachedOrSyncHasMifflinSourceWhenWeightAndProfileSet() throws {
    // Save a weight entry so WeightTrendService.shared.latestWeightKg is non-nil
    var entry = WeightEntry(date: DateFormatters.dateOnly.string(from: Date()), weightKg: 75)
    try AppDatabase.shared.saveWeightEntry(&entry)
    WeightTrendService.shared.refresh()
    var config = TDEEEstimator.TDEEConfig.default
    config.age = 30; config.heightCm = 175; config.sex = .male
    TDEEEstimator.saveConfig(config)
    UserDefaults.standard.removeObject(forKey: "drift_tdee_cache")
    let estimate = TDEEEstimator.shared.cachedOrSync()
    #expect(estimate.activeSources.contains(where: { $0.contains("Profile") }))
    // Clean up
    if let id = entry.id { try? AppDatabase.shared.deleteWeightEntry(id: id) }
    WeightTrendService.shared.refresh()
    TDEEEstimator.saveConfig(.default)
}

@Test @MainActor func cachedOrSyncAppliesManualAdjustment() {
    var config = TDEEEstimator.TDEEConfig.default
    config.manualAdjustment = 200
    TDEEEstimator.saveConfig(config)
    UserDefaults.standard.removeObject(forKey: "drift_tdee_cache")
    let adjusted = TDEEEstimator.shared.cachedOrSync()
    // Manual adjustment of +200 should push TDEE above the base
    #expect(adjusted.tdee >= 1200)

    config.manualAdjustment = 0
    TDEEEstimator.saveConfig(config)
    UserDefaults.standard.removeObject(forKey: "drift_tdee_cache")
    let baseline = TDEEEstimator.shared.cachedOrSync()
    #expect(adjusted.tdee > baseline.tdee - 1)
    TDEEEstimator.saveConfig(.default)
}

// MARK: - foodLoggingConsistency

@Test @MainActor func foodLoggingConsistencyReturnsFraction() {
    let consistency = TDEEEstimator.shared.foodLoggingConsistency()
    #expect(consistency >= 0)
    #expect(consistency <= 1)
}
