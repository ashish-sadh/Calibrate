import Foundation
import SkipFuse
import DriftCore

/// What a user-initiated permission ask actually did. `denied` is the one
/// that needs an escape hatch: Android stops showing the sheet once a denial
/// is USER_FIXED, so re-tapping the button can never recover on its own.
public enum HealthPermissionOutcome: Sendable {
    case alreadyGranted, granted, partial, denied, unavailable, timedOut
}

/// Health Connect adapter — the Android half of the `DriftPlatform.health`
/// seam (HealthKit fills it on iOS). Reads weights written by other apps
/// (scale apps like Renpho), plus steps/calories/sleep from trackers.
///
/// All Health Connect calls go through the blocking+JSON Kotlin facade
/// (`HealthConnectFacade.kt`) because the Kotlin client API is suspend-only,
/// which Skip's reflection bridge cannot call. Facade calls are blocking, so
/// every one runs off-main via `onFacadeQueue`.
public final class HealthConnectService: HealthDataProvider {
    public static let shared = HealthConnectService()
    private init() {}

    private static let facadeClass = "drift.android.HealthConnectFacade"
    /// Weight-sync anchor: epoch millis of the newest record we've ingested.
    private static let anchorKey = "hcWeightAnchorMillis"
    /// Permission-sheet poll cadence + a hard cap, so a user who wanders off
    /// inside Health Connect leaves a loop that ends rather than one that
    /// spins forever (#1235's lesson).
    private static let pollSeconds: Double = 0.25
    private static let pollNanos: UInt64 = 250_000_000
    private static let permissionWaitCapSeconds: Double = 180

    // MARK: - Facade plumbing

    private static func onFacadeQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    // The JNI bridge exists only in the Android compile; Skip's Darwin
    // bridging pass compiles this same file for iphonesimulator, so every
    // facade touchpoint lives behind one #if with inert Darwin stubs.
    #if os(Android)
    private static func facadePing() throws -> String? {
        try AnyDynamicObject(className: facadeClass, arguments: []).ping() as String?
    }
    private static func facadeAvailability() -> Int {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).availabilityStatus() as Int?) ?? 0
    }
    private static func facadeHasAllPermissions() throws -> Bool {
        try AnyDynamicObject(className: facadeClass, arguments: []).hasAllPermissions() as Bool? ?? false
    }
    private static func facadeHasAllReadPermissions() throws -> Bool {
        try AnyDynamicObject(className: facadeClass, arguments: []).hasAllReadPermissions() as Bool? ?? false
    }
    private static func facadeRequestPermissions() -> Bool {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).requestPermissions() as Bool?) ?? false
    }
    private static func facadePermissionFlowPoll() -> Int {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).permissionFlowPoll() as Int?) ?? 0
    }
    private static func facadePermissionFlowGrantedCount() -> Int {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).permissionFlowGrantedCount() as Int?) ?? -1
    }
    private static func facadeOpenSettings() -> Bool {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).openHealthConnectSettings() as Bool?) ?? false
    }
    private static func facadeReadBodyFatJson(_ start: Int64, _ end: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).readBodyFatJson(start, end) as String? ?? "[]"
    }
    private static func facadeReadWeightsJson(_ start: Int64, _ end: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).readWeightsJson(start, end) as String? ?? "[]"
    }
    private static func facadeReadStepsJson(_ start: Int64, _ end: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).readStepsJson(start, end) as String? ?? "{}"
    }
    private static func facadeReadCaloriesJson(_ start: Int64, _ end: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).readCaloriesJson(start, end) as String? ?? "{}"
    }
    private static func facadeReadSleepJson(_ start: Int64, _ end: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).readSleepJson(start, end) as String? ?? "[]"
    }
    private static func facadeReadLatestHeightCm() throws -> Double {
        try AnyDynamicObject(className: facadeClass, arguments: []).readLatestHeightCm() as Double? ?? -1
    }
    private static func facadeReadWorkoutsJson(_ start: Int64, _ end: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).readWorkoutsJson(start, end) as String? ?? "[]"
    }
    #else
    private static func facadePing() throws -> String? { nil }
    private static func facadeAvailability() -> Int { 0 }
    private static func facadeHasAllPermissions() throws -> Bool { false }
    private static func facadeHasAllReadPermissions() throws -> Bool { false }
    private static func facadeRequestPermissions() -> Bool { false }
    private static func facadePermissionFlowPoll() -> Int { 0 }
    private static func facadePermissionFlowGrantedCount() -> Int { -1 }
    private static func facadeOpenSettings() -> Bool { false }
    private static func facadeReadBodyFatJson(_ start: Int64, _ end: Int64) throws -> String { "[]" }
    private static func facadeReadWeightsJson(_ start: Int64, _ end: Int64) throws -> String { "[]" }
    private static func facadeReadStepsJson(_ start: Int64, _ end: Int64) throws -> String { "{}" }
    private static func facadeReadCaloriesJson(_ start: Int64, _ end: Int64) throws -> String { "{}" }
    private static func facadeReadSleepJson(_ start: Int64, _ end: Int64) throws -> String { "[]" }
    private static func facadeReadLatestHeightCm() throws -> Double { -1 }
    private static func facadeReadWorkoutsJson(_ start: Int64, _ end: Int64) throws -> String { "[]" }
    #endif

    private static func jsonArray(_ raw: String) -> [[String: Any]] {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return parsed
    }

    private static func jsonObject(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return parsed
    }

    /// Logged once at launch — proves the Swift↔Kotlin reflective bridge.
    public static func bridgeSmokeTest() {
        Task.detached {
            do {
                let result = try await onFacadeQueue { try facadePing() }
                logger.info("HealthConnect bridge ping: \(result ?? "nil")")
            } catch {
                logger.error("HealthConnect bridge ping FAILED: \(error)")
            }
        }
    }

    // MARK: - HealthDataProvider

    @MainActor public var isAvailable: Bool {
        // Cheap sync status check (no coroutine involved on the Kotlin side).
        Self.facadeAvailability() == 1
    }

    /// Ask, don't wait. The launch catch-up (`DriftAndroidApp.onLaunch`) runs
    /// this ahead of the weight-trend + TDEE refresh, so blocking on a sheet
    /// the user can sit on for minutes would strand both (#1212's failure
    /// mode). User-initiated syncs call `requestAuthorizationInteractive()`,
    /// which does wait for the real answer.
    @MainActor public func requestAuthorization() async throws {
        if try await Self.onFacadeQueue({ try Self.facadeHasAllPermissions() }) { return }
        // launch() fires an Activity contract — main thread only, and
        // @MainActor IS the Android main looper.
        _ = Self.facadeRequestPermissions()
    }

    /// Await the real permission answer before returning, so the sync that
    /// follows can't run while the grant sheet is still on screen (#1207 — the
    /// first tap used to import nothing, every time). The result arrives as
    /// companion state on the Kotlin facade because an Activity result cannot
    /// call back across Skip's bridge, so it has to be polled.
    @MainActor public func requestAuthorizationInteractive() async -> HealthPermissionOutcome {
        if (try? await Self.onFacadeQueue { try Self.facadeHasAllReadPermissions() }) == true {
            return .alreadyGranted
        }
        guard Self.facadeRequestPermissions() else { return .unavailable }

        var waited: Double = 0
        while waited < Self.permissionWaitCapSeconds {
            try? await Task.sleep(nanoseconds: Self.pollNanos)
            waited += Self.pollSeconds
            let status = (try? await Self.onFacadeQueue { Self.facadePermissionFlowPoll() }) ?? 0
            guard status == 2 else { continue }   // 1 = sheet still up
            let granted = (try? await Self.onFacadeQueue { Self.facadePermissionFlowGrantedCount() }) ?? 0
            // Zero grants after a completed flow means denied — and once
            // Android marks the denial USER_FIXED the sheet silently
            // auto-dismisses, so the button alone can never recover.
            if granted <= 0 { return .denied }
            let all = (try? await Self.onFacadeQueue { try Self.facadeHasAllReadPermissions() }) ?? false
            return all ? .granted : .partial
        }
        return .timedOut
    }

    /// 1 available · 2 provider update required · 0 unavailable. Concrete-class
    /// member on purpose: `HealthDataProvider` must not grow a tri-state only
    /// one platform has.
    @MainActor public var availability: Int { Self.facadeAvailability() }

    /// Route out of a terminal denial — opens Health Connect's own permission
    /// screen. False when nothing on the device could handle it.
    @MainActor @discardableResult public func openHealthConnectSettings() -> Bool {
        Self.facadeOpenSettings()
    }

    @MainActor public func fetchUserProfile() async -> HealthUserProfile {
        let cm: Double? = (try? await Self.onFacadeQueue { try Self.facadeReadLatestHeightCm() }) ?? nil
        let height = (cm ?? -1) > 0 ? cm : nil
        return HealthUserProfile(age: nil, heightCm: height, sex: nil)
    }

    // MARK: Weight (the headline feature)

    @MainActor public func syncWeight() async throws -> Int {
        let anchor = DriftPlatform.keyValueStore.double(forKey: Self.anchorKey)
        // First sync: pull a year of history. After: overlap the anchor by 48h
        // so edits/late arrivals near the boundary are never missed (upsert
        // makes re-ingestion harmless).
        let start: Double
        if anchor > 0 {
            start = anchor - 48 * 3600 * 1000
        } else {
            start = Date().addingTimeInterval(-365 * 24 * 3600).timeIntervalSince1970 * 1000
        }
        return try await Self.ingestWeights(startMillis: Int64(start))
    }

    @MainActor public func fullResyncWeight() async throws -> Int {
        DriftPlatform.keyValueStore.removeObject(forKey: Self.anchorKey)
        let fiveYearsAgo = Date().addingTimeInterval(-5 * 365 * 24 * 3600).timeIntervalSince1970 * 1000
        return try await Self.ingestWeights(startMillis: Int64(fiveYearsAgo))
    }

    private static func ingestWeights(startMillis: Int64) async throws -> Int {
        let endMillis = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let raw = try await onFacadeQueue {
            try facadeReadWeightsJson(startMillis, endMillis)
        }
        let records = jsonArray(raw)
        guard !records.isEmpty else { return 0 }

        var count = 0
        var newestMillis: Int64 = startMillis
        for record in records {
            guard let date = record["date"] as? String,
                  let kg = record["kg"] as? Double, kg > 0 else { continue }
            // "healthkit" is the repo-wide marker for platform-health-synced
            // entries — the upsert priority rules (never overwrite manual/
            // deleted) key off it, so Health Connect uses the same source tag.
            var entry = WeightEntry(date: date, weightKg: kg, source: "healthkit", syncedFromHk: true)
            try AppDatabase.shared.saveWeightEntry(&entry)
            count += 1
            if let t = record["tMillis"] as? Double {
                newestMillis = max(newestMillis, Int64(t))
            }
        }
        DriftPlatform.keyValueStore.set(Double(newestMillis), forKey: anchorKey)
        logger.info("HealthConnect weight sync: \(records.count) day-records, \(count) saved")
        return count
    }

    // MARK: Steps / calories / sleep

    private static func dayBounds(_ date: Date) -> (Int64, Int64) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
    }

    @MainActor public func fetchSteps(for date: Date) async throws -> Double {
        let (start, end) = Self.dayBounds(date)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeReadStepsJson(start, end)
        }
        return Self.jsonObject(raw)["steps"] as? Double ?? 0
    }

    @MainActor public func fetchCaloriesBurned(for date: Date) async throws -> CaloriesBurned {
        let (start, end) = Self.dayBounds(date)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeReadCaloriesJson(start, end)
        }
        let parsed = Self.jsonObject(raw)
        let active = parsed["active"] as? Double ?? 0
        let total = parsed["total"] as? Double ?? 0
        // Health Connect's total includes active; basal = the remainder.
        return CaloriesBurned(active: active, basal: max(0, total - active))
    }

    @MainActor public func fetchSleepHours(for date: Date) async throws -> Double {
        // Sessions ENDING on `date` — search from the prior noon to capture
        // overnight sleep.
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let searchStart = dayStart.addingTimeInterval(-12 * 3600)
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeReadSleepJson(
                Int64(searchStart.timeIntervalSince1970 * 1000),
                Int64(dayEnd.timeIntervalSince1970 * 1000)
            )
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let target = formatter.string(from: date)
        return Self.jsonArray(raw)
            .first { ($0["date"] as? String) == target }
            .flatMap { $0["hours"] as? Double } ?? 0
    }

    @MainActor public func fetchRecentSleepData(days: Int) async throws -> [SleepNight] {
        let end = Date()
        let start = end.addingTimeInterval(-Double(days + 1) * 86400)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeReadSleepJson(
                Int64(start.timeIntervalSince1970 * 1000),
                Int64(end.timeIntervalSince1970 * 1000)
            )
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return Self.jsonArray(raw).compactMap { record in
            guard let dateString = record["date"] as? String,
                  let date = formatter.date(from: dateString),
                  let hours = record["hours"] as? Double else { return nil }
            return SleepNight(date: date, hours: hours)
        }
    }

    @MainActor public func fetchSleepHistory(days: Int) async throws -> [(date: Date, hours: Double)] {
        try await fetchRecentSleepData(days: days).map { (date: $0.date, hours: $0.hours) }
    }

    @MainActor public func fetchRecentWorkouts(days: Int) async throws -> [HealthWorkout] {
        let end = Date()
        let start = end.addingTimeInterval(-Double(days) * 86400)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeReadWorkoutsJson(
                Int64(start.timeIntervalSince1970 * 1000),
                Int64(end.timeIntervalSince1970 * 1000)
            )
        }
        return HealthWorkout.decode(fromFacadeJSON: raw)
    }

    // MARK: Not yet backed by Health Connect — honest empties.
    // (Views for these gate on data presence, not on the seam being non-nil.)

    @MainActor public func fetchSleepDetail(for date: Date) async throws -> SleepDetail {
        // Stage breakdown isn't wired yet — report total hours only.
        let hours = (try? await fetchSleepHours(for: date)) ?? 0
        return SleepDetail(totalHours: hours, remHours: 0, deepHours: 0,
                           lightHours: 0, awakeHours: 0, bedStart: nil, bedEnd: nil)
    }
    @MainActor public func fetchHRV(for date: Date) async throws -> Double { 0 }
    @MainActor public func fetchRestingHeartRate(for date: Date) async throws -> Double { 0 }
    @MainActor public func fetchRespiratoryRate(for date: Date) async throws -> Double { 0 }
    @MainActor public func fetchGlucoseReadings(from startDate: Date, to endDate: Date) async throws -> [GlucoseReading] { [] }
    @MainActor public func fetchCycleHistory(days: Int) async throws -> [CycleEntry] { [] }
    @MainActor public func fetchOvulationHistory(days: Int) async throws -> [OvulationEntry] { [] }
    @MainActor public func fetchBBTHistory(days: Int) async throws -> [BBTEntry] { [] }
    @MainActor public func fetchSpottingHistory(days: Int) async throws -> [SpottingEntry] { [] }
    @MainActor public func hasCycleData() async -> Bool { false }
    @MainActor public func fetchHRVHistory(days: Int) async throws -> [(date: Date, ms: Double)] { [] }
    @MainActor public func fetchRestingHeartRateHistory(days: Int) async throws -> [(date: Date, bpm: Double)] { [] }
    @MainActor public func fetchRespiratoryRateHistory(days: Int) async throws -> [(date: Date, rpm: Double)] { [] }
    /// Body fat % from Health Connect → body_composition, mirroring iOS's
    /// 90-day window and dedup (`HealthKitService.syncBodyComposition`). No
    /// BMI: Health Connect has no BMI record type, and deriving one from
    /// weight+height would be fabricating a reading the user never took.
    @MainActor public func syncBodyComposition() async throws -> Int {
        let end = Date()
        let start = end.addingTimeInterval(-90 * 86400)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeReadBodyFatJson(
                Int64(start.timeIntervalSince1970 * 1000),
                Int64(end.timeIntervalSince1970 * 1000) + 60_000
            )
        }
        let records = Self.jsonArray(raw)
        guard !records.isEmpty else { return 0 }

        let existing = (try? AppDatabase.shared.fetchBodyComposition()) ?? []
        var count = 0
        for record in records {
            guard let date = record["date"] as? String,
                  let pct = record["pct"] as? Double, pct > 0 else { continue }
            // Health Connect's Percentage is ALREADY 0-100 — iOS multiplies by
            // 100 only because HealthKit stores 0.0-1.0.
            if existing.contains(where: { $0.date == date && $0.source == "healthkit" }) { continue }
            var entry = BodyComposition(date: date, bodyFatPct: pct, source: "healthkit")
            try AppDatabase.shared.saveBodyComposition(&entry)
            count += 1
        }
        logger.info("HealthConnect body-comp sync: \(records.count) day-records, \(count) saved")
        return count
    }
}
