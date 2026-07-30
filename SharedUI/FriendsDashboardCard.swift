import SwiftUI
import DriftCore

/// Friends/coaches/clients surfaced on the dashboard. The feature previously
/// lived only under More → Friends, where nobody found it (operator 2026-07-28
/// "it's hidden right now"), then sat at the bottom of Recovery. Single-source
/// so iOS's Dashboard and Android's Today tab show the same thing.
///
/// The card changes SHAPE by relationship (operator 2026-07-29: "should chat
/// with your human coach also be a surface under Today?"). Rather than adding a
/// fifth card to an already dense screen, the one card leads with whatever
/// actually needs the user:
///
/// - **You have a coach** — their name, the last thing they said, unread count;
///   tapping goes straight into that chat, because when there is one obvious
///   conversation the hub is a detour.
/// - **You are a coach** — how many clients are waiting on you.
/// - **Friends only** — recent activity count.
/// - **Nobody yet** — a quiet invitation. This is the discovery path so it must
///   be visible; it is NOT a nag (no badge, no count, muted styling) and when
///   signed out it never touches the network.
///
/// A message PREVIEW, not just a count: "2 new" is a counter people learn to
/// ignore, a line of text is an inbox they answer.
///
/// Deliberately shows nothing while loading: a card that pops in with a wrong
/// zero and then corrects itself reads as a bug.
///
/// Owns its own navigation — the destination depends on data only this card
/// has, so hosts render it bare rather than wrapping it. (Wrapping it would
/// also nest tap targets, which is dead on Fuse.)
struct FriendsDashboardCard: View {
    @State var signedIn = SharingService.shared.isSignedIn
    @State var pendingRequests = 0
    @State var friendActivity = 0
    @State var hasCoach = false
    @State var hasClients = false
    @State var hasConnections = false
    @State var loaded = false
    /// The coach to lead with, and their newest message, when there is one.
    @State var leadCoach: SharedProfile?
    @State var leadEntry: InboxEntry?
    /// Clients with unseen completed workouts or unread messages.
    @State var clientsWaiting = 0

    var body: some View {
        Group {
            if signedIn && hasConnections {
                if let coach = leadCoach {
                    // Straight into the conversation — see the type comment.
                    NavigationLink { ChatView(peer: coach, relationship: "coach") } label: {
                        coachCard(coach)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink { SharingView() } label: { connectedCard }
                        .buttonStyle(.plain)
                }
            } else {
                NavigationLink { SharingView() } label: { inviteCard }
                    .buttonStyle(.plain)
            }
        }
        .task { await load() }
    }

    // MARK: - Coach-led

    func coachCard(_ coach: SharedProfile) -> some View {
        HStack(spacing: 10) {
            Text(String(coach.username.prefix(1)).uppercased())
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accentGradient, in: Circle())
                .overlay { Circle().strokeBorder(Theme.chartTrend, lineWidth: 2) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("@\(coach.username)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("COACH")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.chartTrend.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.chartTrend)
                }
                // The preview is what makes this an inbox rather than a badge.
                Text(leadEntry?.latestBody ?? "Tap to message your coach")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let unread = leadEntry?.unread, unread > 0 {
                badge("\(unread) new", tint: Theme.accent)
            }
            Image(systemName: sym("chevron.right"))
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    // MARK: - Signed in, no coach

    /// Role-aware title (operator 2026-07-29: "rename — like connect with
    /// trainer, or if you're a coach, connect with client").
    var connectedTitle: String {
        if hasClients { return "Your clients" }
        return "Friends"
    }

    var connectedCard: some View {
        HStack(spacing: 10) {
            #if os(Android)
            // skip-ui has no two-person glyph; sym() maps it (Symbols.swift).
            Image(systemName: sym("person.2.fill"))
                .foregroundStyle(Theme.accent)
            #else
            Image(systemName: "person.2.fill")
                .foregroundStyle(Theme.accent)
            #endif
            Text(connectedTitle).font(.subheadline.weight(.semibold))
            Spacer()
            if pendingRequests > 0 {
                badge("\(pendingRequests) new", tint: Theme.accent)
            } else if clientsWaiting > 0 {
                // A coach's own queue: clients who did something they haven't
                // looked at yet.
                badge("\(clientsWaiting) waiting", tint: Theme.accent)
            } else if friendActivity > 0 {
                Text("\(friendActivity) recent")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Up to date")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Image(systemName: sym("chevron.right"))
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    /// A count that has to be noticed — a request sitting unanswered is the one
    /// thing here that blocks someone else.
    func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint, in: Capsule())
    }

    // MARK: - Signed out

    var inviteCard: some View {
        HStack(spacing: 10) {
            #if os(Android)
            Image(systemName: sym("person.2.fill"))
                .foregroundStyle(Theme.textSecondary)
            #else
            Image(systemName: "person.2.fill")
                .foregroundStyle(Theme.textSecondary)
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect with a coach").font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Or train with friends — share workouts, chat. Just pick a @username")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: sym("chevron.right"))
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    // MARK: - Load

    func load() async {
        guard !loaded else { return }
        loaded = true
        signedIn = SharingService.shared.isSignedIn
        guard signedIn else { return }
        let svc = SharingService.shared
        // Best-effort: the dashboard must render instantly whether or not the
        // backend answers, so failures leave the counts at zero (and the card
        // in its invitation form).
        async let requests = try? svc.incomingRequests()
        async let sessions = try? svc.clientSessions()
        async let conns = try? svc.connections()
        async let inbox = try? svc.recentInbox()

        pendingRequests = (await requests)?.count ?? 0
        let clientSessions = (await sessions) ?? []
        friendActivity = clientSessions.count
        let connections = (await conns) ?? []
        let messages = (await inbox) ?? []

        hasConnections = !connections.isEmpty
        hasCoach = connections.contains { $0.kind == .coach }
        hasClients = connections.contains { $0.kind == .client }

        let entries = Inbox.entries(from: messages, me: svc.currentSession?.userID ?? "")

        // Lead with the coach who most recently said something; failing that,
        // any coach at all — having a coach is the headline either way.
        let coaches = connections.filter { $0.kind == .coach }
        if let spoke = entries.first(where: { entry in coaches.contains { $0.id == entry.peerID } }) {
            leadCoach = coaches.first { $0.id == spoke.peerID }?.profile
            leadEntry = spoke
        } else {
            leadCoach = coaches.first?.profile
            leadEntry = nil
        }

        // A coach's queue: clients with unseen workouts or unread messages.
        clientsWaiting = connections.filter { connection in
            guard connection.kind == .client else { return false }
            let unseenWork = SeenMarks.unseenSessionCount(for: connection.id,
                                                          sessions: clientSessions)
            let unread = entries.first { $0.peerID == connection.id }?.unread ?? 0
            return unseenWork > 0 || unread > 0
        }.count
    }
}
