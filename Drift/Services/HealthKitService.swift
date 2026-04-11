import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    let healthStore = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
        if let basalEnergy = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) { types.insert(basalEnergy) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose) { types.insert(glucose) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let rhr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(rhr) }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let resp = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { types.insert(resp) }
        if let height = HKObjectType.quantityType(forIdentifier: .height) { types.insert(height) }
        types.insert(HKObjectType.workoutType())
        if let menstrual = HKObjectType.categoryType(forIdentifier: .menstrualFlow) { types.insert(menstrual) }
        if let ovulation = HKObjectType.categoryType(forIdentifier: .ovulationTestResult) { types.insert(ovulation) }
        if let cervical = HKObjectType.categoryType(forIdentifier: .cervicalMucusQuality) { types.insert(cervical) }
        if let spotting = HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding) { types.insert(spotting) }
        if let bbt = HKObjectType.quantityType(forIdentifier: .basalBodyTemperature) { types.insert(bbt) }
        if let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(bodyFat) }
        if let bmi = HKObjectType.quantityType(forIdentifier: .bodyMassIndex) { types.insert(bmi) }
        if let leanMass = HKObjectType.quantityType(forIdentifier: .leanBodyMass) { types.insert(leanMass) }
        // biologicalSex and dateOfBirth are characteristics — no auth needed
        return types
    }

    // Read-only — no write access requested. All data stays on device.
    private var writeTypes: Set<HKSampleType> { [] }

    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return HKHealthStore.isHealthDataAvailable()
        #endif
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            Log.healthKit.warning("HealthKit not available on this device")
            return
        }
        Log.healthKit.info("Requesting HealthKit authorization")
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        Log.healthKit.info("HealthKit authorization completed")
    }

    // MARK: - User Profile (age, height, sex)

    struct UserProfile: Sendable {
        let age: Int?
        let heightCm: Double?
        let sex: TDEEEstimator.Sex?
    }

    func fetchUserProfile() async -> UserProfile {
        guard isAvailable else { return UserProfile(age: nil, heightCm: nil, sex: nil) }

        // Biological sex
        let sex: TDEEEstimator.Sex?
        if let bioSex = try? healthStore.biologicalSex().biologicalSex {
            switch bioSex {
            case .male: sex = .male
            case .female: sex = .female
            default: sex = nil
            }
        } else {
            sex = nil
        }

        // Date of birth → age
        let age: Int?
        if let dob = try? healthStore.dateOfBirthComponents().date {
            age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
        } else {
            age = nil
        }

        // Height (latest sample) — async to avoid blocking main thread
        let heightCm: Double? = await withCheckedContinuation { continuation in
            guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
                continuation.resume(returning: nil)
                return
            }
            let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                let cm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: cm)
            }
            healthStore.execute(query)
        }

        Log.healthKit.info("Profile: age=\(age ?? -1), height=\(heightCm ?? -1)cm, sex=\(sex?.rawValue ?? "nil")")
        return UserProfile(age: age, heightCm: heightCm, sex: sex)
    }

    func syncWeight() async throws -> Int {
        #if targetEnvironment(simulator)
        return 0 // No real HealthKit weight data on simulator
        #else
        guard isAvailable,
              let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return 0 }

        let database = AppDatabase.shared
        let anchor = try loadAnchor(for: "bodyMass", database: database)
        Log.healthKit.info("Syncing weight (anchor: \(anchor != nil ? "exists" : "none"))")

        let (samples, newAnchor) = try await queryAnchoredWeight(type: weightType, anchor: anchor)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Group by date, keep the most recent sample per day
        var byDate: [String: HKQuantitySample] = [:]
        for sample in samples {
            let dateString = formatter.string(from: sample.startDate)
            if let existing = byDate[dateString] {
                if sample.startDate > existing.startDate {
                    byDate[dateString] = sample
                }
            } else {
                byDate[dateString] = sample
            }
        }

        Log.healthKit.info("HealthKit returned \(samples.count) samples across \(byDate.count) unique days")

        var count = 0
        for (dateString, sample) in byDate {
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            var entry = WeightEntry(date: dateString, weightKg: kg, source: "healthkit", syncedFromHk: true)
            try database.saveWeightEntry(&entry)
            count += 1
        }

        if let newAnchor {
            try saveAnchor(newAnchor, for: "bodyMass", database: database)
        }
        Log.healthKit.info("Synced \(count) weight entries from HealthKit")
        return count
    #endif
    }

    /// Sync body composition (body fat %, BMI) from Apple Health → body_composition table.
    func syncBodyComposition() async throws -> Int {
        #if targetEnvironment(simulator)
        return 0
        #else
        guard isAvailable else { return 0 }
        let database = AppDatabase.shared
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var count = 0

        // Sync body fat percentage
        if let fatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            let samples = try await queryRecentSamples(type: fatType, days: 90)
            for sample in samples {
                let dateStr = formatter.string(from: sample.startDate)
                let pct = sample.quantity.doubleValue(for: .percent()) * 100 // HK stores as 0.0-1.0
                // Check if we already have an entry for this date
                let existing = (try? database.fetchBodyComposition())?.first { $0.date == dateStr && $0.source == "healthkit" }
                if existing == nil {
                    var entry = BodyComposition(date: dateStr, bodyFatPct: pct, source: "healthkit")
                    try database.saveBodyComposition(&entry)
                    count += 1
                }
            }
        }

        // Sync BMI
        if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            let samples = try await queryRecentSamples(type: bmiType, days: 90)
            for sample in samples {
                let dateStr = formatter.string(from: sample.startDate)
                let bmi = sample.quantity.doubleValue(for: .count())
                // Update existing entry for this date or create new
                let existing = (try? database.fetchBodyComposition())?.first { $0.date == dateStr && $0.source == "healthkit" }
                if var entry = existing {
                    entry.bmi = bmi
                    try database.saveBodyComposition(&entry)
                } else {
                    var entry = BodyComposition(date: dateStr, bmi: bmi, source: "healthkit")
                    try database.saveBodyComposition(&entry)
                    count += 1
                }
            }
        }

        Log.healthKit.info("Synced \(count) body composition entries from HealthKit")
        return count
        #endif
    }

    private func queryRecentSamples(type: HKQuantityType, days: Int) async throws -> [HKQuantitySample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// Force a full re-sync by clearing the saved anchor.
    func fullResyncWeight() async throws -> Int {
        #if targetEnvironment(simulator)
        return 0
        #else
        let database = AppDatabase.shared
        try database.saveAnchor(dataType: "bodyMass", anchor: Data())
        Log.healthKit.info("Cleared weight sync anchor, performing full re-sync")
        return try await syncWeight()
        #endif
    }

    private func queryAnchoredWeight(type: HKQuantityType, anchor: HKQueryAnchor?) async throws -> ([HKQuantitySample], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, added, _, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: ((added ?? []).compactMap { $0 as? HKQuantitySample }, newAnchor))
            }
            healthStore.execute(query)
        }
    }

    func fetchCaloriesBurned(for date: Date) async throws -> (active: Double, basal: Double) {
        #if targetEnvironment(simulator)
        return (active: 420, basal: 1580)
        #else
        async let active = fetchDaySum(typeIdentifier: .activeEnergyBurned, for: date)
        async let basal = fetchDaySum(typeIdentifier: .basalEnergyBurned, for: date)
        let result = try await (active, basal)
        Log.healthKit.debug("Calories: active=\(Int(result.0)) basal=\(Int(result.1))")
        return result
        #endif
    }

    // MARK: - Apple Health Workouts

    struct HealthWorkout: Sendable, Identifiable {
        let id: UUID
        let type: String
        let duration: TimeInterval
        let calories: Double
        let date: Date

        var durationDisplay: String {
            let m = Int(duration) / 60
            let h = m / 60
            return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
        }
    }

    /// Fetch today's workouts from Apple Health.
    func fetchWorkouts(for date: Date) async throws -> [HealthWorkout] {
        #if targetEnvironment(simulator)
        return Self.mockWorkouts(for: date)
        #else
        guard isAvailable else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { w in
                    HealthWorkout(
                        id: w.uuid,
                        type: w.workoutActivityType.displayName,
                        duration: w.duration,
                        calories: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        date: w.startDate
                    )
                }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
        #endif
    }

    /// Fetch recent workouts (last N days).
    func fetchRecentWorkouts(days: Int = 7) async throws -> [HealthWorkout] {
        #if targetEnvironment(simulator)
        return Self.mockRecentWorkouts(days: days)
        #else
        guard isAvailable else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 100,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { w in
                    HealthWorkout(
                        id: w.uuid,
                        type: w.workoutActivityType.displayName,
                        duration: w.duration,
                        calories: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        date: w.startDate
                    )
                }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
        #endif
    }

    // MARK: - Sleep History

    struct SleepNight: Sendable {
        let date: Date
        let hours: Double
    }

    /// Fetch recent sleep data (hours per night, last N days).
    func fetchRecentSleepData(days: Int = 7) async throws -> [SleepNight] {
        #if targetEnvironment(simulator)
        // Mock data for simulator
        let cal = Calendar.current
        return (0..<days).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let hours = 6.5 + Double.random(in: -1...1.5) // 5.5-8h
            return SleepNight(date: date, hours: hours)
        }
        #else
        guard isAvailable else { return [] }
        var results: [SleepNight] = []
        let cal = Calendar.current
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            if let detail = try? await fetchSleepDetail(for: date), detail.totalHours > 0 {
                results.append(SleepNight(date: date, hours: detail.totalHours))
            }
        }
        return results
        #endif
    }

    // MARK: - Workout Mock Data (simulator only)

    static func mockWorkouts(for date: Date) -> [HealthWorkout] {
        // Return workouts matching the requested date from the full mock set
        let cal = Calendar.current
        return mockRecentWorkouts(days: 7).filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    static func mockRecentWorkouts(days: Int) -> [HealthWorkout] {
        let cal = Calendar.current
        var workouts: [HealthWorkout] = []
        // Today: morning run
        let today = Date()
        if let t = cal.date(bySettingHour: 7, minute: 15, second: 0, of: today) {
            workouts.append(HealthWorkout(id: UUID(), type: "Running", duration: 35 * 60, calories: 320, date: t))
        }
        // Yesterday: strength training
        if let y = cal.date(byAdding: .day, value: -1, to: today),
           let t = cal.date(bySettingHour: 18, minute: 0, second: 0, of: y) {
            workouts.append(HealthWorkout(id: UUID(), type: "Strength Training", duration: 55 * 60, calories: 280, date: t))
        }
        // 2 days ago: cycling
        if let d = cal.date(byAdding: .day, value: -2, to: today),
           let t = cal.date(bySettingHour: 8, minute: 30, second: 0, of: d) {
            workouts.append(HealthWorkout(id: UUID(), type: "Cycling", duration: 45 * 60, calories: 410, date: t))
        }
        // 4 days ago: yoga
        if let d = cal.date(byAdding: .day, value: -4, to: today),
           let t = cal.date(bySettingHour: 6, minute: 45, second: 0, of: d) {
            workouts.append(HealthWorkout(id: UUID(), type: "Yoga", duration: 60 * 60, calories: 180, date: t))
        }
        // 5 days ago: HIIT
        if let d = cal.date(byAdding: .day, value: -5, to: today),
           let t = cal.date(bySettingHour: 17, minute: 30, second: 0, of: d) {
            workouts.append(HealthWorkout(id: UUID(), type: "HIIT", duration: 25 * 60, calories: 350, date: t))
        }
        return workouts.sorted { $0.date > $1.date }
    }

    // Cycle tracking methods in HealthKitService+Cycle.swift
    // MARK: - Glucose

    /// Fetch glucose readings from Apple Health for a date range.
    func fetchGlucoseReadings(from startDate: Date, to endDate: Date) async throws -> [GlucoseReading] {
        guard isAvailable,
              let glucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }

                let readings = (samples ?? []).compactMap { sample -> GlucoseReading? in
                    guard let quantitySample = sample as? HKQuantitySample else { return nil }
                    let mgdl = quantitySample.quantity.doubleValue(for: HKUnit(from: "mg/dL"))
                    return GlucoseReading(
                        timestamp: ISO8601DateFormatter().string(from: quantitySample.startDate),
                        glucoseMgdl: mgdl,
                        source: "apple_health"
                    )
                }
                continuation.resume(returning: readings)
            }
            healthStore.execute(query)
        }
    }

    func fetchSteps(for date: Date) async throws -> Double {
        #if targetEnvironment(simulator)
        return 7842
        #else
        let steps = try await fetchDaySum(typeIdentifier: .stepCount, for: date, unit: .count())
        Log.healthKit.debug("Steps: \(Int(steps))")
        return steps
        #endif
    }

    /// Simplified sleep hours — delegates to fetchSleepDetail to avoid duplicate logic.
    func fetchSleepHours(for date: Date) async throws -> Double {
        #if targetEnvironment(simulator)
        return 7.4
        #else
        let detail = try await fetchSleepDetail(for: date)
        return detail.totalHours
        #endif
    }


    // Sleep & Recovery in HealthKitService+Sleep.swift

    // MARK: - History Methods (for baselines + sparklines)

    func fetchHRVHistory(days: Int) async throws -> [(date: Date, ms: Double)] {
        var result: [(Date, Double)] = []
        let cal = Calendar.current
        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let ms = try await fetchHRV(for: date)
            if ms > 0 { result.append((date, ms)) }
        }
        return result.reversed()
    }

    func fetchRestingHeartRateHistory(days: Int) async throws -> [(date: Date, bpm: Double)] {
        var result: [(Date, Double)] = []
        let cal = Calendar.current
        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let bpm = try await fetchRestingHeartRate(for: date)
            if bpm > 0 { result.append((date, bpm)) }
        }
        return result.reversed()
    }

    func fetchRespiratoryRateHistory(days: Int) async throws -> [(date: Date, rpm: Double)] {
        var result: [(Date, Double)] = []
        let cal = Calendar.current
        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let rpm = try await fetchRespiratoryRate(for: date)
            if rpm > 0 { result.append((date, rpm)) }
        }
        return result.reversed()
    }

    func fetchSleepHistory(days: Int) async throws -> [(date: Date, hours: Double)] {
        var result: [(Date, Double)] = []
        let cal = Calendar.current
        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let hours = try await fetchSleepHours(for: date)
            result.append((date, hours))
        }
        return result.reversed()
    }

    func writeNutrition(calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, date: Date) async throws {
        #if targetEnvironment(simulator)
        return // No write access on simulator
        #else
        guard isAvailable else { return }
        var samples: [HKQuantitySample] = []
        func addSample(_ id: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) {
            guard value > 0, let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date))
        }
        addSample(.dietaryEnergyConsumed, value: calories, unit: .kilocalorie())
        addSample(.dietaryProtein, value: proteinG, unit: .gram())
        addSample(.dietaryCarbohydrates, value: carbsG, unit: .gram())
        addSample(.dietaryFatTotal, value: fatG, unit: .gram())
        addSample(.dietaryFiber, value: fiberG, unit: .gram())
        guard !samples.isEmpty else { return }
        try await healthStore.save(samples)
        Log.healthKit.info("Wrote nutrition: \(Int(calories))cal \(Int(proteinG))P \(Int(carbsG))C \(Int(fatG))F")
    #endif
    }

    private func fetchDaySum(typeIdentifier: HKQuantityTypeIdentifier, for date: Date, unit: HKUnit = .kilocalorie()) async throws -> Double {
        guard isAvailable, let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated func loadAnchor(for dataType: String, database: AppDatabase) throws -> HKQueryAnchor? {
        guard let data = try database.fetchAnchor(dataType: dataType), !data.isEmpty else { return nil }
        // Gracefully handle corrupted anchor data
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private nonisolated func saveAnchor(_ anchor: HKQueryAnchor, for dataType: String, database: AppDatabase) throws {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            Log.healthKit.error("Failed to archive anchor for \(dataType)")
            return
        }
        try database.saveAnchor(dataType: dataType, anchor: data)
    }
}

// MARK: - Workout Activity Type Names

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .walking: "Walking"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .functionalStrengthTraining: "Strength Training"
        case .traditionalStrengthTraining: "Strength Training"
        case .coreTraining: "Core Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing: "Stair Climbing"
        case .dance: "Dance"
        case .pilates: "Pilates"
        case .boxing: "Boxing"
        case .kickboxing: "Kickboxing"
        case .martialArts: "Martial Arts"
        case .crossTraining: "Cross Training"
        case .flexibility: "Flexibility"
        case .cooldown: "Cooldown"
        case .mixedCardio: "Mixed Cardio"
        case .jumpRope: "Jump Rope"
        case .tennis: "Tennis"
        case .badminton: "Badminton"
        case .basketball: "Basketball"
        case .soccer: "Soccer"
        case .baseball: "Baseball"
        case .golf: "Golf"
        case .tableTennis: "Table Tennis"
        case .cricket: "Cricket"
        default: "Workout"
        }
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .walking: "figure.walk"
        case .swimming: "figure.pool.swim"
        case .hiking: "figure.hiking"
        case .yoga: "figure.yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "dumbbell.fill"
        case .highIntensityIntervalTraining: "flame.fill"
        case .elliptical: "figure.elliptical"
        case .rowing: "figure.rowing"
        case .dance: "figure.dance"
        case .coreTraining: "figure.core.training"
        default: "figure.mixed.cardio"
        }
    }
}
