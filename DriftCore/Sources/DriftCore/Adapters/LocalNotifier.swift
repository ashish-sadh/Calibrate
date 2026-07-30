import Foundation

/// A minimal local-notification seam.
///
/// Drift raises alerts the way a rest timer does — locally, on the device, with
/// no server involved. There is deliberately no push infrastructure (no APNs
/// key, no FCM project, no device tokens): a privacy-first app has no
/// always-on server watching a user's activity. When an alert is about
/// something that happened on SOMEONE ELSE's phone (a coach's client finished
/// a workout, a message arrived), the app finds out by polling when it next
/// runs and then raises a LOCAL notification.
///
/// Why a seam rather than direct calls: `UNUserNotificationCenter` is
/// Apple-only, and `Drift/Services/NotificationService.swift` lives in the iOS
/// app target. Android needs `NotificationManager` plus a channel and the
/// API-33 `POST_NOTIFICATIONS` runtime permission. Both sit behind this
/// protocol so the POLICY — who gets told what — stays in shared DriftCore code
/// and cannot drift between platforms.
public protocol LocalNotifier: Sendable {
    /// Ask for permission if it hasn't been asked yet. Returns whether alerts
    /// are allowed afterwards.
    ///
    /// On Android this triggers the API-33 runtime prompt, which relaunches the
    /// activity (#1096) — call it from a deliberate moment, never lazily during
    /// a render.
    func requestAuthorization() async -> Bool

    /// Whether alerts are currently allowed, without prompting.
    func isAuthorized() async -> Bool

    /// Raise an alert NOW. `id` de-duplicates: raising the same id twice
    /// replaces rather than stacks, so a poll that runs twice over the same
    /// unread message doesn't notify twice.
    func notify(id: String, title: String, body: String, deepLink: String?) async
}

/// The events Drift can raise, and who is allowed to be interrupted by each.
///
/// The policy lives here — in shared code, as data — because it is the part
/// that must not diverge: a bug that pushes a friend about someone's workout is
/// exactly what the design rules out (operator 2026-07-29, #1162).
public enum NotifiableEvent: String, Sendable, CaseIterable {
    /// A 1:1 message arrived.
    case message
    /// A client finished a workout they LOGGED IN DRIFT — sets, reps, the
    /// session a coach programmed. This is the one a coach wants to hear about.
    case clientWorkoutLogged
    /// A client's workout that arrived from Apple Health / Health Connect
    /// (a walk, a run the watch recorded). It belongs in the history and the
    /// activity feed, but it is CONTEXT, not an event — operator 2026-07-29:
    /// "only notify coach about manually logged one… other just shows up as
    /// activity." Auto-imported workouts would otherwise buzz a coach every
    /// time their client went for a walk.
    case clientWorkoutImported
    /// Someone asked to connect — the one alert that needs an answer.
    case connectionRequest

    /// Whether this event may raise a PHONE alert given the relationship to the
    /// other party.
    ///
    /// The rule, in the operator's words: "coach getting notification is fine
    /// but friends shouldn't. They should only get notification when someone
    /// added them." A friend's training is not an interruption; a client's is a
    /// coach's job.
    ///
    /// INTERPRETATION, flagged because "phone app notification only Coach
    /// should get" reads two ways: the COACHING RELATIONSHIP earns the alert in
    /// BOTH directions, not just the coach's side. A client who gets no alert
    /// when their coach replies has a coaching chat that feels broken, and the
    /// client is the person paying for the relationship. Friendships never
    /// alert. If the operator meant strictly the coach's device, this becomes
    /// `relationship == .client` in one line.
    public func alertsPhone(relationship: Connection.Kind?) -> Bool {
        switch self {
        case .connectionRequest:
            // Always: it blocks someone else until answered, and at request
            // time there is no relationship yet.
            return true
        case .message:
            // Inside a coaching relationship, either way round. A friend
            // messaging you shows up on Today instead.
            return relationship == .client || relationship == .coach
        case .clientWorkoutLogged:
            // Only a coach cares that a client trained; the reverse isn't a
            // thing (a coach's own workouts aren't pushed to clients).
            return relationship == .client
        case .clientWorkoutImported:
            // Never. It still SHARES (history + activity) — it just doesn't
            // interrupt anyone.
            return false
        }
    }
}
