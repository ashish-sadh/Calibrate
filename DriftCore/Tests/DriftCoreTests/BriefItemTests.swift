import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — deterministic value, identity, and persistence contracts for narrated brief items.
@Suite struct BriefItemTests {

    @Test func initializerPreservesRenderContentAndUsesSignalIdentity() {
        let item = BriefItem(
            title: "Protein dipped",
            detail: "Protein was below target on three days.",
            seedQuery: "How can I raise my protein this week?",
            sourceSignalId: "protein-low-2026-07-21",
            alignment: .against
        )

        #expect(item.id == "protein-low-2026-07-21")
        #expect(item.title == "Protein dipped")
        #expect(item.detail == "Protein was below target on three days.")
        #expect(item.seedQuery == "How can I raise my protein this week?")
        #expect(item.sourceSignalId == "protein-low-2026-07-21")
        #expect(item.alignment == .against)
    }

    @Test func sharedSignalIdentityDoesNotCollapseDifferentRenderContent() {
        let original = BriefItem(
            title: "Sleep improved",
            detail: "Sleep duration rose this week.",
            seedQuery: "What helped my sleep?",
            sourceSignalId: "sleep-duration",
            alignment: .aligned
        )
        let regenerated = BriefItem(
            title: "Sleep held steady",
            detail: "Sleep duration remained consistent this week.",
            seedQuery: "How can I keep my sleep consistent?",
            sourceSignalId: "sleep-duration",
            alignment: .neutral
        )

        #expect(original.id == regenerated.id)
        #expect(original != regenerated)
    }

    @Test(arguments: [
        BriefItem.GoalAlignment.aligned,
        .against,
        .neutral,
    ])
    func codableRoundTripPreservesEveryGoalAlignment(_ alignment: BriefItem.GoalAlignment) throws {
        let item = BriefItem(
            title: "Hydration pattern",
            detail: "Water intake tracked with afternoon energy.",
            seedQuery: "Tell me more about this hydration pattern.",
            sourceSignalId: "hydration-energy",
            alignment: alignment
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(BriefItem.self, from: data)

        #expect(decoded == item)
        #expect(decoded.id == "hydration-energy")
    }
}
