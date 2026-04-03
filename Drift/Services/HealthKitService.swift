import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

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

    func fetchUserProfile() -> UserProfile {
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

        // Height (latest sample)
        var heightCm: Double?
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            let semaphore = DispatchSemaphore(value: 0)
            let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                }
                semaphore.signal()
            }
            healthStore.execute(query)
            semaphore.wait()
        }

        Log.healthKit.info("Profile: age=\(age ?? -1), height=\(heightCm ?? -1)cm, sex=\(sex?.rawValue ?? "nil")")
        return UserProfile(age: age, heightCm: heightCm, sex: sex)
    }

    func syncWeight() async throws -> Int {
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
    }

    /// Force a full re-sync by clearing the saved anchor.
    func fullResyncWeight() async throws -> Int {
        let database = AppDatabase.shared
        try database.saveAnchor(dataType: "bodyMass", anchor: Data())
        Log.healthKit.info("Cleared weight sync anchor, performing full re-sync")
        return try await syncWeight()
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

    // MARK: - Cycle Tracking

    struct CycleEntry: Sendable, Identifiable {
        let id = UUID()
        let date: Date
        let flow: Int // 1=light, 2=medium, 3=heavy, 4=none/spotting ended

        var flowDisplay: String {
            switch flow {
            case 1: "Light"
            case 2: "Medium"
            case 3: "Heavy"
            case 4: "None"
            default: "Unspecified"
            }
        }
    }

    struct OvulationEntry: Sendable, Identifiable {
        let id = UUID()
        let date: Date
        let result: Int // 1=negative, 2=LH surge (positive), 3=indeterminate, 4=estrogen surge

        var isPositive: Bool { result == 2 || result == 4 }
    }

    struct BBTEntry: Sendable, Identifiable {
        let id = UUID()
        let date: Date
        let temperatureCelsius: Double
    }

    struct SpottingEntry: Sendable, Identifiable {
        let id = UUID()
        let date: Date
    }

    /// Check if user has any cycle data in Apple Health (last 90 days).
    func hasCycleData() async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        guard isAvailable,
              let menstrualType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return false }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -90, to: Date()) else { return false }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: menstrualType, predicate: predicate, limit: 1,
                                      sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples ?? []).count > 0)
            }
            healthStore.execute(query)
        }
        #endif
    }

    /// Fetch cycle history from Apple Health.
    func fetchCycleHistory(days: Int = 180) async throws -> [CycleEntry] {
        #if targetEnvironment(simulator)
        return Self.mockCycleData()
        #else
        guard isAvailable,
              let menstrualType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: menstrualType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let entries = (samples as? [HKCategorySample] ?? []).map { s in
                    CycleEntry(date: s.startDate, flow: s.value)
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
        #endif
    }

    /// Fetch ovulation test results from Apple Health.
    func fetchOvulationHistory(days: Int = 180) async throws -> [OvulationEntry] {
        #if targetEnvironment(simulator)
        return Self.mockOvulationData()
        #else
        guard isAvailable,
              let ovType = HKObjectType.categoryType(forIdentifier: .ovulationTestResult) else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: ovType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let entries = (samples as? [HKCategorySample] ?? []).map { s in
                    OvulationEntry(date: s.startDate, result: s.value)
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
        #endif
    }

    /// Fetch basal body temperature from Apple Health.
    func fetchBBTHistory(days: Int = 180) async throws -> [BBTEntry] {
        #if targetEnvironment(simulator)
        return Self.mockBBTData()
        #else
        guard isAvailable,
              let bbtType = HKObjectType.quantityType(forIdentifier: .basalBodyTemperature) else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: bbtType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let entries = (samples as? [HKQuantitySample] ?? []).map { s in
                    BBTEntry(date: s.startDate, temperatureCelsius: s.quantity.doubleValue(for: .degreeCelsius()))
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
        #endif
    }

    /// Fetch spotting/intermenstrual bleeding from Apple Health.
    func fetchSpottingHistory(days: Int = 180) async throws -> [SpottingEntry] {
        #if targetEnvironment(simulator)
        return Self.mockSpottingData()
        #else
        guard isAvailable,
              let spType = HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding) else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: spType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let entries = (samples as? [HKCategorySample] ?? []).map { s in
                    SpottingEntry(date: s.startDate)
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
        #endif
    }

    // MARK: - Cycle Mock Data (simulator only)

    /// Mock cycle data with varying cycle lengths (26, 28, 30 days).
    static func mockCycleData() -> [CycleEntry] {
        let cal = Calendar.current
        var entries: [CycleEntry] = []
        let cycleLengths = [30, 28, 26] // oldest to newest
        var offset = 5 // start 5 days ago for most recent period
        for i in 0..<3 {
            let cycleStart = cal.date(byAdding: .day, value: -offset, to: Date())!
            for day in 0..<5 {
                let date = cal.date(byAdding: .day, value: day, to: cycleStart)!
                let flow = day == 0 || day == 4 ? 1 : (day == 2 ? 3 : 2)
                entries.append(CycleEntry(date: date, flow: flow))
            }
            if i < 2 { offset += cycleLengths[2 - i] }
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Mock ovulation test data — positive LH surge around day 13-14 of each cycle.
    static func mockOvulationData() -> [OvulationEntry] {
        let cal = Calendar.current
        var entries: [OvulationEntry] = []
        let cycleLengths = [30, 28, 26]
        var offset = 5
        for i in 0..<3 {
            let cycleStart = cal.date(byAdding: .day, value: -offset, to: Date())!
            let ovDay = cycleLengths[2 - i] / 2
            // Negative test day before, positive on ovulation day
            if let negDate = cal.date(byAdding: .day, value: ovDay - 1, to: cycleStart) {
                entries.append(OvulationEntry(date: negDate, result: 1))
            }
            if let posDate = cal.date(byAdding: .day, value: ovDay, to: cycleStart) {
                entries.append(OvulationEntry(date: posDate, result: 2))
            }
            if i < 2 { offset += cycleLengths[2 - i] }
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Mock BBT data — ~36.3°C follicular, ~36.6°C luteal with noise.
    static func mockBBTData() -> [BBTEntry] {
        let cal = Calendar.current
        var entries: [BBTEntry] = []
        let cycleLengths = [30, 28, 26]
        var offset = 5
        for i in 0..<3 {
            let cycleStart = cal.date(byAdding: .day, value: -offset, to: Date())!
            let length = cycleLengths[2 - i]
            let ovDay = length / 2
            for day in 0..<length {
                guard let date = cal.date(byAdding: .day, value: day, to: cycleStart),
                      date <= Date() else { continue }
                let noise = Double.random(in: -0.1...0.1)
                let temp = day < ovDay ? 36.3 + noise : 36.6 + noise
                entries.append(BBTEntry(date: date, temperatureCelsius: temp))
            }
            if i < 2 { offset += cycleLengths[2 - i] }
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Mock spotting data — 1-2 random spotting days.
    static func mockSpottingData() -> [SpottingEntry] {
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: -18, to: Date()) else { return [] }
        return [SpottingEntry(date: date)]
    }

    /// Mock biometric data correlated with cycle phases.
    static func mockCycleBiometrics(periodStarts: [(start: Date, length: Int)]) -> (
        hrv: [(date: Date, ms: Double)],
        rhr: [(date: Date, bpm: Double)],
        sleep: [(date: Date, hours: Double)]
    ) {
        let cal = Calendar.current
        var hrv: [(date: Date, ms: Double)] = []
        var rhr: [(date: Date, bpm: Double)] = []
        var sleep: [(date: Date, hours: Double)] = []

        for (start, length) in periodStarts {
            let ovDay = length / 2
            for day in 0..<length {
                guard let date = cal.date(byAdding: .day, value: day, to: start),
                      date <= Date() else { continue }
                let noise = Double.random(in: -3...3)
                let sleepNoise = Double.random(in: -0.3...0.3)

                let (hrvVal, rhrVal, sleepVal): (Double, Double, Double)
                if day < 5 {
                    // Menstrual
                    hrvVal = 44 + noise; rhrVal = 64 + noise * 0.5; sleepVal = 7.1 + sleepNoise
                } else if day < ovDay - 1 {
                    // Follicular
                    hrvVal = 50 + noise; rhrVal = 60 + noise * 0.5; sleepVal = 7.5 + sleepNoise
                } else if day <= ovDay + 1 {
                    // Ovulation
                    hrvVal = 55 + noise; rhrVal = 62 + noise * 0.5; sleepVal = 7.3 + sleepNoise
                } else {
                    // Luteal
                    hrvVal = 40 + noise; rhrVal = 66 + noise * 0.5; sleepVal = 7.0 + sleepNoise
                }
                hrv.append((date: date, ms: max(20, hrvVal)))
                rhr.append((date: date, bpm: max(45, rhrVal)))
                sleep.append((date: date, hours: max(4, sleepVal)))
            }
        }
        return (hrv: hrv, rhr: rhr, sleep: sleep)
    }

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

    // MARK: - Sleep & Recovery Data

    struct SleepDetail: Sendable {
        let totalHours: Double
        let remHours: Double
        let deepHours: Double
        let lightHours: Double
        let awakeHours: Double
        let bedStart: Date?
        let bedEnd: Date?
    }

    /// Detailed sleep breakdown for a night.
    func fetchSleepDetail(for date: Date) async throws -> SleepDetail {
        guard isAvailable, let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return SleepDetail(totalHours: 0, remHours: 0, deepHours: 0, lightHours: 0, awakeHours: 0, bedStart: nil, bedEnd: nil)
        }
        // Last night's sleep: look from 6pm yesterday to noon today
        // This catches sleep that starts late evening and ends in the morning
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let evening = cal.date(byAdding: .hour, value: -6, to: startOfDay),
              let noon = cal.date(byAdding: .hour, value: 12, to: startOfDay) else {
            return SleepDetail(totalHours: 0, remHours: 0, deepHours: 0, lightHours: 0, awakeHours: 0, bedStart: nil, bedEnd: nil)
        }
        let predicate = HKQuery.predicateForSamples(withStart: evening, end: noon, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let sleepSamples = (samples ?? []).compactMap { $0 as? HKCategorySample }

                var rem = 0.0, deep = 0.0, light = 0.0, awake = 0.0, asleep = 0.0, inBed = 0.0
                var earliest: Date?, latest: Date?

                Log.healthKit.info("Sleep detail: \(sleepSamples.count) samples, values: \(sleepSamples.map(\.value))")

                // First pass: categorize all samples
                for s in sleepSamples {
                    let dur = s.endDate.timeIntervalSince(s.startDate) / 3600
                    if earliest == nil || s.startDate < earliest! { earliest = s.startDate }
                    if latest == nil || s.endDate > latest! { latest = s.endDate }

                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: rem += dur
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += dur
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue: light += dur
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: asleep += dur
                    case HKCategoryValueSleepAnalysis.awake.rawValue: awake += dur
                    case HKCategoryValueSleepAnalysis.inBed.rawValue: inBed += dur
                    default: asleep += dur
                    }
                }

                // If detailed stages (REM/Deep/Core) exist, use ONLY those.
                // Ignore both inBed and asleepUnspecified — they overlap with stages
                // from other HealthKit sources (WHOOP + iPhone = double counting).
                let hasDetailedStages = rem > 0 || deep > 0 || light > 0
                let total: Double
                if hasDetailedStages {
                    total = rem + deep + light
                } else if asleep > 0 {
                    total = asleep
                } else {
                    total = inBed
                }
                // Sanity cap
                let capped = min(total, 14.0)
                Log.healthKit.info("Sleep computed: total=\(String(format: "%.1f", capped))h rem=\(String(format: "%.1f", rem)) deep=\(String(format: "%.1f", deep)) light=\(String(format: "%.1f", light)) asleep=\(String(format: "%.1f", asleep)) inBed=\(String(format: "%.1f", inBed)) hasStages=\(hasDetailedStages)")

                continuation.resume(returning: SleepDetail(
                    totalHours: capped, remHours: rem, deepHours: deep,
                    lightHours: hasDetailedStages ? light : asleep, awakeHours: awake,
                    bedStart: earliest, bedEnd: latest
                ))
            }
            healthStore.execute(query)
        }
    }

    /// HRV (SDNN) for a date - latest reading.
    func fetchHRV(for date: Date) async throws -> Double {
        #if targetEnvironment(simulator)
        return 48
        #else
        try await fetchLatestQuantity(identifier: .heartRateVariabilitySDNN, for: date,
                                       unit: .secondUnit(with: .milli), windowDays: 1)
        #endif
    }

    /// Resting heart rate for a date.
    func fetchRestingHeartRate(for date: Date) async throws -> Double {
        #if targetEnvironment(simulator)
        return 62
        #else
        try await fetchLatestQuantity(identifier: .restingHeartRate, for: date,
                                       unit: .count().unitDivided(by: .minute()))
        #endif
    }

    /// Respiratory rate for a date.
    func fetchRespiratoryRate(for date: Date) async throws -> Double {
        #if targetEnvironment(simulator)
        return 15
        #else
        try await fetchLatestQuantity(identifier: .respiratoryRate, for: date,
                                       unit: .count().unitDivided(by: .minute()))
        #endif
    }

    /// Generic helper: fetch the latest sample of a quantity type for a date.
    private func fetchLatestQuantity(identifier: HKQuantityTypeIdentifier, for date: Date,
                                      unit: HKUnit, windowDays: Int = 0) async throws -> Double {
        guard isAvailable, let qType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let start = cal.date(byAdding: .day, value: -windowDays, to: startOfDay),
              let end = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: qType, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch sleep hours for multiple days (for trend chart).
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
        guard let data = try database.fetchAnchor(dataType: dataType) else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private nonisolated func saveAnchor(_ anchor: HKQueryAnchor, for dataType: String, database: AppDatabase) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
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
