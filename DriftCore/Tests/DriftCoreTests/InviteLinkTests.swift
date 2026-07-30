import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for invite-link parsing (#1162 discovery).
///
/// Links arrive pasted, forwarded, re-cased and mangled by messaging apps, and
/// a link that silently fails to resolve is indistinguishable from "that person
/// doesn't use Drift" — so the tolerant cases matter as much as the strict ones.
struct InviteLinkTests {

    // MARK: - Generating

    @Test func generatesTheHttpsShapeForSharing() {
        // https, because a custom scheme often isn't tappable in messaging apps.
        #expect(InviteLink.url(for: "cindyk") == "https://drift.app/add/cindyk")
        #expect(InviteLink.deepLink(for: "cindyk") == "drift://add/cindyk")
    }

    @Test func generatingNormalisesTheHandle() {
        #expect(InviteLink.url(for: "@CindyK") == "https://drift.app/add/cindyk")
        #expect(InviteLink.deepLink(for: "Cindy K!") == "drift://add/cindyk")
    }

    /// A bare URL in a chat thread reads like spam — the share text says who
    /// and what.
    @Test func shareTextNamesThePersonAndTheApp() {
        let text = InviteLink.shareText(for: "cindyk")
        #expect(text.contains("@cindyk"))
        #expect(text.contains("Drift"))
        #expect(text.contains("https://drift.app/add/cindyk"))
    }

    // MARK: - Parsing both shapes

    @Test func parsesTheDeepLinkShape() {
        #expect(InviteLink.username(from: "drift://add/cindyk") == "cindyk")
        // Triple-slash form, where everything lands in path rather than host.
        #expect(InviteLink.username(from: "drift:///add/cindyk") == "cindyk")
    }

    @Test func parsesTheHttpsShapeIncludingWww() {
        #expect(InviteLink.username(from: "https://drift.app/add/cindyk") == "cindyk")
        #expect(InviteLink.username(from: "https://www.drift.app/add/cindyk") == "cindyk")
        #expect(InviteLink.username(from: "http://drift.app/add/cindyk") == "cindyk")
    }

    /// Messaging apps re-case, add trailing slashes and append tracking params.
    /// All of those still mean "add cindyk".
    @Test func parsingSurvivesWhatMessengersDoToLinks() {
        #expect(InviteLink.username(from: "HTTPS://DRIFT.APP/ADD/CindyK") == "cindyk")
        #expect(InviteLink.username(from: "https://drift.app/add/cindyk/") == "cindyk")
        #expect(InviteLink.username(from: "https://drift.app/add/cindyk?utm=whatsapp") == "cindyk")
        #expect(InviteLink.username(from: "  drift://add/cindyk  ") == "cindyk")
    }

    /// Someone pasting a bare handle means the same thing; refusing it would be
    /// pedantry.
    @Test func acceptsABareHandleToo() {
        #expect(InviteLink.username(from: "cindyk") == "cindyk")
        #expect(InviteLink.username(from: "@cindyk") == "cindyk")
    }

    // MARK: - Rejecting

    @Test func rejectsNonInvites() {
        #expect(InviteLink.username(from: "") == nil)
        #expect(InviteLink.username(from: "https://example.com/add/cindyk") == nil,
                "another host is not our invite")
        #expect(InviteLink.username(from: "https://drift.app/privacy") == nil,
                "our host, but not an invite path")
        #expect(InviteLink.username(from: "drift://chat/cindyk") == nil,
                "our scheme, but a different action")
        #expect(!InviteLink.isInvite("just some text"))
    }

    /// The handle must satisfy the same rule as `profiles.username`
    /// (`^[a-z0-9_]{3,20}$`), so a link can never carry something the server
    /// would reject.
    @Test func rejectsHandlesTheServerWouldRefuse() {
        #expect(InviteLink.username(from: "drift://add/ab") == nil, "under 3 chars")
        #expect(InviteLink.username(from: "drift://add/!!") == nil, "nothing legal left")
        // Over-length is truncated to the 20-char maximum rather than rejected,
        // matching how the signup field behaves.
        let long = String(repeating: "a", count: 30)
        #expect(InviteLink.username(from: "drift://add/\(long)")?.count == 20)
    }

    @Test func isInviteAgreesWithUsername() {
        #expect(InviteLink.isInvite("https://drift.app/add/cindyk"))
        #expect(InviteLink.isInvite("drift://add/cindyk"))
        #expect(!InviteLink.isInvite("drift://add/xx"))
    }
}
