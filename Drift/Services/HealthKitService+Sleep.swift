import Foundation
import HealthKit

// MARK: - Sleep & Recovery Data

extension HealthKitService {

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
    func fetchLatestQuantity(identifier: HKQuantityTypeIdentifier, for date: Date,
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
}
