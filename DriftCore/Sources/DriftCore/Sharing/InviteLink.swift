import Foundation

/// Inviting someone by @handle.
///
/// **This used to mint `https://drift.app/add/<handle>` and that was a bug I
/// shipped (2026-07-30).** We don't own `drift.app`, so every invite anyone sent
/// landed on "Safari can't establish a secure connection" — the operator caught
/// it from a WhatsApp thread. The code even carried a comment calling the host
/// "not a live website, a stable container for the handle", which was
/// self-deception: the URL went into a SHARE SHEET, where the entire contract is
/// that the recipient taps it.
///
/// Worse, the fallback didn't work either: `drift://` is registered on Android
/// (AndroidManifest intent filter) but NOT on iOS, so the custom scheme was
/// dead on the platform most invites would come from.
///
/// So there is no link. An invite is the @handle plus a sentence telling the
/// recipient what to do with it — which works in every messaging app, on both
/// platforms, with no domain, no universal-link entitlement and no
/// apple-app-site-association file to host.
///
/// A real tappable link needs a domain we control serving a smart-banner page
/// (and iOS associated-domains). Worth doing when there's a website to put it
/// on; not worth faking before then.
///
/// Parsing stays deliberately tolerant — someone will paste "@cindyk", "cindyk",
/// or a `drift://add/cindyk` link from Android — and lives here in DriftCore so
/// both platforms accept exactly the same input, Tier-0 tested rather than
/// discovered in the field.
public enum InviteLink {

    public static let scheme = "drift"
    static let path = "add"

    /// The deep-link shape. Live on Android (intent filter); NOT registered on
    /// iOS, so don't put it in front of users on either platform until it is.
    /// Kept because Android's handler is wired and it's what a QR code would
    /// encode.
    public static func deepLink(for username: String) -> String {
        "\(scheme)://\(path)/\(normalize(username))"
    }

    /// What actually goes in the share sheet.
    ///
    /// The handle, and the two steps to act on it. No URL: a dead link is worse
    /// than no link, because it makes the app look broken to someone who hasn't
    /// installed it yet. Naming the tab is the difference between an invite
    /// someone completes and one they mean to get back to.
    public static func shareText(for username: String) -> String {
        let handle = normalize(username)
        return """
        Add me on Drift — @\(handle)

        Open Drift → Friends → search @\(handle), then tap Add friend.
        """
    }

    /// Pull a handle out of anything a user might hand us: a bare handle, an
    /// @handle, or a `drift://add/<handle>` link. Returns nil when it isn't an
    /// invite at all.
    public static func username(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tolerate "@cindyk" or "cindyk" — the intent is unambiguous and
        // refusing it would be pedantry. This is the PRIMARY path now that
        // invites are handles rather than links.
        //
        // But ONLY when the input is already a handle apart from casing and a
        // leading @. Normalising first would turn "just some text" into
        // "justsometext" and accept it, so any pasted sentence would look like
        // an invite — caught by rejectsNonInvites().
        if !trimmed.contains("://") {
            let stripped = (trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed)
                .lowercased()
            let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
            guard !stripped.isEmpty, stripped.allSatisfy({ allowed.contains($0) }) else {
                return nil
            }
            return isValid(stripped) ? stripped : nil
        }

        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)

        // drift://add/<name> — URLComponents puts "add" in host, not path.
        if components.host?.lowercased() == path, let name = segments.first {
            return valid(name)
        }
        // Tolerate drift:///add/<name> too, where it all lands in path.
        if segments.count >= 2, segments[0].lowercased() == path {
            return valid(segments[1])
        }
        return nil
    }

    /// True when `raw` is an invite for anybody.
    public static func isInvite(_ raw: String) -> Bool { username(from: raw) != nil }

    static func valid(_ candidate: String) -> String? {
        let handle = normalize(candidate)
        return isValid(handle) ? handle : nil
    }

    /// Lowercase, strip a leading @, drop anything the username charset
    /// forbids. Mirrors the `^[a-z0-9_]{3,20}$` CHECK on `profiles.username`,
    /// so an invite can never carry a handle the server would reject.
    public static func normalize(_ raw: String) -> String {
        let stripped = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        return String(stripped.lowercased().filter { allowed.contains($0) }.prefix(20))
    }

    static func isValid(_ handle: String) -> Bool {
        handle.count >= 3 && handle.count <= 20
    }
}
