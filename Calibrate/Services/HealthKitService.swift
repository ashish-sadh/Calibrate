import Foundation
import HealthKit

/// Actor managing all HealthKit interactions.
/// Thread-safe, handles authorization, queries, and background delivery.
actor HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    private let database = AppDatabase.shared

    // MARK: - Types to read/write

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
        if let basalEnergy = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) { types.insert(basalEnergy) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
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

    // MARK: - Authorization

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    // MARK: - Weight Sync

    /// Sync weight entries from HealthKit using anchored queries.
    /// Returns the number of new entries synced.
    func syncWeight() async throws -> Int {
        guard isAvailable,
              let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return 0 }

        let anchor = try loadAnchor(for: "bodyMass")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: weightType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, added, _, newAnchor, error in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }

                Task {
                    do {
                        if let error { throw error }

                        var count = 0
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.locale = Locale(identifier: "en_US_POSIX")

                        for sample in (added ?? []) {
                            guard let quantitySample = sample as? HKQuantitySample else { continue }
                            let kg = quantitySample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                            let dateString = formatter.string(from: quantitySample.startDate)

                            var entry = WeightEntry(
                                date: dateString,
                                weightKg: kg,
                                source: "healthkit",
                                syncedFromHk: true
                            )
                            try await self.database.saveWeightEntry(&entry)
                            count += 1
                        }

                        if let newAnchor {
                            try await self.saveAnchor(newAnchor, for: "bodyMass")
                        }

                        continuation.resume(returning: count)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Energy Burned (query on demand, not persisted)

    /// Fetch total calories burned today (active + basal).
    func fetchCaloriesBurned(for date: Date) async throws -> (active: Double, basal: Double) {
        async let active = fetchSum(typeIdentifier: .activeEnergyBurned, for: date)
        async let basal = fetchSum(typeIdentifier: .basalEnergyBurned, for: date)
        return try await (active, basal)
    }

    /// Fetch step count for a date.
    func fetchSteps(for date: Date) async throws -> Double {
        try await fetchSum(typeIdentifier: .stepCount, for: date)
    }

    /// Fetch sleep duration for the night before the given date (hours).
    func fetchSleepHours(for date: Date) async throws -> Double {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let previousEvening = calendar.date(byAdding: .hour, value: -12, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: previousEvening, end: startOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let totalSeconds = (samples ?? [])
                    .compactMap { $0 as? HKCategorySample }
                    .filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                continuation.resume(returning: totalSeconds / 3600)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Write Nutrition to HealthKit

    func writeNutrition(calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, date: Date) async throws {
        guard isAvailable else { return }

        var samples: [HKQuantitySample] = []

        func addSample(_ identifier: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) {
            guard value > 0, let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        addSample(.dietaryEnergyConsumed, value: calories, unit: .kilocalorie())
        addSample(.dietaryProtein, value: proteinG, unit: .gram())
        addSample(.dietaryCarbohydrates, value: carbsG, unit: .gram())
        addSample(.dietaryFatTotal, value: fatG, unit: .gram())
        addSample(.dietaryFiber, value: fiberG, unit: .gram())

        guard !samples.isEmpty else { return }
        try await healthStore.save(samples)
    }

    // MARK: - Private Helpers

    private func fetchSum(typeIdentifier: HKQuantityTypeIdentifier, for date: Date) async throws -> Double {
        guard isAvailable,
              let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else { return 0 }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        let unit: HKUnit = typeIdentifier == .stepCount ? .count() : .kilocalorie()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    private func loadAnchor(for dataType: String) throws -> HKQueryAnchor? {
        guard let data = try database.fetchAnchor(dataType: dataType) else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, for dataType: String) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        try database.saveAnchor(dataType: dataType, anchor: data)
    }
}
