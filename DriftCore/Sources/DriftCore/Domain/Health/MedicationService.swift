import Foundation

@MainActor
public enum MedicationService {

    /// Log a single dose. Resolves a `Medication` profile by name; auto-creates
    /// one (asneeded schedule) if the user hasn't onboarded the drug yet so
    /// the chat-driven flow never dead-ends. The legacy `daily_medication`
    /// table is also written for one cycle so MedicationInfoTool / GLP1
    /// readers (which still query the flat log) keep returning data.
    public static func logMedication(name: String, doseMg: Double?, doseUnit: String?) -> String {
        let now = Date()
        let nowISO = ISO8601DateFormatter().string(from: now)
        let unit = doseUnit ?? "mg"
        // Drop hallucinated non-finite doses before they reach GRDB or the
        // formatter. The LLM extractor can return .infinity / .nan via
        // params.double — persisting those corrupts MedicationLog and
        // historically trapped at Int(dose) during response rendering (#772).
        let sanitizedDose: Double? = doseMg.flatMap { $0.isFinite ? $0 : nil }

        // Profile + log path (design-574)
        let profile = resolveOrCreateProfile(name: name, doseAmount: sanitizedDose, doseUnit: unit)
        if let pid = profile.id {
            var log = MedicationLog(medicationId: pid, takenAt: nowISO, doseAmount: sanitizedDose)
            try? AppDatabase.shared.saveMedicationLog(&log)
        }

        // Legacy flat-log path — kept until MedicationInfoTool / GLP1InsightTool / NotificationService
        // migrate off DailyMedication. Both writes succeed or fail independently; neither
        // blocks the other.
        var legacy = DailyMedication(name: name.capitalized, doseMg: sanitizedDose, doseUnit: unit, loggedAt: nowISO)
        try? AppDatabase.shared.saveMedication(&legacy)

        var response = "Logged \(profile.displayName)"
        if let dose = sanitizedDose {
            response += " (\(formatDose(dose))\(unit))"
        }
        response += "."
        return response
    }

    /// Format a dose value without crashing on hallucinated extremes.
    /// `Int(dose)` traps when `dose` is non-finite, NaN, or outside Int's range;
    /// the LLM extractor can emit any of these. Callers should already drop
    /// non-finite values, but this is the last line of defense.
    nonisolated static func formatDose(_ dose: Double) -> String {
        guard dose.isFinite else { return "?" }
        if dose.rounded() == dose, abs(dose) < Double(Int.max / 2) {
            return String(Int(dose))
        }
        return String(dose)
    }

    /// Add a medication to the user's profile (design-574 `add_medication`
    /// chat flow). Returns a friendly confirmation. Idempotent on generic
    /// name or brand name — re-adding "Ozempic" after the generic
    /// "semaglutide" was added updates the existing row in place rather
    /// than creating a duplicate, so "I'm on Wegovy" twice doesn't litter
    /// the user's profile.
    public static func addMedicationProfile(
        name: String,
        brandName: String? = nil,
        doseAmount: Double,
        doseUnit: String = "mg",
        scheduleType: String = "daily",
        reminderTime: String? = nil,
        reminderDay: Int? = nil,
        startDate: String? = nil,
        notes: String? = nil
    ) -> String {
        // Reject hallucinated non-finite doseAmount before it reaches GRDB.
        // The handler in ToolRegistration.swift only checks `dose > 0` which
        // lets +Infinity through (.nan is caught by `> 0` because NaN > x is false).
        guard doseAmount.isFinite else {
            return "What dose? Got an unreadable number — try '0.5mg' or '500mg'."
        }
        let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedBrand = brandName?.trimmingCharacters(in: .whitespaces)
        let resolvedBrand: String? = (normalizedBrand?.isEmpty ?? true) ? nil : normalizedBrand

        let existingByName = (try? AppDatabase.shared.findMedication(named: normalizedName)) ?? nil
        let existingByBrand: Medication? = resolvedBrand.flatMap {
            (try? AppDatabase.shared.findMedication(named: $0)) ?? nil
        }
        let existing = existingByName ?? existingByBrand

        var profile: Medication
        if var current = existing {
            // Idempotent update path: keep generic name + existing brand if no
            // new brand was supplied. "I'm on Ozempic 1mg" must not overwrite
            // the generic name "semaglutide" that the user added earlier.
            current.brandName = resolvedBrand ?? current.brandName
            current.doseAmount = doseAmount
            current.doseUnit = doseUnit
            // #988: don't clobber a stored "weekly" with the default "daily" when the user
            // re-adds without restating the schedule — only take an explicitly non-default value.
            current.scheduleType = (scheduleType == "daily") ? current.scheduleType : scheduleType
            current.reminderTime = reminderTime ?? current.reminderTime
            current.reminderDay = reminderDay ?? current.reminderDay
            current.startDate = startDate ?? current.startDate
            current.isActive = true
            current.notes = notes ?? current.notes
            profile = current
        } else {
            profile = Medication(
                name: normalizedName,
                brandName: resolvedBrand,
                doseAmount: doseAmount,
                doseUnit: doseUnit,
                scheduleType: scheduleType,
                reminderTime: reminderTime,
                reminderDay: reminderDay,
                startDate: startDate,
                isActive: true,
                notes: notes
            )
        }
        try? AppDatabase.shared.saveMedicationProfile(&profile)

        let doseStr = formatDose(doseAmount)
        let verb = existing == nil ? "Added" : "Updated"
        var response = "\(verb) \(profile.displayName) \(doseStr)\(doseUnit)"
        if scheduleType != "daily" {
            response += " (\(scheduleType))"
        }
        if let time = reminderTime {
            response += ". Reminder set for \(time)"
        }
        response += "."
        return response
    }

    /// Resolve an existing Medication profile by name/brand, or create a
    /// minimal asneeded profile so a log call always has something to attach to.
    private static func resolveOrCreateProfile(name: String, doseAmount: Double?, doseUnit: String) -> Medication {
        if let existing = (try? AppDatabase.shared.findMedication(named: name)) ?? nil {
            return existing
        }
        var newProfile = Medication(
            name: name.lowercased(),
            brandName: nil,
            doseAmount: doseAmount ?? 0,
            doseUnit: doseUnit,
            scheduleType: "asneeded",
            startDate: DateFormatters.todayString,
            isActive: true
        )
        try? AppDatabase.shared.saveMedicationProfile(&newProfile)
        return newProfile
    }

    public static func todayMedications() -> [DailyMedication] {
        (try? AppDatabase.shared.fetchTodayMedications()) ?? []
    }

    /// Most recent log timestamp for a named medication, or nil if never logged.
    public static func lastDoseTime(for name: String) -> Date? {
        let logs = (try? AppDatabase.shared.fetchMedications(for: name, days: 365)) ?? []
        guard let latest = logs.first else { return nil }
        return ISO8601DateFormatter().date(from: latest.loggedAt)
    }

    /// Local-time hours (fractional Double, e.g. 13.5 = 1:30 PM) for recent logs
    /// of a named medication. Used to compute typical dose time for smart reminders.
    public static func recentDoseHours(for name: String, days: Int = 30) -> [Double] {
        let logs = (try? AppDatabase.shared.fetchMedications(for: name, days: days)) ?? []
        return logs.compactMap { log in
            guard let date = ISO8601DateFormatter().date(from: log.loggedAt) else { return nil }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard let hour = comps.hour, let minute = comps.minute else { return nil }
            return Double(hour) + Double(minute) / 60.0
        }
    }

    /// Names of medications logged at least `minLogs` times in the last `days` days.
    /// These are candidates for smart dose reminders.
    public static func consistentMedicationNames(days: Int = 30, minLogs: Int = 3) -> [String] {
        let all = (try? AppDatabase.shared.fetchAllRecentMedications(days: days)) ?? []
        var counts: [String: Int] = [:]
        for med in all { counts[med.name, default: 0] += 1 }
        return counts.filter { $0.value >= minLogs }.map(\.key).sorted()
    }
}
