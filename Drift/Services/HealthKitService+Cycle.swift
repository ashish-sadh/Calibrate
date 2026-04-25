import Foundation
import HealthKit
import DriftCore

// MARK: - Cycle Tracking

extension HealthKitService {

    // CycleEntry / OvulationEntry / BBTEntry / SpottingEntry value types live in DriftCore.
    typealias CycleEntry = DriftCore.CycleEntry
    typealias OvulationEntry = DriftCore.OvulationEntry
    typealias BBTEntry = DriftCore.BBTEntry
    typealias SpottingEntry = DriftCore.SpottingEntry

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
                let flow = day == 0 || day == 4 ? 2 : (day == 2 ? 4 : 3) // HK: 2=light, 3=medium, 4=heavy
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
}
