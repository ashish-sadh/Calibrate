import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for WHO may be interrupted by WHAT.
///
/// This is the load-bearing test file for #1162: the operator's rule is that a
/// friend's training must never buzz someone's phone, and only a connection
/// request may interrupt a friend at all. A regression here is not a cosmetic
/// bug — it's the app violating a promise about interruption.
struct SocialAlertPolicyTests {

    // MARK: - The matrix

    @Test func friendsAreOnlyInterruptedByConnectionRequests() {
        #expect(NotifiableEvent.connectionRequest.alertsPhone(relationship: .friend))
        #expect(!NotifiableEvent.message.alertsPhone(relationship: .friend),
                "a friend's message belongs on Today, not on the lock screen")
        #expect(!NotifiableEvent.clientWorkoutLogged.alertsPhone(relationship: .friend))
        #expect(!NotifiableEvent.clientWorkoutImported.alertsPhone(relationship: .friend))
    }

    @Test func coachingRelationshipsAlertBothWays() {
        // Your client messages you: that's work.
        #expect(NotifiableEvent.message.alertsPhone(relationship: .client))
        // Your coach messages you: that's the thing you're paying for.
        #expect(NotifiableEvent.message.alertsPhone(relationship: .coach))
    }

    /// A coach cares that a client trained. The reverse isn't a thing — a
    /// coach's own workouts are never pushed to their clients.
    @Test func onlyCoachesHearAboutWorkouts() {
        #expect(NotifiableEvent.clientWorkoutLogged.alertsPhone(relationship: .client))
        #expect(!NotifiableEvent.clientWorkoutLogged.alertsPhone(relationship: .coach))
    }

    /// Operator 2026-07-29: "only notify coach about manually logged one —
    /// other just shows up as activity." An Apple Health import still SHARES;
    /// it must never interrupt, or a coach is buzzed for every client walk.
    @Test func importedWorkoutsNeverInterruptAnyone() {
        for relationship in [Connection.Kind.client, .coach, .friend] {
            #expect(!NotifiableEvent.clientWorkoutImported.alertsPhone(relationship: relationship),
                    "imported workouts are context, not events (\(relationship))")
        }
        #expect(!NotifiableEvent.clientWorkoutImported.alertsPhone(relationship: nil))
    }

    /// A request arrives BEFORE any relationship exists, so nil must still
    /// alert or the only friend-facing notification would never fire.
    @Test func requestsAlertEvenWithNoRelationshipYet() {
        #expect(NotifiableEvent.connectionRequest.alertsPhone(relationship: nil))
        #expect(!NotifiableEvent.message.alertsPhone(relationship: nil),
                "a message from a stranger is not a thing we buzz about")
    }

    // MARK: - decide()

    private func profile(_ id: String) -> SharedProfile {
        SharedProfile(id: id, username: id, displayName: nil, avatarUrl: nil)
    }

    private func message(_ id: String, from sender: String, to me: String,
                         _ body: String, at when: Date) -> MessageDTO {
        MessageDTO(id: id, senderId: sender, recipientId: me, body: body,
                   createdAt: DateFormatters.iso8601.string(from: when))
    }

    private func request(_ id: String, from requester: String, to me: String,
                         role: FriendRole = .friend) -> FriendshipDTO {
        FriendshipDTO(id: id, requesterId: requester, addresseeId: me,
                      status: .pending, role: role)
    }

    /// The end-to-end shape of the rule: a friend and a client both message
    /// you, and only the client's message produces an alert.
    @Test func decideAlertsForClientMessagesButNotFriendMessages() {
        let now = Date()
        let alerts = SocialAlertPoll.decide(
            messages: [message("m1", from: "clienty", to: "me", "shoulder ok?", at: now),
                       message("m2", from: "friendy", to: "me", "gym at 6?", at: now)],
            clientSessions: [],
            requests: [],
            connections: [Connection(profile: profile("clienty"), kind: .client),
                          Connection(profile: profile("friendy"), kind: .friend)],
            usernames: ["clienty": "clienty", "friendy": "friendy"],
            me: "me",
            alreadyAlerted: [])

        #expect(alerts.count == 1)
        #expect(alerts.first?.event == .message)
        #expect(alerts.first?.title == "@clienty")
        #expect(alerts.first?.deepLink == "drift://chat/clienty")
    }

    /// Ten messages are one alert, not ten.
    @Test func manyUnreadFromOnePersonCollapseToOneAlert() {
        let now = Date()
        let messages = (0..<5).map { index in
            message("m\(index)", from: "clienty", to: "me", "msg \(index)",
                    at: now.addingTimeInterval(Double(index)))
        }
        let alerts = SocialAlertPoll.decide(
            messages: messages, clientSessions: [], requests: [],
            connections: [Connection(profile: profile("clienty"), kind: .client)],
            usernames: ["clienty": "clienty"], me: "me", alreadyAlerted: [])

        #expect(alerts.count == 1)
        #expect(alerts.first?.body == "5 new messages")
    }

    /// A single unread shows the actual text — the preview IS the value.
    @Test func aSingleUnreadShowsItsBody() {
        let alerts = SocialAlertPoll.decide(
            messages: [message("m1", from: "clienty", to: "me", "knee feels better", at: Date())],
            clientSessions: [], requests: [],
            connections: [Connection(profile: profile("clienty"), kind: .client)],
            usernames: ["clienty": "clienty"], me: "me", alreadyAlerted: [])
        #expect(alerts.first?.body == "knee feels better")
    }

    /// Requests alert whoever they're addressed to, and say which kind they are.
    @Test func decideAlertsRequestsAndNamesTheKind() {
        let alerts = SocialAlertPoll.decide(
            messages: [], clientSessions: [],
            requests: [request("r1", from: "newbie", to: "me", role: .trainer),
                       // Addressed to someone else: not mine to be told about.
                       request("r2", from: "other", to: "notme")],
            connections: [],
            usernames: ["newbie": "newbie"], me: "me", alreadyAlerted: [])

        #expect(alerts.count == 1)
        #expect(alerts.first?.event == .connectionRequest)
        #expect(alerts.first?.title == "New coaching request")
        #expect(alerts.first?.body == "@newbie wants you as their coach")
    }

    /// An unknown requester still gets an alert — "someone" beats silence,
    /// because the request blocks them until answered.
    @Test func anUnresolvedHandleStillAlerts() {
        let alerts = SocialAlertPoll.decide(
            messages: [], clientSessions: [],
            requests: [request("r1", from: "ghost", to: "me")],
            connections: [], usernames: [:], me: "me", alreadyAlerted: [])
        #expect(alerts.first?.body == "someone wants to connect")
    }

    /// The de-dup ledger: an id already alerted is never raised again, so a
    /// poll running every 15 minutes doesn't re-buzz the same message.
    @Test func alreadyAlertedIsNeverRaisedTwice() {
        let requests = [request("r1", from: "newbie", to: "me")]
        let first = SocialAlertPoll.decide(
            messages: [], clientSessions: [], requests: requests, connections: [],
            usernames: ["newbie": "newbie"], me: "me", alreadyAlerted: [])
        #expect(first.count == 1)

        let second = SocialAlertPoll.decide(
            messages: [], clientSessions: [], requests: requests, connections: [],
            usernames: ["newbie": "newbie"], me: "me",
            alreadyAlerted: Set(first.map(\.id)))
        #expect(second.isEmpty)
    }

    private func session(_ id: String, client: String, source: String?) -> LiveWorkoutDTO {
        LiveWorkoutDTO(id: id, clientId: client, trainerId: "me",
                       templateName: "Push Day", status: .completed,
                       startedAt: DateFormatters.iso8601.string(from: Date()),
                       endedAt: nil, source: source)
    }

    /// End-to-end: a client's LOGGED session alerts their coach; the same
    /// client's Apple Health import does not.
    @Test func decideAlertsLoggedWorkoutsButNotImportedOnes() {
        let connections = [Connection(profile: profile("clienty"), kind: .client)]
        let usernames = ["clienty": "clienty"]

        let logged = SocialAlertPoll.decide(
            messages: [], clientSessions: [session("s1", client: "clienty", source: "drift")],
            requests: [], connections: connections, usernames: usernames,
            me: "me", alreadyAlerted: [])
        #expect(logged.count == 1)
        #expect(logged.first?.event == .clientWorkoutLogged)
        #expect(logged.first?.title == "@clienty trained")

        let imported = SocialAlertPoll.decide(
            messages: [], clientSessions: [session("s2", client: "clienty", source: "health")],
            requests: [], connections: connections, usernames: usernames,
            me: "me", alreadyAlerted: [])
        #expect(imported.isEmpty, "an imported walk shares, but never interrupts")
    }

    /// Rows written before the `source` column existed were all manually
    /// logged Drift sessions — absent must NOT be read as imported, or a coach
    /// silently stops being told about real sessions.
    @Test func aMissingSourceIsTreatedAsManuallyLogged() {
        let alerts = SocialAlertPoll.decide(
            messages: [], clientSessions: [session("s1", client: "clienty", source: nil)],
            requests: [],
            connections: [Connection(profile: profile("clienty"), kind: .client)],
            usernames: ["clienty": "clienty"], me: "me", alreadyAlerted: [])
        #expect(alerts.count == 1)
        #expect(alerts.first?.event == .clientWorkoutLogged)
    }

    /// Nothing at all to report produces no alerts — the poll must be silent
    /// when the world is quiet.
    @Test func aQuietWorldProducesNothing() {
        let alerts = SocialAlertPoll.decide(
            messages: [], clientSessions: [], requests: [], connections: [],
            usernames: [:], me: "me", alreadyAlerted: [])
        #expect(alerts.isEmpty)
    }
}
