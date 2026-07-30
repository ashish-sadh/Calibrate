import SwiftUI
import DriftCore

/// Coach / clients / friends on Today, as thin pills.
///
/// Replaces `FriendsDashboardCard`'s full-width card, which led with "Tap to
/// message your coach". Two problems with that (operator 2026-07-30): it gave a
/// single chat the visual weight of the calorie rings, and messaging is the
/// smallest thing a coaching relationship contains — "It can also be something
/// like *your coach* page, where you see more than a message, like what they
/// assigned to you".
///
/// So each pill is a DOORWAY to a page, not a shortcut to a chat:
///
/// - **Your coach** → `CoachPageView` — what they assigned, what they wrote,
///   and messaging as one action among several.
/// - **Your clients** → the roster, to see how they're doing.
/// - **Friends** → the hub.
///
/// Someone who is both a client and a coach gets both pills; the row scrolls
/// horizontally rather than shrinking them, because two truncated pills are
/// worse than one and a half visible ones.
///
/// Pills EARN their place. A pill with news carries a dot; when everything is
/// quiet the row collapses to a single muted pill rather than a strip of
/// "0 new" (operator: "maybe disappearing pills"). Nothing renders at all until
/// the load finishes — a row that pops in with a wrong zero reads as a bug —
/// and when signed out it never touches the network.
struct SocialPillRow: View {
    @State var signedIn = SharingService.shared.isSignedIn
    @State var loaded = false
    /// Guards against two loads overlapping. NOT a "load once" latch — that was
    /// the bug (see `load`).
    @State var loading = false

    @State var coach: SharedProfile?
    @State var coachUnread = 0
    /// Assignments from a coach that haven't been accepted yet — the thing the
    /// operator wanted visible above "you have a message".
    @State var coachAssignments = 0
    @State var clientCount = 0
    @State var clientsWaiting = 0
    @State var friendCount = 0
    @State var friendActivity = 0
    @State var pendingRequests = 0
    /// False when the inbox window couldn't cover every correspondent, so
    /// "you're up to date" is not a claim we're entitled to make.
    @State var inboxComplete = true

    var body: some View {
        Group {
            if !loaded {
                // NOT EmptyView(). `.task` never fires on a view that resolves
                // to EmptyView — it has no layout node — so `!loaded → EmptyView`
                // was a self-sustaining deadlock: nothing ran, so `loaded` never
                // flipped, so the whole social surface was permanently absent
                // from Today. Found by driving the iOS simulator, invisible in
                // every build and test (2026-07-30). A zero-height Color is a
                // real node, so the modifier attaches and the load runs.
                Color.clear.frame(height: 0)
            } else if !SharingService.shared.isConfigured {
                // No backend in this build: an invitation that dead-ends is
                // worse than no invitation.
                Color.clear.frame(height: 0)
            } else if !signedIn || (coach == nil && clientCount == 0 && friendCount == 0) {
                invitePill
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { pills }
                        .padding(.horizontal, 1)
                }
                // Android: a horizontal scroller inside a vertical one needs a
                // pinned MINIMUM height or it collapses when the IME closes.
                .frame(minHeight: 44)
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var pills: some View {
        // Requests first and always: a request sitting unanswered is the only
        // thing here that blocks another person.
        if pendingRequests > 0 {
            pill(title: pendingRequests == 1 ? "1 request" : "\(pendingRequests) requests",
                 icon: "person.badge.plus", tint: Theme.accent, dot: true) {
                SharingView()
            }
        }

        if let coach {
            pill(title: "Your coach", icon: "figure.strengthtraining.traditional",
                 tint: Theme.chartTrend,
                 detail: coachDetail,
                 dot: coachUnread > 0 || coachAssignments > 0) {
                CoachPageView(coach: coach)
            }
        }

        if clientCount > 0 {
            pill(title: clientCount == 1 ? "Your client" : "\(clientCount) clients",
                 icon: "person.2.fill", tint: Theme.accent,
                 detail: clientsWaiting > 0 ? "\(clientsWaiting) waiting" : nil,
                 dot: clientsWaiting > 0) {
                SharingView()
            }
        }

        if friendCount > 0 {
            pill(title: "Friends", icon: "person.2.fill", tint: Theme.textSecondary,
                 detail: friendActivity > 0 ? "\(friendActivity) active" : nil,
                 dot: false) {
                SharingView()
            }
        }
    }

    /// What the coach pill says under the title. Assignments outrank messages —
    /// a program you haven't started is more actionable than an unread line.
    private var coachDetail: String? {
        if coachAssignments > 0 {
            return coachAssignments == 1 ? "1 new plan" : "\(coachAssignments) new plans"
        }
        if coachUnread > 0 { return "\(coachUnread) unread" }
        // Only claim to be caught up when the window actually covered everyone.
        return inboxComplete ? nil : "Tap to catch up"
    }

    // MARK: - Pill

    private func pill<Destination: View>(title: String, icon: String, tint: Color,
                                        detail: String? = nil, dot: Bool,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 6) {
                Image(systemName: sym(icon))
                    .font(.caption2).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                if dot {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.cardBackground, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.separatorFaint, lineWidth: 1) }
            // Without an explicit shape the capsule's corners aren't tappable,
            // and a dead entry point hides everything behind it.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Nobody connected yet. The discovery path, so it stays visible — but
    /// muted, and never a badge or a count. It is an offer, not a nag.
    private var invitePill: some View {
        NavigationLink { SharingView() } label: {
            HStack(spacing: 6) {
                Image(systemName: sym("person.2.fill"))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                Text("Connect with a coach or friend")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: sym("chevron.right"))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.cardBackground, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.separatorFaint, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load

    func load() async {
        // `!loading`, NOT `!loaded`. This used to early-return forever after the
        // first run, so the counts froze for the whole app session: a coach
        // opened a client, `SeenMarks` cleared the mark, came back to Today —
        // and the "1 waiting" dot was still there until the app was relaunched.
        // Operator repro, 2026-07-30: "it's not clearing up recent dots".
        // `.task` re-fires whenever Today reappears, which is exactly when these
        // numbers should be re-read.
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // `defer`, not a line at the bottom: `loaded` used to be set only after
        // all five fetches returned, so a hung request or a stale session left
        // this row as EmptyView FOREVER — the whole social surface silently
        // absent from Today, which is how it was found (iOS sim, 2026-07-30).
        // Whatever happens below, the row must decide what to draw.
        defer { loaded = true }
        signedIn = SharingService.shared.isSignedIn
        guard signedIn else { return }
        let svc = SharingService.shared

        // Best-effort and concurrent: Today must render whether or not the
        // backend answers, so failures leave the counts at zero and the row in
        // its invitation form.
        async let requests = try? svc.incomingRequests()
        async let conns = try? svc.connections()
        async let inbox = try? svc.recentInbox()
        async let sessions = try? svc.clientSessions()
        async let assignments = try? svc.incomingSharedTemplates()

        pendingRequests = (await requests)?.count ?? 0
        let connections = (await conns) ?? []
        let messages = (await inbox) ?? []
        let clientSessions = (await sessions) ?? []
        let incoming = (await assignments) ?? []

        let rollup = Inbox.rollup(from: messages, me: svc.currentSession?.userID ?? "",
                                 windowLimit: SharingService.inboxWindow)
        inboxComplete = rollup.complete

        let coaches = connections.filter { $0.kind == .coach }
        let clients = connections.filter { $0.kind == .client }
        let friends = connections.filter { $0.kind == .friend }

        // Lead with whichever coach most recently said something — with two
        // coaches, the one mid-conversation is the one you meant.
        if let spoke = rollup.entries.first(where: { entry in coaches.contains { $0.id == entry.peerID } }) {
            coach = coaches.first { $0.id == spoke.peerID }?.profile
            coachUnread = spoke.unread
        } else {
            coach = coaches.first?.profile
            coachUnread = 0
        }
        let coachIDs = Set(coaches.map(\.id))
        coachAssignments = incoming.filter { coachIDs.contains($0.ownerId) }.count

        clientCount = clients.count
        clientsWaiting = clients.filter { connection in
            let unseen = SeenMarks.unseenSessionCount(for: connection.id, sessions: clientSessions)
            let unread = rollup.entries.first { $0.peerID == connection.id }?.unread ?? 0
            return unseen > 0 || unread > 0
        }.count

        friendCount = friends.count
        friendActivity = friends.filter { connection in
            SeenMarks.unseenSessionCount(for: connection.id, sessions: clientSessions) > 0
        }.count
    }
}
