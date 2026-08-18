import SwiftUI
import DriftCore

/// Your clients, and nothing else.
///
/// The Today pills all used to land on the full Friends hub — search, requests,
/// coaches, clients, friends, leaderboard — so tapping "3 clients" meant
/// arriving somewhere and then hunting. The coach pill already opened a page
/// about that coach, and the operator wants the rest to match: "I wish it was a
/// bit easier to just focus on clients and leaderboard, at least like the coach
/// pill."
///
/// So this is a roster, ordered by who needs you. The hub is still one tap away
/// for everything else.
struct ClientsView: View {
    /// Not private — Fuse can't bridge private @State.
    @State var clients: [Connection] = []
    @State var sessions: [LiveWorkoutDTO] = []
    @State var loading = true
    /// The roster fetch failed. Distinct from "no clients" — telling a coach
    /// nobody has hired them because one read failed is the same lie the hub
    /// used to tell about friends (#1251).
    @State var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if failed {
                    CouldNotLoadCard(
                        message: "Couldn't load your clients just now — they're safe, this device just couldn't reach the server.",
                        retry: { await load() })
                } else if clients.isEmpty {
                    Text("Nobody has made you their coach yet. When someone does, they'll appear here with what they've been training.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .card()
                } else {
                    ForEach(clients) { client in
                        NavigationLink { ClientDetailView(client: client.profile) } label: {
                            row(client)
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink { SharingView() } label: {
                    HStack(spacing: 6) {
                        Text("Friends, coaches & requests")
                            .font(.caption).foregroundStyle(Theme.accent)
                        Spacer()
                        Image(systemName: sym("chevron.right"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle()).padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Your clients")
        .task { await load() }
    }

    func row(_ client: Connection) -> some View {
        let unseen = SeenMarks.unseenSessionCount(for: client.profile.id, sessions: sessions)
        return HStack(spacing: 10) {
            Text(String(client.profile.username.prefix(1)).uppercased())
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("@\(client.profile.username)")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                // What they've done since you last looked — the only thing a
                // coach opens this screen to find out.
                Text(unseen > 0 ? "\(unseen) new session\(unseen == 1 ? "" : "s")"
                                : "Up to date")
                    .font(.caption2)
                    .foregroundStyle(unseen > 0 ? Theme.accent : Theme.textTertiary)
            }
            Spacer()
            Image(systemName: sym("chevron.right"))
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
        .contentShape(Rectangle())
    }

    func load() async {
        let svc = SharingService.shared
        async let conns = svc.connections()
        async let live = try? svc.clientSessions()
        let all: [Connection]
        do { all = try await conns; failed = false } catch { all = []; failed = true }
        sessions = (await live) ?? []
        // Whoever needs you first.
        clients = all.filter { $0.kind == .client }.sorted {
            SeenMarks.unseenSessionCount(for: $0.profile.id, sessions: sessions)
                > SeenMarks.unseenSessionCount(for: $1.profile.id, sessions: sessions)
        }
        loading = false
    }
}

/// Leaderboards, on their own screen.
///
/// Same reasoning as `ClientsView`: the pill said "Leaderboard" and landed you
/// in a hub where the board was the last card. Here it's the only thing.
struct LeaderboardView: View {
    @State var connections: [Connection] = []
    @State var loading = true
    /// See `ClientsView.failed` — an unreachable server must not read as
    /// "you have no friends to compare with" (#1251).
    @State var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if failed {
                    CouldNotLoadCard(
                        message: "Couldn't load your boards just now — this device couldn't reach the server.",
                        retry: { await loadBoards() })
                } else if connections.filter({ $0.kind == .friend }).isEmpty {
                    Text("Leaderboards compare you with friends. Add one and your boards fill in — steps, calories, workouts and your food-logging streak are ready to go.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .card()
                    NavigationLink { SharingView() } label: {
                        Label("Find friends", systemImage: sym("person.badge.plus"))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                } else {
                    LeaderboardsCard(connections: connections)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Leaderboards")
        .task { await loadBoards() }
    }

    func loadBoards() async {
        do {
            connections = try await SharingService.shared.connections()
            failed = false
        } catch {
            failed = true
        }
        loading = false
    }
}

/// The one "we couldn't reach the server" card these focused screens share.
/// Deliberately not the empty state: an empty roster and an unreachable server
/// are different facts and must never render as the same sentence (#1251).
struct CouldNotLoadCard: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await retry() } } label: {
                Text("Try again")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
