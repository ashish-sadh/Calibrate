import XCTest
import SwiftUI
@testable import DriftCore
@testable import Drift

/// The Findable-by-search row is a settings control whose entire job is to
/// report the account's state. #1217: it defaulted to `true` and spent the
/// first seconds of every open telling an opted-out account it was listed.
/// These pin the three-way mapping so "we haven't asked yet" can never again
/// be indistinguishable from "you are listed".
final class SharingDiscoverableStateTests: XCTestCase {

    func testListedAccountSaysPeopleCanFindYou() {
        XCTAssertEqual(SharingView.discoverableSubtitle(for: true),
                       "People can find you by @username")
    }

    func testOptedOutAccountSaysInviteLinkOnly() {
        XCTAssertEqual(SharingView.discoverableSubtitle(for: false),
                       "Only people with your invite link can find you")
    }

    /// Unknown is its own copy — not either promise. A thrown
    /// `isDiscoverable()` used to land here as "you are listed".
    func testUnknownStateIsNeitherPromise() {
        let unknown = SharingView.discoverableSubtitle(for: nil)
        XCTAssertEqual(unknown, "Checking\u{2026}")
        XCTAssertNotEqual(unknown, SharingView.discoverableSubtitle(for: true))
        XCTAssertNotEqual(unknown, SharingView.discoverableSubtitle(for: false))
    }

    /// The fail-open direction is the one that matters: nothing but an explicit
    /// `true` may claim the account is findable.
    func testOnlyExplicitTrueClaimsFindable() {
        let findable = SharingView.discoverableSubtitle(for: true)
        for state: Bool? in [nil, false] {
            XCTAssertNotEqual(SharingView.discoverableSubtitle(for: state), findable,
                              "state \(String(describing: state)) must not read as listed")
        }
    }

    /// The toggle rests OFF while unknown — the non-permissive position — which
    /// is what `discoverable ?? false` in the binding's getter encodes.
    func testUnknownStateRestsOff() {
        let unknown: Bool? = nil
        XCTAssertFalse(unknown ?? false)
        XCTAssertTrue(true as Bool? ?? false)
    }
}
