import SwiftUI
import DriftCore

/// Friends/coaches surfaced on the dashboard. The feature previously lived only
/// under More → Friends, where nobody found it (operator 2026-07-28: "it's
/// hidden right now"). Single-source so iOS's Dashboard and Android's Today tab
/// show the same thing.
///
/// Two states, deliberately:
/// - **Signed out** — a one-line invitation. This is the discovery path, so it
///   has to be visible; it is NOT a nag (no badge, no count, muted styling) and
///   it never touches the network.
/// - **Signed in** — pending requests and new-from-friends activity, which is
///   the reason to come back. Counts come from the same polling the hub uses.
///
/// Deliberately shows nothing while loading: a card that pops in with a wrong
/// zero and then corrects itself reads as a bug.
/// Presentation only — it carries NO tap handling of its own so the host can
/// wrap it in whatever navigation it uses (a NavigationLink on iOS, a Button on
/// Android). Embedding a Button here would nest tap targets inside the host's.
struct FriendsDashboardCard: View {
    @State var signedIn = SharingService.shared.isSignedIn
    @State var pendingRequests = 0
    @State var friendActivity = 0
    @State var loaded = false

    var body: some View {
        Group {
            if signedIn {
                connectedCard
            } else {
                inviteCard
            }
        }
        .task { await load() }
    }

    // MARK: - Signed in

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
            Text("Friends").font(.subheadline.weight(.semibold))
            Spacer()
            if pendingRequests > 0 {
                badge("\(pendingRequests) new", tint: Theme.accent)
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
                Text("Friends & coaches").font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Share workouts, get a coach — just pick a username")
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
        // Best-effort: the dashboard must render instantly whether or not the
        // backend answers, so failures leave the counts at zero.
        async let requests = try? SharingService.shared.incomingRequests()
        async let sessions = try? SharingService.shared.clientSessions()
        pendingRequests = (await requests)?.count ?? 0
        friendActivity = (await sessions)?.count ?? 0
    }
}
