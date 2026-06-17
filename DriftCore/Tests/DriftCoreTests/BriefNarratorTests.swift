import Foundation
@testable import DriftCore
import Testing

// MARK: - Fixtures (pure — no DB, no MainActor, no model call)

private func alertSignal(
    _ id: String = "protein-low",
    title: String = "Protein below target",
    detail: String = "Protein has trailed your goal for 3 days.",
    direction: BriefSignal.GoalDirection = .against
) -> BriefSignal {
    BriefSignal(id: id, source: .alert, title: title, detail: detail, goalDirection: direction)
}

private func patternSignal(
    _ id: String = "pattern-protein-sleep",
    title: String = "Protein ↔ Sleep",
    detail: String = "Sleep dipped on the same days protein did.",
    direction: BriefSignal.GoalDirection = .neutral
) -> BriefSignal {
    BriefSignal(id: id, source: .pattern, title: title, detail: detail, goalDirection: direction)
}

private func input(_ signals: [BriefSignal], thin: Bool = false) -> BriefInput {
    BriefInput(signals: signals, isThinData: thin, dataDayCount: thin ? 1 : 12)
}

// MARK: - Prompt structure

@Test func buildPromptListsEachSignalWithItsIdAndFact() {
    let prompt = BriefNarrator.buildPrompt(from: input([alertSignal(), patternSignal()]))
    #expect(prompt.contains("id=protein-low"))
    #expect(prompt.contains("id=pattern-protein-sleep"))
    #expect(prompt.contains("Protein has trailed your goal for 3 days."))
    // Must instruct a JSON array capped at maxItems.
    #expect(prompt.contains("JSON array"))
    #expect(prompt.contains("1-\(BriefNarrator.maxItems)"))
}

// MARK: - Parse happy path

@Test func parseDecodesGroundedJsonIntoItems() {
    let raw = """
    [
      {"sourceSignalId":"protein-low","title":"Protein dipped 3 days","detail":"Your protein trailed your goal for 3 days running.","seedQuery":"How do I hit my protein goal this week?"}
    ]
    """
    let items = BriefNarrator.parse(raw, input: input([alertSignal(), patternSignal()]))
    #expect(items.count == 1)
    #expect(items.first?.title == "Protein dipped 3 days")
    #expect(items.first?.sourceSignalId == "protein-low")
    #expect(items.first?.seedQuery == "How do I hit my protein goal this week?")
}

@Test func parseDerivesAlignmentFromSignalNotFromModel() {
    // Model emits no alignment field at all; parse must derive it from the source signal's direction.
    let raw = #"[{"sourceSignalId":"protein-low","title":"Protein low","detail":"Trailing goal.","seedQuery":"q"}]"#
    let against = BriefNarrator.parse(raw, input: input([alertSignal(direction: .against)]))
    #expect(against.first?.alignment == .against)

    let aligned = BriefNarrator.parse(raw, input: input([alertSignal(direction: .aligned)]))
    #expect(aligned.first?.alignment == .aligned)

    let neutralRaw = #"[{"sourceSignalId":"pattern-protein-sleep","title":"Pattern","detail":"They move together.","seedQuery":"q"}]"#
    let neutral = BriefNarrator.parse(neutralRaw, input: input([patternSignal(direction: .neutral)]))
    #expect(neutral.first?.alignment == .neutral)
}

@Test func parseFillsSeedQueryWhenModelOmitsIt() {
    let raw = #"[{"sourceSignalId":"protein-low","title":"Protein low","detail":"Trailing goal.","seedQuery":""}]"#
    let items = BriefNarrator.parse(raw, input: input([alertSignal()]))
    #expect(items.first?.seedQuery.isEmpty == false)
}

// MARK: - Parse defenses

@Test func parseCapsAtMaxItems() {
    let signals = (1...6).map { alertSignal("a\($0)", title: "A\($0)", detail: "detail \($0)") }
    let entries = signals.map {
        #"{"sourceSignalId":"\#($0.id)","title":"\#($0.title)","detail":"insight","seedQuery":"q"}"#
    }.joined(separator: ",")
    let items = BriefNarrator.parse("[\(entries)]", input: input(signals))
    #expect(items.count == BriefNarrator.maxItems)
}

@Test func parseDropsEntriesWithUnknownSignalId() {
    let raw = """
    [
      {"sourceSignalId":"ghost","title":"Made up","detail":"No such signal.","seedQuery":"q"},
      {"sourceSignalId":"protein-low","title":"Real","detail":"Trailing goal.","seedQuery":"q"}
    ]
    """
    let items = BriefNarrator.parse(raw, input: input([alertSignal()]))
    #expect(items.map(\.sourceSignalId) == ["protein-low"])
}

@Test func parseDedupsBySourceSignalId() {
    let raw = """
    [
      {"sourceSignalId":"protein-low","title":"First","detail":"Trailing goal.","seedQuery":"q"},
      {"sourceSignalId":"protein-low","title":"Second","detail":"Trailing goal again.","seedQuery":"q"}
    ]
    """
    let items = BriefNarrator.parse(raw, input: input([alertSignal()]))
    #expect(items.count == 1)
    #expect(items.first?.title == "First")
}

@Test func parseThinDataOrEmptyInputReturnsNoItems() {
    let raw = #"[{"sourceSignalId":"protein-low","title":"T","detail":"d","seedQuery":"q"}]"#
    #expect(BriefNarrator.parse(raw, input: input([alertSignal()], thin: true)).isEmpty)
    #expect(BriefNarrator.parse(raw, input: input([])).isEmpty)
}

@Test func parseRecoversArrayFromChattyOrFencedResponse() {
    let raw = """
    Sure! Here is your brief:
    ```json
    [{"sourceSignalId":"protein-low","title":"Protein low","detail":"Trailing goal.","seedQuery":"q"}]
    ```
    Hope that helps.
    """
    let items = BriefNarrator.parse(raw, input: input([alertSignal()]))
    #expect(items.count == 1)
    #expect(items.first?.sourceSignalId == "protein-low")
}

@Test func parseReturnsEmptyOnGarbageResponse() {
    #expect(BriefNarrator.parse("I cannot help with that.", input: input([alertSignal()])).isEmpty)
}

// MARK: - Grounding predicate (#877 safety property — the over-claim bug class)

@Test func narrationGroundsOnlyInSuppliedSignals() {
    let signals = input([alertSignal(), patternSignal()])

    // Grounded: the only number ("3") is present in a supplied signal.
    #expect(BriefNarrator.isGrounded(
        title: "Protein dipped 3 days",
        detail: "Sleep slid on the same 3 days — recovery risk.",
        in: signals
    ))

    // Over-claim: "2.3" kg is a number no signal computed → rejected (the 2-point-extrapolation class).
    #expect(!BriefNarrator.isGrounded(
        title: "On track",
        detail: "You lost 2.3 kg this week.",
        in: signals
    ))

    // No numbers at all → trivially grounded (pure rephrasing is allowed).
    #expect(BriefNarrator.isGrounded(
        title: "Protein is slipping",
        detail: "It has been under your goal lately.",
        in: signals
    ))
}

@Test func groundingGuardsDigitFormNumbersOnly_knownLimit() {
    // Documented scope (not a bug): the predicate guards digit-form numbers, so a spelled-out
    // hallucination slips past — the prompt's "never state a number" rule + #885's live eval are
    // the guards for that. Pinned so a future reader doesn't mistake the gap for a defect.
    let signals = input([alertSignal(detail: "Protein trailed your goal lately.")])
    #expect(BriefNarrator.isGrounded(title: "Down forty-two pounds", detail: "Great work.", in: signals))
}

@Test func parseDropsEntriesWithEmptyTitleOrDetail() {
    let raw = """
    [
      {"sourceSignalId":"protein-low","title":"","detail":"non-empty","seedQuery":"q"},
      {"sourceSignalId":"protein-low","title":"non-empty","detail":"","seedQuery":"q"}
    ]
    """
    #expect(BriefNarrator.parse(raw, input: input([alertSignal()])).isEmpty)
}

@Test func groundingUsesWholeTokensNotSubstrings() {
    // Supplied has "15"; a claimed "5" must NOT pass off it as a substring.
    let signals = input([alertSignal(detail: "You logged 15 days this month.")])
    #expect(!BriefNarrator.isGrounded(title: "5 day streak", detail: "Nice work.", in: signals))
    #expect(BriefNarrator.isGrounded(title: "15 days logged", detail: "Nice work.", in: signals))
}

@Test func parseDropsUngroundedItemButKeepsGroundedSibling() {
    // End-to-end: parse must apply the grounding filter, not just the predicate in isolation.
    let raw = """
    [
      {"sourceSignalId":"protein-low","title":"Lost weight","detail":"You dropped 2.3 kg.","seedQuery":"q"},
      {"sourceSignalId":"pattern-protein-sleep","title":"Linked","detail":"Protein and sleep moved together over 3 days.","seedQuery":"q"}
    ]
    """
    let items = BriefNarrator.parse(raw, input: input([alertSignal(), patternSignal()]))
    #expect(items.map(\.sourceSignalId) == ["pattern-protein-sleep"])
}
