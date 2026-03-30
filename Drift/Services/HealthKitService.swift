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
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let energy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) { types.insert(energy) }
        if let protein = HKObjectType.quantityType(forIdentifier: .dietaryProtein) { types.insert(protein) }
        if let carbs = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) { types.insert(carbs) }
        if let fat = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) { types.insert(fat) }
        if let fiber = HKObjectType.quantityType(forIdentifier: .dietaryFiber) { types.insert(fiber) }
        return types
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else {
            Log.healthKit.warning("HealthKit not available on this device")
            return
        }
        Log.healthKit.info("Requesting HealthKit authorization")
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        Log.healthKit.info("HealthKit authorization completed")
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
        async let active = fetchDaySum(typeIdentifier: .activeEnergyBurned, for: date)
        async let basal = fetchDaySum(typeIdentifier: .basalEnergyBurned, for: date)
        let result = try await (active, basal)
        Log.healthKit.debug("Calories: active=\(Int(result.0)) basal=\(Int(result.1))")
        return result
    }

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
        let steps = try await fetchDaySum(typeIdentifier: .stepCount, for: date, unit: .count())
        Log.healthKit.debug("Steps: \(Int(steps))")
        return steps
    }

    func fetchSleepHours(for date: Date) async throws -> Double {
        guard isAvailable, let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let evening = calendar.date(byAdding: .hour, value: -6, to: startOfDay),
              let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: evening, end: noon, options: [])

        let hours: Double = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let sleepSamples = (samples ?? []).compactMap { $0 as? HKCategorySample }

                var staged = 0.0, inBed = 0.0, unspecified = 0.0
                for s in sleepSamples {
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        staged += dur
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        unspecified += dur
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        inBed += dur
                    default: break // skip awake
                    }
                }
                // If detailed stages (REM/Deep/Core) exist, use ONLY those.
                // Don't add inBed or unspecified on top — they often overlap and cause double-counting
                // (e.g., WHOOP writes stages + iPhone writes inBed for the same night = 13h).
                // Only fall back to unspecified or inBed when no detailed stages are available.
                let totalSeconds: Double
                if staged > 0 {
                    totalSeconds = staged
                } else if unspecified > 0 {
                    totalSeconds = unspecified
                } else {
                    totalSeconds = inBed
                }
                // Sanity cap: sleep cannot exceed 14 hours in one night
                let capped = min(totalSeconds, 14 * 3600)
                continuation.resume(returning: capped / 3600)
            }
            healthStore.execute(query)
        }
        Log.healthKit.debug("Sleep: \(String(format: "%.1f", hours))h")
        return hours
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
        let evening = cal.date(byAdding: .hour, value: -6, to: startOfDay)! // 6pm previous day
        let noon = cal.date(byAdding: .hour, value: 12, to: startOfDay)!    // noon today
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
        guard isAvailable, let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return 0 }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: date)),
              let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let ms = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .secondUnit(with: .milli)) ?? 0
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    /// Resting heart rate for a date.
    func fetchRestingHeartRate(for date: Date) async throws -> Double {
        guard isAvailable, let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: rhrType, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let bpm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    /// Respiratory rate for a date.
    func fetchRespiratoryRate(for date: Date) async throws -> Double {
        guard isAvailable, let rrType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: rrType, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let rpm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
                continuation.resume(returning: rpm)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch sleep hours for multiple days (for trend chart).
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
