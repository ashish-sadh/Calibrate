import Foundation

/// The one place that decides WHEN social data moves.
///
/// Both platforms call the same two functions, so the sync policy cannot drift
/// between iOS and Android — the same reason `SocialAlertPoll` is shared.
///
/// **The honest constraint.** Steps and calories live in HealthKit / Health
/// Connect, on the device. No server can pull them, so nothing publishes while
/// the app isn't running. That isn't a limitation we can design away; what we
/// CAN do is make every moment the app runs count, and be truthful about the age
/// of what's on screen.
///
/// The triggers, in order of how much they matter:
///
/// 1. **App foreground** — the big one. Everyone opens the app; almost nobody
///    opens the Friends hub. Gated to once a day because collecting a week costs
///    up to 14 per-day health queries.
/// 2. **A workout was saved** — the moment a lift PR actually changes, and the
///    only data that moved is in the local DB, so it's cheap and immediate.
/// 3. **Background refresh** (iOS, opportunistic) — narrows the gap for someone
///    who hasn't opened the app today. Best-effort by nature: iOS decides
///    whether to run it, and Android has no equivalent wired yet.
///
/// What it is deliberately NOT triggered by: opening the Friends hub. That was
/// the original wiring and it was backwards — the hub is where you go to LOOK at
/// the board, so your own number was always one visit behind, and someone who
/// never opened it never appeared at all.
@MainActor
public enum SocialSync {

    /// Everything the app should do about social when it comes to the front.
    ///
    /// Deliberately one call rather than two so a platform can't wire half of it
    /// — the alert poll shipped on both platforms and the publish didn't, which
    /// is exactly the divergence this prevents.
    public static func onForeground() async {
        await SocialAlertPoll.run()
        await LeaderboardPublisher.publishIfDue()
    }

    /// A workout just landed. Publishes immediately, past the daily gate.
    ///
    /// Forced because a new heaviest set is the one change people expect to see
    /// on a board straight away, and because the lift half reads only the local
    /// workout store — no health queries, so the daily gate isn't protecting
    /// anything here.
    public static func afterWorkoutSaved() async {
        guard Preferences.shareStatsWithFriends else { return }
        await LeaderboardPublisher.publishIfDue(force: true)
    }

    /// Background refresh. Same daily gate; iOS calls this from its existing
    /// BGTask rather than registering another identifier.
    public static func onBackgroundRefresh() async {
        await LeaderboardPublisher.publishIfDue()
    }
}
