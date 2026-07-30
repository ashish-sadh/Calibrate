import Foundation

/// Finds out what happened on other people's phones and raises local alerts for
/// whatever the policy says may interrupt you.
///
/// This is the whole notification engine, and it lives in shared DriftCore on
/// purpose: the POLICY (who may be interrupted by what) is the part that must
/// not diverge between iOS and Android. Only the *scheduling* is platform code
/// — `BGTaskScheduler` on iOS, `WorkManager` on Android — and both call
/// `run()`.
///
/// Called on app foreground too, so the common case (you open the app) needs no
/// background execution at all.
public enum SocialAlertPoll {

    /// Alerts already raised, so a poll that runs twice doesn't notify twice.
    /// Keyed per event id; the notifier ALSO de-duplicates by id, this is belt
    /// and braces plus a cheap early-out.
    static let alertedKey = "social_alerted_ids"

    static func alreadyAlerted() -> Set<String> {
        Set(DriftPlatform.keyValueStore.stringArray(forKey: alertedKey) ?? [])
    }

    static func remember(_ ids: Set<String>) {
        // Cap it: this is a de-dup ledger, not history. Newest wins.
        let capped = Array(ids).suffix(200)
        DriftPlatform.keyValueStore.set(Array(capped), forKey: alertedKey)
    }

    /// One decision the caller can test without a network or a device.
    public struct PendingAlert: Sendable, Equatable, Identifiable {
        public let id: String
        public let event: NotifiableEvent
        public let title: String
        public let body: String
        /// Where tapping should land, as a deep link path.
        public let deepLink: String?

        public init(id: String, event: NotifiableEvent, title: String,
                    body: String, deepLink: String?) {
            self.id = id
            self.event = event
            self.title = title
            self.body = body
            self.deepLink = deepLink
        }
    }

    /// PURE: given what the server said, decide what deserves a phone alert.
    /// No notifier, no store, no clock — so the policy is Tier-0 testable, which
    /// matters because a bug here notifies friends about workouts, the exact
    /// thing the design rules out.
    ///
    /// `usernames` maps user id → @handle for readable copy; a missing entry
    /// falls back to "someone".
    public static func decide(messages: [MessageDTO],
                              clientSessions: [LiveWorkoutDTO],
                              requests: [FriendshipDTO],
                              connections: [Connection],
                              usernames: [String: String],
                              me: String,
                              alreadyAlerted: Set<String>) -> [PendingAlert] {
        var out: [PendingAlert] = []
        var kindByID: [String: Connection.Kind] = [:]
        for connection in connections { kindByID[connection.id] = connection.kind }

        func handle(_ id: String) -> String { usernames[id].map { "@\($0)" } ?? "someone" }

        // Connection requests — the one alert everybody gets, because it blocks
        // the other person until answered.
        for request in requests where request.status == .pending && request.addresseeId == me {
            let id = "req-\(request.id)"
            guard !alreadyAlerted.contains(id) else { continue }
            let asksToCoach = request.role == .trainer
            out.append(PendingAlert(
                id: id, event: .connectionRequest,
                title: asksToCoach ? "New coaching request" : "New friend request",
                body: asksToCoach
                    ? "\(handle(request.requesterId)) wants you as their coach"
                    : "\(handle(request.requesterId)) wants to connect",
                deepLink: "drift://friends"))
        }

        // Messages — unread inbound, grouped so ten messages are one alert
        // rather than ten. Only where the relationship permits it.
        for entry in Inbox.entries(from: messages, me: me) where entry.unread > 0 {
            let relationship = kindByID[entry.peerID]
            guard NotifiableEvent.message.alertsPhone(relationship: relationship) else { continue }
            // Keyed on the LATEST message so a new one re-alerts but a re-poll
            // of the same state does not.
            let id = "msg-\(entry.peerID)-\(entry.latestAt?.timeIntervalSince1970 ?? 0)"
            guard !alreadyAlerted.contains(id) else { continue }
            out.append(PendingAlert(
                id: id, event: .message,
                title: handle(entry.peerID),
                body: entry.unread > 1
                    ? "\(entry.unread) new messages"
                    : entry.latestBody,
                deepLink: "drift://chat/\(entry.peerID)"))
        }

        // Client workouts — a coach's job, but only the ones the client
        // actually LOGGED. An Apple Health import still shares (it lands in the
        // history and the activity feed); it just doesn't buzz anyone, or a
        // coach would be interrupted every time a client went for a walk.
        for session in clientSessions where session.status == .completed {
            let relationship = kindByID[session.clientId]
            let event: NotifiableEvent = session.isImported
                ? .clientWorkoutImported : .clientWorkoutLogged
            guard event.alertsPhone(relationship: relationship) else { continue }
            guard SeenMarks.unseenSessionCount(for: session.clientId,
                                               sessions: [session]) > 0 else { continue }
            let id = "work-\(session.id)"
            guard !alreadyAlerted.contains(id) else { continue }
            out.append(PendingAlert(
                id: id, event: event,
                title: "\(handle(session.clientId)) trained",
                body: session.templateName ?? "Completed a workout",
                deepLink: "drift://client/\(session.clientId)"))
        }

        return out
    }

    /// Fetch, decide, raise. Safe to call from anywhere; does nothing when the
    /// user isn't signed in, hasn't allowed alerts, or no notifier is installed.
    @MainActor
    public static func run() async {
        let svc = SharingService.shared
        guard svc.isSignedIn, let notifier = DriftPlatform.notifier else { return }
        guard await notifier.isAuthorized() else { return }
        guard let me = svc.currentSession?.userID else { return }

        async let inbox = try? svc.recentInbox()
        async let sessions = try? svc.clientSessions()
        async let requests = try? svc.incomingRequests()
        async let connections = try? svc.connections()

        let messages = (await inbox) ?? []
        let clientSessions = (await sessions) ?? []
        let pending = (await requests) ?? []
        let conns = (await connections) ?? []

        // Requester profiles aren't in `connections` yet (they're not connected
        // — that's the point), so resolve any missing handles in one call.
        var usernames: [String: String] = [:]
        for connection in conns { usernames[connection.id] = connection.profile.username }
        let unknown = pending.map(\.requesterId).filter { usernames[$0] == nil }
        if !unknown.isEmpty, let profiles = try? await svc.profiles(ids: unknown) {
            for profile in profiles { usernames[profile.id] = profile.username }
        }

        let alerted = alreadyAlerted()
        let decisions = decide(messages: messages, clientSessions: clientSessions,
                               requests: pending, connections: conns,
                               usernames: usernames, me: me, alreadyAlerted: alerted)
        guard !decisions.isEmpty else { return }

        for alert in decisions {
            await notifier.notify(id: alert.id, title: alert.title,
                                  body: alert.body, deepLink: alert.deepLink)
        }
        remember(alerted.union(decisions.map(\.id)))
    }
}
