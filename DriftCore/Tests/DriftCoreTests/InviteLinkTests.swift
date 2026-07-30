import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for invite parsing (#1162 discovery).
///
/// Handles arrive pasted, forwarded and re-cased, and an invite that silently
/// fails to resolve is indistinguishable from "that person doesn't use Drift" —
/// so the tolerant cases matter as much as the strict ones.
///
/// The `https://drift.app/...` shape is GONE (2026-07-30): we never owned the
/// domain, so every invite sent hit a Safari TLS error. `mintsNoWebURL` below
/// is the guard that keeps it from coming back.
struct InviteLinkTests {

    // MARK: - Generating

    @Test func generatesTheDeepLinkShape() {
        #expect(InviteLink.deepLink(for: "cindyk") == "drift://add/cindyk")
    }

    @Test func generatingNormalisesTheHandle() {
        #expect(InviteLink.deepLink(for: "Cindy K!") == "drift://add/cindyk")
    }

    /// The share text says who, and what to DO — a bare handle in a chat thread
    /// leaves the recipient with nowhere to go.
    @Test func shareTextNamesThePersonAndTheSteps() {
        let text = InviteLink.shareText(for: "@CindyK")
        #expect(text.contains("@cindyk"), "normalised handle")
        #expect(text.contains("Drift"))
        #expect(text.localizedCaseInsensitiveContains("friends"), "names where to go")
    }

    /// THE REGRESSION GUARD. Shipping a URL on a domain we don't own put
    /// "Safari can't establish a secure connection" in front of every invited
    /// user. Nothing we hand a share sheet may contain a web URL until there is
    /// a host actually serving it.
    @Test func mintsNoWebURL() {
        let text = InviteLink.shareText(for: "cindyk")
        #expect(!text.contains("http"), "no web URL: \(text)")
        #expect(!text.localizedCaseInsensitiveContains("drift.app"))
    }

    // MARK: - Parsing both shapes

    @Test func parsesTheDeepLinkShape() {
        #expect(InviteLink.username(from: "drift://add/cindyk") == "cindyk")
        // Triple-slash form, where everything lands in path rather than host.
        #expect(InviteLink.username(from: "drift:///add/cindyk") == "cindyk")
    }

    /// The dead web shape is no longer an invite. Deleted rather than kept as a
    /// tolerated legacy input: the feature existed for a few hours and never
    /// worked, so there is nothing in the wild to stay compatible with.
    @Test func theRemovedWebShapeIsNotAnInvite() {
        #expect(InviteLink.username(from: "https://drift.app/add/cindyk") == nil)
        #expect(InviteLink.username(from: "https://www.drift.app/add/cindyk") == nil)
    }

    /// Messaging apps re-case and pad what they forward. All of these still
    /// mean "add cindyk".
    @Test func parsingSurvivesWhatMessengersDoToLinks() {
        #expect(InviteLink.username(from: "DRIFT://ADD/CindyK") == "cindyk")
        #expect(InviteLink.username(from: "drift://add/cindyk/") == "cindyk")
        #expect(InviteLink.username(from: "drift://add/cindyk?utm=whatsapp") == "cindyk")
        #expect(InviteLink.username(from: "  drift://add/cindyk  ") == "cindyk")
        #expect(InviteLink.username(from: " @CindyK ") == "cindyk")
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
        #expect(InviteLink.isInvite("@cindyk"))
        #expect(InviteLink.isInvite("drift://add/cindyk"))
        #expect(!InviteLink.isInvite("drift://add/xx"))
    }
}
