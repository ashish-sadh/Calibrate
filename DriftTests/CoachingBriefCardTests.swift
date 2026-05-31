import XCTest
import SwiftUI
@testable import Drift
import DriftCore

/// Tier-1 tests for `CoachingBriefCard` — the proactive "Today's Brief" surface (#878).
///
/// We test the pure `payload(from:)` factory + the goal-aware `accentColor(for:)` mapping
/// rather than the SwiftUI tree (the render layer is dumb, covered by `#Preview`). The
/// logic worth pinning: "cap to 3, never a wall; empty → thin-data onboarding nudge, never
/// an empty shell; alignment drives a goal-aware color, never good/bad". These stay stable
/// as the S2 narrator (#877) that produces the `BriefItem`s evolves underneath.
@MainActor
final class CoachingBriefCardTests: XCTestCase {

    // MARK: - Fixtures

    private func item(_ id: String, alignment: BriefItem.GoalAlignment = .neutral) -> BriefItem {
        BriefItem(
            title: "Title \(id)",
            detail: "Detail \(id)",
            seedQuery: "Seed \(id)?",
            sourceSignalId: id,
            alignment: alignment
        )
    }

    // MARK: - Payload factory: 0 / 1 / 3 / >3 / thin-data states

    func testZeroItemsYieldsThinDataNudgeNotEmptyShell() {
        // Zero qualifying insights must render the onboarding nudge, never an empty card.
        XCTAssertEqual(CoachingBriefCard.payload(from: []), .thinData)
    }

    func testSingleItemYieldsBriefWithThatItem() {
        let only = item("a", alignment: .aligned)
        XCTAssertEqual(CoachingBriefCard.payload(from: [only]), .brief([only]))
    }

    func testThreeItemsYieldsBriefWithAllThree() {
        let items = [item("a"), item("b"), item("c")]
        XCTAssertEqual(CoachingBriefCard.payload(from: items), .brief(items))
    }

    func testMoreThanThreeItemsCapsToFirstThree() {
        // "Render 1-3 rows (never a wall)" — the factory caps to maxItems, keeping order.
        let items = [item("a"), item("b"), item("c"), item("d"), item("e")]
        let expected = [item("a"), item("b"), item("c")]
        XCTAssertEqual(CoachingBriefCard.payload(from: items), .brief(expected))

        guard case .brief(let rendered) = CoachingBriefCard.payload(from: items) else {
            return XCTFail("Expected a .brief payload")
        }
        XCTAssertEqual(rendered.count, CoachingBriefCard.maxItems)
        XCTAssertEqual(rendered.count, 3)
    }

    func testCapBoundaryHonorsMaxItemsConstant() {
        // Exactly maxItems passes through unchanged; the +1 case drops the tail.
        XCTAssertEqual(CoachingBriefCard.maxItems, 3)
        let atCap = (0..<CoachingBriefCard.maxItems).map { item("s\($0)") }
        XCTAssertEqual(CoachingBriefCard.payload(from: atCap), .brief(atCap))
    }

    // MARK: - Goal-aware color mapping (never good/bad)

    func testAlignedMapsToDeficitGreen() {
        XCTAssertEqual(CoachingBriefCard.accentColor(for: .aligned), Theme.deficit)
    }

    func testAgainstMapsToSurplusRed() {
        XCTAssertEqual(CoachingBriefCard.accentColor(for: .against), Theme.surplus)
    }

    func testNeutralMapsToInk() {
        XCTAssertEqual(CoachingBriefCard.accentColor(for: .neutral), Theme.ink)
    }

    func testGoalAwareColorsAreNotTheRetiredAccentPink() {
        // V7: the goal-aware palette must never fall back to the retired Theme.accent pink.
        for alignment: BriefItem.GoalAlignment in [.aligned, .against, .neutral] {
            XCTAssertNotEqual(CoachingBriefCard.accentColor(for: alignment), Theme.accent)
        }
    }

    // MARK: - BriefItem identity (stable dismissal across regenerations)

    func testBriefItemIdIsItsSourceSignalId() {
        let i = item("protein_sleep_recovery", alignment: .against)
        XCTAssertEqual(i.id, "protein_sleep_recovery")
    }
}
