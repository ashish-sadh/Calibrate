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
/// No message button for STRANGERS. You cannot message someone who hasn't
/// accepted you; the request is the only channel a stranger gets. Once you're
/// connected (friend/coach) Message appears regardless of how the sheet was
/// reached — see `canMessage`. Before #8 this was gated on `pushed`, so opening
/// an existing friend from SEARCH (a modal sheet, no nav stack) silently dropped
/// Message; now the modal path supplies its own NavigationStack to push onto.
struct PublicProfileSheet: View {
    let profile: SharedProfile
    /// What they were doing on the board you found them on — the reason you're
    /// here, so it stays on screen.
    let context: String?
    /// nil when you don't know this person — the original stranger case, which
    /// gets request buttons. Set for someone you're already connected to: the
    /// same page then carries the relationship and the way to change it, which
    /// is what makes "a coach is just a profile" true rather than a slogan.
    var relationship: Connection.Kind?
    /// True when pushed onto a navigation stack rather than presented as a
    /// sheet: the stack supplies Back, so the in-content chrome would duplicate
    /// it, and Message can push chat instead of having nowhere to go.
    var pushed = false
    /// Called after a relationship change so the hub can refetch.
    var onChanged: (() -> Void)?

    @Environment(\.dismiss) var dismiss

    /// Not private — Fuse can't bridge private @State.
    @State var activity: [PublicActivityDTO] = []
    @State var mutuals = 0
    @State var loading = true
    @State var sending = false
    @State var sent: String?
    @State var errorText: String?
    /// Removal arms on the first tap and fires on the second — same two-tap
    /// confirm the hub's management strip uses, no dialog (Fuse focus traps).
    @State var confirmingRemove = false

    /// You can message anyone you're actually connected to — a friend or a
    /// coach — but not a stranger (no relationship) and not a client (that
    /// conversation lives in ClientDetailView). Independent of `pushed`: the
    /// only thing `pushed` decided before #8 was whether a push target existed,
    /// which the modal path now provides for itself below.
    var canMessage: Bool {
        relationship != nil && relationship != .client
    }

    var body: some View {
        // A pushed sheet already sits inside the hub's NavigationStack; a modal
        // sheet (search / leaderboard tap) has none, so Message had nowhere to
        // push. Give the modal path its own stack so the button works there too.
        if pushed {
            content
        } else {
            NavigationStack { content }
        }
    }

    var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !pushed { chrome }
                identity

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Theme.surplus)
                }

                if let sent {
                    Text(sent).font(.caption).foregroundStyle(Theme.deficit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                } else if relationship != nil {
                    connectedActions
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
            if let name = profile.displayName, !name.isEmpty {
                Text(name).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            // The tagline is the one line a person wrote about themselves — the
            // reason we ask for it at all. Skip it when it IS the context line
            // (search passes the tagline as context) so it doesn't print twice.
            if let tag = profile.tagline, !tag.isEmpty, tag != context {
                Text(tag).font(.caption).italic()
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let context {
                Text(context).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// What you can do with someone you're already connected to: message them,
    /// and change or end the relationship. The management actions live HERE —
    /// operator 2026-07-30: "coach may be hidden under coach profile (convert to
    /// friend, remove coach)". Mirrors the hub's strip so both places agree.
    @ViewBuilder var connectedActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: sym(relationshipIcon))
                    .font(.caption).foregroundStyle(Theme.chartTrend)
                Text(relationshipLabel).font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.chartTrend)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.chartTrend.opacity(0.12), in: Capsule())

            if canMessage {
                NavigationLink {
                    ChatView(peer: profile, relationship: (relationship ?? .friend).rawValue)
                } label: {
                    #if os(Android)
                    // skip-ui maps no chat glyph and the paperplane stand-in
                    // read as SEND on the Message button (#1233) — drawn
                    // bubble instead (CameraGlyph.swift).
                    Label { Text("Message") } icon: {
                        ChatBubbleShape().fill(.white).frame(width: 15, height: 15)
                    }
                    .frame(maxWidth: .infinity)
                    #else
                    Label("Message", systemImage: sym("bubble.left.fill"))
                        .frame(maxWidth: .infinity)
                    #endif
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }

            if relationship == .coach {
                Button { Task { await manage { try await SharingService.shared.demoteCoach(profile.id) } } } label: {
                    Label("Back to friend", systemImage: sym("person.fill"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.chartTrend).disabled(sending)
            }
            if relationship == .friend {
                Button { Task { await manage { try await SharingService.shared.requestCoachPromotion(profile.id) } } } label: {
                    Label("Ask to coach me", systemImage: sym("figure.strengthtraining.traditional"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.chartTrend).disabled(sending)
            }

            Button {
                if confirmingRemove {
                    Task { await manage { try await SharingService.shared.removeConnection(with: profile.id) } }
                } else {
                    confirmingRemove = true
                }
            } label: {
                Text(confirmingRemove ? "Tap again to confirm" : removeLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Theme.surplus).disabled(sending)
        }
    }

    var relationshipLabel: String {
        switch relationship {
        case .coach: return "Your coach"
        case .client: return "Your client"
        case .friend: return "Friends"
        case nil: return ""
        }
    }

    var relationshipIcon: String {
        switch relationship {
        case .coach: return "figure.strengthtraining.traditional"
        case .client: return "person.crop.circle.badge.checkmark"
        default: return "person.2.fill"
        }
    }

    var removeLabel: String {
        switch relationship {
        case .coach: return "Remove coach"
        case .client: return "Remove client"
        default: return "Unfriend"
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
                        // Drawn glyph — skip-ui maps dumbbell to list.bullet,
                        // so every activity row read as a BULLET LIST (#1248,
                        // directive 0a). 11×11 is the caption2 glyph box.
                        #if os(Android)
                        DumbbellShape().fill(Theme.textTertiary)
                            .frame(width: 11, height: 11)
                        #else
                        Image(systemName: sym("dumbbell.fill"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        #endif
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

    /// Run a relationship change, report it in place, and let the hub refetch.
    /// Leaves the page open on success — the header re-renders from the caller's
    /// refreshed state, and dismissing under the user hides whether it worked.
    func manage(_ action: @escaping () async throws -> Void) async {
        sending = true
        errorText = nil
        confirmingRemove = false
        defer { sending = false }
        do {
            try await action()
            onChanged?()
            dismiss()
        } catch let e as SharingError {
            errorText = SharingView.message(for: e)
        } catch {
            errorText = "Couldn't do that. Try again."
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
