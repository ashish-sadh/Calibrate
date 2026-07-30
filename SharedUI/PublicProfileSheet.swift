import SwiftUI
import DriftCore

/// Someone you found on a global board, before you know them.
///
/// The operator's flow (2026-07-30): "you see a bunch of new users on
/// leaderboard, you click, you see their recent activity and mutual friends and
/// click send request for friend or coach."
///
/// What it shows and what it withholds is the whole design:
///   * **Recent activity** — workout names and dates only, from
///     `public_activity`, which is gated server-side on that person having opted
///     into a global board and windowed to 30 days. No sets, no weights, nothing
///     about their body. Enough to tell whether they train like you.
///   * **Mutual friends** as a COUNT, never a list. Naming them would turn a
///     leaderboard into a tool for enumerating a stranger's social graph.
///   * **One request**, friend or coach. Coaches are just profiles — the same
///     sheet, the same buttons — which is what makes "make a friend your coach"
///     feel like a relationship changing rather than a mode switch.
///
/// No message button. You cannot message someone who hasn't accepted you; the
/// request is the only channel a stranger gets.
struct PublicProfileSheet: View {
    let profile: SharedProfile
    /// What they were doing on the board you found them on — the reason you're
    /// here, so it stays on screen.
    let context: String?

    @Environment(\.dismiss) var dismiss

    /// Not private — Fuse can't bridge private @State.
    @State var activity: [PublicActivityDTO] = []
    @State var mutuals = 0
    @State var loading = true
    @State var sending = false
    @State var sent: String?
    @State var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                chrome
                identity

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Theme.surplus)
                }

                if let sent {
                    Text(sent).font(.caption).foregroundStyle(Theme.deficit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                } else {
                    requestButtons
                }

                if loading {
                    ProgressView().padding(.vertical, 20)
                } else {
                    if mutuals > 0 { mutualsRow }
                    activitySection
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await load() }
    }

    // In-content chrome: a nav bar inside a sheet reserves a dead band on
    // Android (#1089).
    var chrome: some View {
        HStack {
            Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
            Spacer()
            Text("Profile").font(.headline)
            Spacer()
            Text("Close").font(.body).foregroundStyle(.clear)
        }
        .padding(.top, 12)
    }

    var identity: some View {
        VStack(spacing: 6) {
            Text(String(profile.username.prefix(1)).uppercased())
                .font(.title.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.accentGradient, in: Circle())
            Text("@\(profile.username)")
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            if let context {
                Text(context).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    var mutualsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: sym("person.2.fill"))
                .font(.caption).foregroundStyle(Theme.chartTrend)
            // A count, not names — see the type comment.
            Text(mutuals == 1 ? "1 mutual friend" : "\(mutuals) mutual friends")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .card()
    }

    var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT ACTIVITY").sectionHeading()
            if activity.isEmpty {
                Text("Nothing public in the last 30 days.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(activity) { row in
                    HStack(spacing: 8) {
                        Image(systemName: sym("dumbbell.fill"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        Text(row.name).font(.caption).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(row.workoutDate).font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    var requestButtons: some View {
        VStack(spacing: 8) {
            Button {
                Task { await request(role: .friend) }
            } label: {
                Label("Send friend request", systemImage: sym("person.badge.plus"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .disabled(sending)

            // Same sheet, same weight: a coach is a profile like any other, and
            // asking someone to coach you is a request they accept, never a role
            // imposed on them.
            Button {
                Task { await request(role: .trainer) }
            } label: {
                Label("Ask to be my coach", systemImage: sym("figure.strengthtraining.traditional"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Theme.chartTrend)
            .disabled(sending)
        }
    }

    // MARK: - Actions

    func request(role: FriendRole) async {
        sending = true
        errorText = nil
        defer { sending = false }
        do {
            if role == .trainer {
                try await SharingService.shared.addCoach(profile.id)
                sent = "Asked @\(profile.username) to be your coach. You'll see them once they accept."
            } else {
                try await SharingService.shared.sendRequest(to: profile.id, role: .friend)
                sent = "Friend request sent to @\(profile.username)."
            }
        } catch let e as SharingError {
            // The duplicate case is worth naming: a request already exists, which
            // is not a failure the person needs to retry.
            if case .conflict = e {
                sent = "You've already asked @\(profile.username)."
            } else {
                errorText = SharingView.message(for: e)
            }
        } catch {
            errorText = "Couldn't send that request. Try again."
        }
    }

    func load() async {
        let svc = SharingService.shared
        async let acts = try? svc.publicActivity(of: profile.id)
        async let count = try? svc.mutualFriendCount(with: profile.id)
        activity = (await acts) ?? []
        mutuals = (await count) ?? 0
        loading = false
    }
}
