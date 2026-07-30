import Foundation

/// "What's new since I last looked" — per-conversation and per-client read
/// marks.
///
/// This is Drift's honest substitute for a server that tracks read state. Real
/// read receipts would need the server to know when you opened a screen, which
/// is more surveillance than a training app needs; instead each device
/// remembers what IT has already shown and treats the rest as new.
///
/// Durable via `DriftPlatform.keyValueStore` (the SQLite seam), NOT
/// UserDefaults: no UserDefaults write survives Android process death (#1108).
///
/// Two purposes, deliberately in one place so the key scheme can't collide:
/// - **sessions** — a coach seeing a client's completed workouts
/// - **messages** — either party seeing a 1:1 conversation
public enum SeenMarks {

    // MARK: - Client workout sessions (coach side)

    static func sessionsKey(_ clientID: String) -> String { "coach_seen_at_\(clientID)" }

    /// When the coach last opened this client's page. Nil = never looked, in
    /// which case everything shared so far counts as new.
    public static func lastSeenSessions(client clientID: String) -> Date? {
        date(forKey: sessionsKey(clientID))
    }

    public static func markSessionsSeen(client clientID: String, at when: Date = Date()) {
        DriftPlatform.keyValueStore.set(when.timeIntervalSince1970,
                                       forKey: sessionsKey(clientID))
    }

    /// Completed sessions this coach hasn't seen yet, for one client.
    ///
    /// Counts COMPLETED sessions only: an abandoned session is not an
    /// achievement to announce, and a live one is still in progress (the hub
    /// already shows those with a live dot).
    public static func unseenSessionCount(for clientID: String,
                                          sessions: [LiveWorkoutDTO]) -> Int {
        let since = lastSeenSessions(client: clientID)
        return sessions.filter { session in
            guard session.clientId == clientID, session.status == .completed else { return false }
            guard let started = session.startedAt, let when = parse(started) else {
                // No parseable timestamp: treat as seen rather than badging
                // forever on a row that can never clear.
                return false
            }
            guard let since else { return true }
            return when > since
        }.count
    }

    // MARK: - Messages (either party)

    static func messagesKey(_ peerID: String) -> String { "msgs_seen_at_\(peerID)" }

    public static func lastSeenMessages(peer peerID: String) -> Date? {
        date(forKey: messagesKey(peerID))
    }

    public static func markMessagesSeen(peer peerID: String, at when: Date = Date()) {
        DriftPlatform.keyValueStore.set(when.timeIntervalSince1970,
                                       forKey: messagesKey(peerID))
    }

    /// Unread messages FROM `peerID`. Only inbound counts — your own replies
    /// are not news, and counting them would badge every conversation you
    /// participate in.
    public static func unreadCount(peer peerID: String, messages: [MessageDTO]) -> Int {
        let since = lastSeenMessages(peer: peerID)
        return messages.filter { message in
            guard message.senderId == peerID else { return false }
            guard let created = message.createdAt, let when = parse(created) else { return false }
            guard let since else { return true }
            return when > since
        }.count
    }

    // MARK: - Shared helpers

    static func date(forKey key: String) -> Date? {
        let raw = DriftPlatform.keyValueStore.double(forKey: key)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    /// Postgres returns timestamps with or without fractional seconds
    /// depending on the value, so try both rather than dropping the row.
    static func parse(_ raw: String) -> Date? {
        if let withFraction = DateFormatters.iso8601.date(from: raw) { return withFraction }
        let strict = ISO8601DateFormatter()
        strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return strict.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

/// The newest inbound message per person, with how many are unread — what the
/// Today card needs to read like an inbox rather than a counter.
///
/// Computed in DriftCore from one fetch so the card costs a single round trip
/// instead of one per connection.
public struct InboxEntry: Sendable, Equatable, Identifiable {
    public let peerID: String
    public let latestBody: String
    public let latestAt: Date?
    public let unread: Int

    public var id: String { peerID }

    public init(peerID: String, latestBody: String, latestAt: Date?, unread: Int) {
        self.peerID = peerID
        self.latestBody = latestBody
        self.latestAt = latestAt
        self.unread = unread
    }
}

public enum Inbox {
    /// Group recent messages into one entry per correspondent, newest first.
    /// `me` is excluded as a sender — an entry is about what someone SENT you.
    public static func entries(from messages: [MessageDTO], me: String) -> [InboxEntry] {
        var latest: [String: MessageDTO] = [:]
        for message in messages where message.senderId != me {
            let peer = message.senderId
            guard let existing = latest[peer] else { latest[peer] = message; continue }
            let a = message.createdAt.flatMap(SeenMarks.parse) ?? .distantPast
            let b = existing.createdAt.flatMap(SeenMarks.parse) ?? .distantPast
            if a > b { latest[peer] = message }
        }
        return latest.values
            .map { message in
                InboxEntry(peerID: message.senderId,
                           latestBody: message.body,
                           latestAt: message.createdAt.flatMap(SeenMarks.parse),
                           unread: SeenMarks.unreadCount(peer: message.senderId,
                                                         messages: messages))
            }
            .sorted { ($0.latestAt ?? .distantPast) > ($1.latestAt ?? .distantPast) }
    }

    /// `entries` plus whether they can be trusted as the WHOLE picture.
    public struct Rollup: Sendable, Equatable {
        public let entries: [InboxEntry]
        /// False when the message window came back full, so correspondents
        /// whose newest message fell outside it are invisible here.
        public let complete: Bool

        public init(entries: [InboxEntry], complete: Bool) {
            self.entries = entries
            self.complete = complete
        }

        public var totalUnread: Int { entries.reduce(0) { $0 + $1.unread } }
    }

    /// Group messages into per-correspondent entries AND report whether the
    /// window that produced them was exhaustive.
    ///
    /// Unread is a LOCAL notion (`SeenMarks` lives in the key-value store, not
    /// on the server), so per-peer counts can only be derived from messages the
    /// client actually pulled. That's fine at one coach and five friends. With
    /// thirty chatty correspondents, a fixed newest-N window stops covering
    /// everyone, and a peer with genuinely unread messages silently reports
    /// zero — the UI then says "up to date" to someone who is not.
    ///
    /// Rather than pretend, `complete` goes false the moment the window comes
    /// back full, and callers must not claim to be caught up while it is.
    /// Fixing this properly needs server-side read state, which is a real
    /// schema change and not something to fake client-side.
    public static func rollup(from messages: [MessageDTO], me: String,
                             windowLimit: Int) -> Rollup {
        Rollup(entries: entries(from: messages, me: me),
               complete: messages.count < windowLimit)
    }
}
