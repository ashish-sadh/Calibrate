import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for the chat-driven medication tools introduced in design-574:
//   - log_medication writes both profile+log AND legacy DailyMedication
//   - add_medication idempotent profile creation
//   - ToolRanker disambiguation between "took X" (log) and "started X" (add)
//
// Service tests go through AppDatabase.shared (the prod singleton) — UUID-suffixed
// names keep parallel runs isolated, same pattern as MedicationServiceTests.

private func unique(_ stem: String) -> String { "\(stem)_\(UUID().uuidString.prefix(8))" }

// MARK: - MedicationService.logMedication: profile + log + legacy

@MainActor
@Test func logMedicationCreatesProfileWhenNoneExists() async throws {
    let name = unique("ozempic")
    _ = MedicationService.logMedication(name: name, doseMg: 0.5, doseUnit: "mg")

    let profile = try #require(try AppDatabase.shared.findMedication(named: name))
    #expect(profile.scheduleType == "asneeded",
            "Auto-created profile for chat-logged drug should be marked asneeded")

    let logs = try AppDatabase.shared.fetchMedicationLogs(medicationId: profile.id!, days: 1)
    #expect(logs.count >= 1)
    #expect(logs.first?.doseAmount == 0.5)
}

@MainActor
@Test func logMedicationReusesExistingProfile() async throws {
    let name = unique("metformin")
    var profile = Medication(name: name, doseAmount: 500, doseUnit: "mg")
    try AppDatabase.shared.saveMedicationProfile(&profile)

    _ = MedicationService.logMedication(name: name, doseMg: nil, doseUnit: nil)
    _ = MedicationService.logMedication(name: name.uppercased(), doseMg: 500, doseUnit: "mg")

    // Should be exactly one profile for this unique name (case-insensitive lookup).
    let all = try AppDatabase.shared.fetchAllMedications(includeArchived: true)
    let mine = all.filter { $0.name.lowercased() == name.lowercased() }
    #expect(mine.count == 1, "Logging same med (case-insensitive) must not duplicate the profile")

    let logs = try AppDatabase.shared.fetchMedicationLogs(medicationId: profile.id!, days: 1)
    #expect(logs.count >= 2, "Both log calls should attach to the same profile")
}

@MainActor
@Test func logMedicationStillWritesLegacyDailyMedication() async throws {
    // GLP1InsightTool / MedicationInfoTool / NotificationService still read from
    // the legacy DailyMedication table — design-574 keeps writing during transition.
    let name = unique("ozempic")
    _ = MedicationService.logMedication(name: name, doseMg: 0.5, doseUnit: "mg")

    let legacy = MedicationService.todayMedications()
    #expect(legacy.contains(where: { $0.name == name.capitalized }))
}

// MARK: - MedicationService.addMedicationProfile

@MainActor
@Test func addMedicationProfileCreatesNewRow() async throws {
    let name = unique("semaglutide")
    let brand = "Ozempic_\(UUID().uuidString.prefix(6))"

    let res = MedicationService.addMedicationProfile(
        name: name, brandName: brand,
        doseAmount: 0.5, doseUnit: "mg", scheduleType: "weekly",
        startDate: "2026-04-28"
    )

    let profile = try #require(try AppDatabase.shared.findMedication(named: name))
    #expect(profile.brandName == brand)
    #expect(profile.doseAmount == 0.5)
    #expect(profile.scheduleType == "weekly")
    #expect(profile.startDate == "2026-04-28")
    #expect(res.contains(brand))
    #expect(res.contains("weekly"))
}

@MainActor
@Test func addMedicationProfileIsIdempotentByGenericName() async throws {
    let name = unique("metformin")

    _ = MedicationService.addMedicationProfile(name: name, doseAmount: 500, doseUnit: "mg")
    let second = MedicationService.addMedicationProfile(
        name: name, doseAmount: 1000, doseUnit: "mg",
        scheduleType: "daily", reminderTime: "08:00"
    )

    let all = try AppDatabase.shared.fetchAllMedications(includeArchived: true)
    let mine = all.filter { $0.name == name.lowercased() }
    #expect(mine.count == 1, "Second add must update the existing row, not duplicate")
    #expect(mine[0].doseAmount == 1000)
    #expect(mine[0].reminderTime == "08:00")
    #expect(second.hasPrefix("Updated"), "Idempotent re-add should say 'Updated', not 'Added'")
}

@MainActor
@Test func addMedicationProfileIsIdempotentByBrand() async throws {
    let generic = unique("semaglutide")
    let brand = "Ozempic_\(UUID().uuidString.prefix(6))"

    _ = MedicationService.addMedicationProfile(
        name: generic, brandName: brand,
        doseAmount: 0.5, doseUnit: "mg", scheduleType: "weekly"
    )
    // User now says "I'm on Ozempic 1mg" — same drug under brand only.
    _ = MedicationService.addMedicationProfile(
        name: brand.lowercased(), doseAmount: 1.0, doseUnit: "mg", scheduleType: "weekly"
    )

    let byBrand = try #require(try AppDatabase.shared.findMedication(named: brand))
    let byGeneric = try #require(try AppDatabase.shared.findMedication(named: generic))
    #expect(byBrand.id == byGeneric.id, "Brand re-add must hit the same row as the generic add")
    #expect(byBrand.doseAmount == 1.0)
}

// #988: re-adding a weekly medication WITHOUT restating the schedule must not reset it to daily.
@MainActor
@Test func addMedicationProfileReAddKeepsWeeklySchedule() async throws {
    let name = unique("semaglutide")
    _ = MedicationService.addMedicationProfile(name: name, doseAmount: 0.5, doseUnit: "mg",
                                               scheduleType: "weekly", reminderDay: 1)
    // User re-adds ("I'm on <name> 1mg") — scheduleType defaults to "daily".
    _ = MedicationService.addMedicationProfile(name: name, doseAmount: 1.0, doseUnit: "mg")
    let profile = try #require(try AppDatabase.shared.findMedication(named: name))
    #expect(profile.scheduleType == "weekly", "re-add with default daily must not clobber stored weekly")
    #expect(profile.doseAmount == 1.0, "dose IS updated on re-add")
}

@MainActor
@Test func addMedicationProfileNormalizesNameToLowercase() async throws {
    let raw = "  \(unique("Metformin"))  "
    let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
    _ = MedicationService.addMedicationProfile(name: raw, doseAmount: 500)

    let profile = try AppDatabase.shared.findMedication(named: trimmed)
    #expect(profile != nil, "name should be trimmed + lowercased for lookup")
    #expect(profile?.name == trimmed)
}

@MainActor
@Test func addMedicationProfileDefaultsToDailyMg() async throws {
    let name = unique("atorvastatin")
    _ = MedicationService.addMedicationProfile(name: name, doseAmount: 20)
    let profile = try #require(try AppDatabase.shared.findMedication(named: name))
    #expect(profile.doseUnit == "mg")
    #expect(profile.scheduleType == "daily")
}

// MARK: - ToolRanker: log vs add disambiguation

@MainActor
@Test func toolRankerRoutesAddPhrasesToAddMedication() {
    ToolRegistration.registerAll()
    let cases = [
        "i'm on wegovy",
        "im on ozempic",
        "i am on metformin",
        "started ozempic 0.5mg weekly",
        "starting wegovy next week",
        "add metformin 500mg daily",
        "add a medication",
        "i was prescribed atorvastatin",
        "got prescribed mounjaro",
        "new prescription for ozempic",
    ]
    var correct = 0
    for q in cases {
        let tools = ToolRanker.rank(query: q.lowercased(), screen: .food)
        if tools.first?.name == "add_medication" { correct += 1 }
        else { print("MISS (add_medication): '\(q)' → \(tools.first?.name ?? "nil")") }
    }
    print("📊 add_medication routing: \(correct)/\(cases.count)")
    #expect(correct >= cases.count - 1, "At most 1 routing miss for add_medication triggers")
}

@MainActor
@Test func toolRankerRoutesTookPhrasesToLogMedication() {
    ToolRegistration.registerAll()
    let cases = [
        "took my ozempic",
        "took my metformin",
        "injected my semaglutide",
        "log my ozempic",
        "took my glp1 shot",
        "took my wegovy",
        "took my tirzepatide",
    ]
    var correct = 0
    for q in cases {
        let tools = ToolRanker.rank(query: q.lowercased(), screen: .food)
        if tools.first?.name == "log_medication" { correct += 1 }
        else { print("MISS (log_medication): '\(q)' → \(tools.first?.name ?? "nil")") }
    }
    print("📊 log_medication routing: \(correct)/\(cases.count)")
    #expect(correct >= cases.count - 1, "At most 1 routing miss for log_medication triggers")
}

@MainActor
@Test func toolRankerDoesNotConfuseAddAndLog() {
    // Dangerous failure mode: "started ozempic" → log_medication (creates a
    // dose log against no profile) or "took my ozempic" → add_medication
    // (resets the user's prescription). Both wreck the user's profile.
    ToolRegistration.registerAll()

    let addOnlyPhrases = ["i'm on wegovy", "started ozempic", "add metformin"]
    for q in addOnlyPhrases {
        let top = ToolRanker.rank(query: q.lowercased(), screen: .food).first?.name
        #expect(top != "log_medication", "'\(q)' must not route to log_medication (got \(top ?? "nil"))")
    }

    let logOnlyPhrases = ["took my ozempic", "injected semaglutide", "log my metformin"]
    for q in logOnlyPhrases {
        let top = ToolRanker.rank(query: q.lowercased(), screen: .food).first?.name
        #expect(top != "add_medication", "'\(q)' must not route to add_medication (got \(top ?? "nil"))")
    }
}

// MARK: - Tool registration

@MainActor
@Test func chatMedicationToolsAreRegistered() {
    ToolRegistration.registerAll()
    #expect(ToolRegistry.shared.tool(named: "add_medication") != nil)
    #expect(ToolRegistry.shared.tool(named: "log_medication") != nil)
}

// MARK: - add_medication tool handler: preHook + dose validation

@MainActor
@Test func addMedicationToolPreHookRejectsMissingName() async {
    ToolRegistration.registerAll()
    let tool = try! #require(ToolRegistry.shared.tool(named: "add_medication"))
    let params = ToolCallParams(values: ["dose": "0.5"])
    let preHook = try! #require(tool.preHook)
    switch await preHook(params) {
    case .invalid(let reason): #expect(reason.lowercased().contains("medication"))
    default: Issue.record("preHook should reject missing name")
    }
}

@MainActor
@Test func addMedicationToolPreHookRejectsMissingDose() async {
    ToolRegistration.registerAll()
    let tool = try! #require(ToolRegistry.shared.tool(named: "add_medication"))
    let params = ToolCallParams(values: ["name": "metformin"])
    let preHook = try! #require(tool.preHook)
    switch await preHook(params) {
    case .invalid(let reason): #expect(reason.lowercased().contains("dose"))
    default: Issue.record("preHook should reject missing dose")
    }
}

@MainActor
@Test func addMedicationToolHandlerNormalizesUnknownSchedule() async throws {
    ToolRegistration.registerAll()
    let tool = try #require(ToolRegistry.shared.tool(named: "add_medication"))
    let name = unique("metformin")
    let params = ToolCallParams(values: ["name": name, "dose": "500", "schedule": "occasionally"])

    let result = await tool.handler(params)
    if case .text = result {
        let profile = try #require(try AppDatabase.shared.findMedication(named: name))
        #expect(profile.scheduleType == "daily", "Unknown schedule must fall back to daily")
    } else {
        Issue.record("Handler should succeed for valid params (got \(result))")
    }
}
