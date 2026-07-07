import Foundation
import HealthKit
import DriftCore

/// Apple Health nutrition write-back (#934). Listens on the DB mutation seam
/// (`DriftPlatform.nutritionWriter`) and mirrors logged entries into Health as
/// dietary samples — energy CONSUMED (never active energy) + protein, carbs,
/// fat, fiber.
///
/// Double-count policy (user decision, 2026-07-07): writing is a user toggle,
/// OFF by default. If another app is detected writing nutrition — at enable
/// time or on any later write — Drift warns, AUTO-DISABLES the toggle, and
/// records the reason for Settings. Drift only ever manages its own samples:
/// each carries `HKMetadataKeySyncIdentifier` = "drift-food-<entryId>-<kind>",
/// so edits REPLACE (higher sync version) instead of duplicating, deletes
/// remove exactly what Drift wrote, and re-syncing is idempotent.
actor HealthNutritionSyncService: HealthNutritionWriter {
    static let shared = HealthNutritionSyncService()

    /// Own store instance — HKHealthStore is thread-safe and cheap; keeps
    /// this actor off the @MainActor HealthKitService hot path.
    private let store = HKHealthStore()

    private static let typeByKind: [NutritionSampleSpec.Kind: HKQuantityTypeIdentifier] = [
        .energyKcal: .dietaryEnergyConsumed,   // dietary, NOT activeEnergyBurned
        .proteinG: .dietaryProtein,
        .carbsG: .dietaryCarbohydrates,
        .fatG: .dietaryFatTotal,
        .fiberG: .dietaryFiber,
    ]

    private static let unitByKind: [NutritionSampleSpec.Kind: HKUnit] = [
        .energyKcal: .kilocalorie(),
        .proteinG: .gram(), .carbsG: .gram(), .fatG: .gram(), .fiberG: .gram(),
    ]

    private static var shareTypes: Set<HKSampleType> {
        Set(typeByKind.values.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }

    // MARK: - Enable flow (Settings)

    enum EnableOutcome: Equatable {
        case enabled
        /// Health share permission denied for all nutrition types.
        case authDenied
        /// Another app is writing nutrition — toggle left OFF (app names attached).
        case foreignDetected([String])
        case unavailable
    }

    /// Full opt-in flow: request share authorization, then scan the recent
    /// window for other apps writing nutrition. Only flips the preference on
    /// when the path is clear.
    func requestEnable() async -> EnableOutcome {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do { try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.shareTypes) }
        catch { return .authDenied }

        let denied = Self.shareTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingDenied }
        if denied { return .authDenied }

        let foreign = await foreignNutritionSources(daysBack: 14)
        if !foreign.isEmpty {
            await MainActor.run { Preferences.healthNutritionAutoDisableReason = Self.reason(for: foreign) }
            return .foreignDetected(foreign)
        }
        await MainActor.run { Preferences.healthNutritionWriteEnabled = true }
        return .enabled
    }

    // MARK: - Live write-back (DB seam)

    nonisolated func entrySaved(_ entry: FoodEntry) {
        Task { await self.sync(entry) }
    }

    nonisolated func entryDeleted(id: Int64) {
        Task { await self.deleteSamples(entryId: id) }
    }

    private func sync(_ entry: FoodEntry) async {
        guard await MainActor.run(body: { Preferences.healthNutritionWriteEnabled }) else { return }
        let specs = NutritionHealthSync.specs(for: entry)
        guard !specs.isEmpty else { return }

        // Per-day foreign check — the no-double-count guarantee. Another
        // app writing the same day trips the auto-disable.
        let foreign = await foreignNutritionSources(on: specs[0].date)
        guard foreign.isEmpty else {
            await autoDisable(foreign: foreign)
            return
        }
        await save(specs: specs)
    }

    private func deleteSamples(entryId: Int64) async {
        guard await MainActor.run(body: { Preferences.healthNutritionWriteEnabled }) else { return }
        let ids = NutritionHealthSync.syncIdentifiers(entryId: entryId)
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ids)
        for type in Self.shareTypes {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    private func save(specs: [NutritionSampleSpec]) async {
        // Sync version must strictly increase per re-save so HealthKit
        // replaces rather than rejects — millisecond clock is plenty.
        let version = Int(Date().timeIntervalSince1970 * 1000)
        let samples: [HKQuantitySample] = specs.compactMap { spec in
            guard let id = Self.typeByKind[spec.kind],
                  let type = HKQuantityType.quantityType(forIdentifier: id),
                  let unit = Self.unitByKind[spec.kind] else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: spec.value),
                start: spec.date, end: spec.date,
                metadata: [
                    HKMetadataKeySyncIdentifier: spec.syncIdentifier,
                    HKMetadataKeySyncVersion: version,
                ])
        }
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            Log.healthKit.info("Health nutrition write: \(samples.count) samples")
        } catch {
            Log.healthKit.error("Health nutrition write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Foreign-source detection (double-count guard)

    private func foreignNutritionSources(on date: Date) async -> [String] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return await foreignNutritionSources(start: start, end: end)
    }

    private func foreignNutritionSources(daysBack: Int) async -> [String] {
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) else { return [] }
        return await foreignNutritionSources(start: start, end: end)
    }

    private func foreignNutritionSources(start: Date, end: Date) async -> [String] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return [] }
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: 200, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples ?? [])
            }
            store.execute(q)
        }
        let names = samples
            .map(\.sourceRevision.source)
            .filter { $0.bundleIdentifier != bundleId }
            .map(\.name)
        return Array(Set(names)).sorted()
    }

    private func autoDisable(foreign: [String]) async {
        let reason = Self.reason(for: foreign)
        await MainActor.run {
            Preferences.healthNutritionWriteEnabled = false
            Preferences.healthNutritionAutoDisableReason = reason
            NotificationCenter.default.post(name: .healthNutritionAutoDisabled, object: nil)
        }
        Log.healthKit.warning("Health nutrition write auto-disabled: \(reason)")
    }

    private static func reason(for foreign: [String]) -> String {
        "\(foreign.joined(separator: ", ")) is already writing nutrition to Apple Health — Drift stopped writing to avoid double counting."
    }

    // MARK: - Past sync (explicit, Settings)

    struct PastSyncSummary: Equatable {
        var entriesWritten = 0
        var daysSkipped = 0
        var foreignApps: [String] = []
    }

    /// Backfill history into Health. `days == nil` means all history.
    /// Idempotent: sync identifiers make re-runs replace, never duplicate.
    /// Days where another app already wrote nutrition are skipped (reported
    /// in the summary) — the no-double-count rule applied to the past.
    func syncPast(days: Int?) async -> PastSyncSummary {
        var summary = PastSyncSummary()
        let cutoff = days.flatMap { d -> String? in
            guard let date = Calendar.current.date(byAdding: .day, value: -d, to: Date()) else { return nil }
            return DateFormatters.dateOnly.string(from: date)
        }
        let entries = (try? AppDatabase.shared.fetchFoodEntries(fromDate: cutoff)) ?? []
        let byDay = Dictionary(grouping: entries) { $0.date ?? "" }

        for (day, dayEntries) in byDay.sorted(by: { $0.key < $1.key }) {
            guard let dayDate = DateFormatters.dateOnly.date(from: day) else { continue }
            let foreign = await foreignNutritionSources(on: dayDate)
            if !foreign.isEmpty {
                summary.daysSkipped += 1
                summary.foreignApps = Array(Set(summary.foreignApps + foreign)).sorted()
                continue
            }
            let specs = dayEntries.flatMap { NutritionHealthSync.specs(for: $0) }
            guard !specs.isEmpty else { continue }
            await save(specs: specs)
            summary.entriesWritten += dayEntries.count
        }
        return summary
    }
}

extension Notification.Name {
    /// Posted when the writer auto-disables the Health nutrition toggle
    /// (foreign app detected) so Settings can refresh its state.
    static let healthNutritionAutoDisabled = Notification.Name("drift.healthNutritionAutoDisabled")
}
