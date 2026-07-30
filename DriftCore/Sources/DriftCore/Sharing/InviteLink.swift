import Foundation

/// The invite link — how people actually connect.
///
/// Search already matched username AND display_name, so finding someone was
/// never the bottleneck: you had to already KNOW their handle. Real users send
/// a link ("add me on Drift"), and a coach signing up a client standing in
/// front of them needs something shorter than dictating a username.
///
/// Two shapes, one meaning:
/// - `drift://add/cindyk` — the custom scheme, opens the app directly.
/// - `https://drift.app/add/cindyk` — survives pasting anywhere (iMessage,
///   WhatsApp, email) and is what a QR code encodes. Only recognised as an
///   invite; nothing is fetched from that host, so no web service is implied.
///
/// Parsing lives here, in DriftCore, so both platforms accept exactly the same
/// links and the rules are Tier-0 testable rather than discovered in the field.
public enum InviteLink {

    public static let scheme = "drift"
    /// Not a live website — a stable, human-readable container for the handle.
    public static let webHost = "drift.app"
    static let path = "add"

    /// Canonical form for sharing. Uses the https shape because it stays
    /// tappable in every messaging app, where a custom scheme often doesn't.
    public static func url(for username: String) -> String {
        "https://\(webHost)/\(path)/\(normalize(username))"
    }

    /// The deep-link shape, for QR codes and in-app handoff.
    public static func deepLink(for username: String) -> String {
        "\(scheme)://\(path)/\(normalize(username))"
    }

    /// Copy for a share sheet. Says who and what, because a bare URL in a chat
    /// thread reads like spam.
    public static func shareText(for username: String) -> String {
        "Add me on Drift — @\(normalize(username))\n\(url(for: username))"
    }

    /// Pull the handle out of anything a user might hand us: either link shape,
    /// with or without a leading `@`, any casing, trailing slash or query.
    /// Returns nil when it isn't an invite at all.
    public static func username(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tolerate someone pasting just "@cindyk" or "cindyk" — the intent is
        // unambiguous and refusing it would be pedantry.
        //
        // But ONLY when the input is ALREADY a handle apart from casing and a
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

        guard let components = URLComponents(string: trimmed) else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)

        if components.scheme?.lowercased() == scheme {
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

        if let host = components.host?.lowercased(),
           host == webHost || host == "www.\(webHost)",
           segments.count >= 2, segments[0].lowercased() == path {
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
    /// so a link can never carry a handle the server would reject.
    public static func normalize(_ raw: String) -> String {
        let stripped = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        return String(stripped.lowercased().filter { allowed.contains($0) }.prefix(20))
    }

    static func isValid(_ handle: String) -> Bool {
        handle.count >= 3 && handle.count <= 20
    }
}
