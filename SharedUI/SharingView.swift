import SwiftUI
import DriftCore

/// Friends & Trainer sharing — single-source hub for iOS + Android.
///
/// Opt-in and off by default: nothing here touches the network until the user
/// claims a @username (which silently creates an anonymous account — no email,
/// no password). The transport lives in DriftCore (`SharingService`), so this
/// file is pure presentation and works on both platforms (buffered HTTPS).
struct SharingView: View {

    enum Stage: Equatable {
        case loading, needsUsername, ready
    }

    @State var stage: Stage = .loading
    @State var busy = false
    @State var error: String?

    // Auth — username only (anonymous account under the hood)
    @State var username = ""

    // Hub data
    @State var searchText = ""
    @State var searchResults: [SharedProfile] = []
    @State var searchGen = 0
    @State var searching = false
    @State var searchedOnce = false
    @State var requestedIDs: Set<String> = []
    /// The other party of every pending edge, either direction — so search can
    /// say "Requested" for someone asked days ago, not just this session.
    @State var pendingIDs: Set<String> = []
    @State var requests: [FriendshipDTO] = []
    /// Requester profiles by user ID, so a request row can say WHO is asking —
    /// an identity-blind "Friend request" made accepting strangers the default.
    @State var requestSenders: [String: SharedProfile] = [:]
    @State var conns: [Connection] = []
    /// The last connections fetch failed. Distinct from `conns.isEmpty`, which
    /// is a legitimate state for a new account — telling someone with friends
    /// that they have none is the worse error by far.
    @State var connectionsFailed = false
    @State var incomingTemplates: [SharedTemplateDTO] = []
    @State var clientSessions: [LiveWorkoutDTO] = []
    // Per-row connection management (operator 2026-07-29: no way to unfriend,
    // remove a coach, or make an existing friend a coach). `managingID` flips
    // a row's inline action strip open; destructive actions arm on first tap
    // (`confirmingRemoveID`) and fire on the second — a two-tap confirm, not a
    // dialog, because Fuse dialogs carry keyboard/focus traps (#1077).
    @State var managingID: String? = nil
    @State var confirmingRemoveID: String? = nil

    private var svc: SharingService { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch stage {
                case .loading:
                    ProgressView().padding(.top, 60)
                case .needsUsername:
                    usernameCard
                case .ready:
                    hub
                }

                if let error {
                    Text(error)
                        .font(.caption).foregroundStyle(Theme.surplus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                privacyFootnote
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Friends")
        .task { await bootstrap() }
    }

    // MARK: - Onboarding (username only)

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PICK A USERNAME").sectionHeading()
            Text("Choose a @username so friends can find you. No email, no password — just pick a name and you're in. Lowercase letters, numbers and underscores, 3–20 characters.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 4) {
                Text("@").font(.headline).foregroundStyle(Theme.textSecondary)
                TextField("username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    #if !os(Android)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
            primaryButton("Claim @\(normalizedUsername.isEmpty ? "username" : normalizedUsername)", busy: busy) {
                await run {
                    try await svc.startSharing(username: normalizedUsername)
                    await afterSignIn()
                }
            }
            .disabled(normalizedUsername.count < 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var normalizedUsername: String {
        String(username.lowercased().unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").contains($0)
        }).prefix(20).description
    }

    // MARK: - Hub (signed in)

    private var hub: some View {
        VStack(spacing: 16) {
            identityCard
            peopleStrip
            searchCard
            if !requests.isEmpty { requestsCard }
            if !incomingTemplates.isEmpty { incomingTemplatesCard }
            if !clientSessions.isEmpty { workoutsFromFriendsCard }
            if !coaches.isEmpty {
                connectionSection("YOUR COACHES", coaches, subtitle: "coaches you")
                ForEach(coaches) { coach in
                    CoachSharingCard(coach: coach.profile)
                }
            }
            if !clients.isEmpty { connectionSection("YOUR CLIENTS", clients, subtitle: "you coach") }
            if connectionsFailed {
                couldNotLoadCard
            } else {
                connectionSection("FRIENDS", friendConns, subtitle: nil,
                                  emptyText: "No friends yet. Search a @username above to add a friend or a coach.")
            }
        }
    }

    /// A tappable list of connections — each row opens the chat (coach/client
    /// rows also carry the relationship subtitle).
    private func connectionSection(_ title: String, _ list: [Connection],
                                   subtitle: String?, emptyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeading()
            if list.isEmpty, let emptyText {
                Text(emptyText).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(list) { c in
                // The manage button lives BESIDE the NavigationLink, never
                // inside its label — nested tap targets are dead on Fuse.
                HStack(spacing: 6) {
                    NavigationLink {
                        // A client opens the coach's client detail (their workouts +
                        // assign + message); coaches/friends open chat directly.
                        if c.kind == .client {
                            ClientDetailView(client: c.profile)
                        } else {
                            ChatView(peer: c.profile, relationship: c.kind.rawValue)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            avatar(c.profile.username)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(c.profile.username)").font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(subtitle ?? (c.profile.displayName ?? "tap to chat"))
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            // The coach's unread mark — Drift's honest stand-in
                            // for a push notification (see SeenMarks).
                            if c.kind == .client {
                                let unseen = SeenMarks.unseenSessionCount(
                                    for: c.profile.id, sessions: clientSessions)
                                if unseen > 0 {
                                    Text("\(unseen) new")
                                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Theme.accent, in: Capsule())
                                }
                            }
                            Image(systemName: sym("bubble.left.fill"))
                                .font(.caption).foregroundStyle(Theme.chartTrend)
                            Image(systemName: sym("chevron.right"))
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle()).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        managingID = managingID == c.id ? nil : c.id
                        confirmingRemoveID = nil
                    } label: {
                        Image(systemName: sym("ellipsis"))
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6).padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if managingID == c.id { managementStrip(c) }
                if c.id != list.last?.id { Divider().overlay(Theme.separatorFaint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Inline actions for one connection. Promotion is a REQUEST (operator
    /// decision 2026-07-29): coaching is accepted, never imposed — the friend
    /// gets "wants you as their coach" in their requests card and the
    /// friendship stays intact while they decide. Removal arms on the first
    /// tap and fires on the second.
    private func managementStrip(_ c: Connection) -> some View {
        HStack(spacing: 8) {
            if c.kind == .friend {
                stripButton("Ask to coach me", tint: Theme.chartTrend) {
                    await runManage { try await svc.requestCoachPromotion(c.profile.id) }
                }
            }
            if c.kind == .coach {
                stripButton("Back to friend", tint: Theme.chartTrend) {
                    await runManage { try await svc.demoteCoach(c.profile.id) }
                }
            }
            let removeLabel = c.kind == .client ? "Remove client" : (c.kind == .coach ? "Remove coach" : "Unfriend")
            stripButton(confirmingRemoveID == c.id ? "Tap again to confirm" : removeLabel,
                        tint: Theme.surplus) {
                if confirmingRemoveID == c.id {
                    await runManage { try await svc.removeConnection(with: c.profile.id) }
                } else {
                    confirmingRemoveID = c.id
                }
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func stripButton(_ title: String, tint: Color,
                             action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func runManage(_ action: @escaping () async throws -> Void) async {
        await run { try await action() }
        managingID = nil
        confirmingRemoveID = nil
        await refreshHub()
    }

    private var workoutsFromFriendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FRIEND ACTIVITY").sectionHeading()
            ForEach(clientSessions) { session in
                NavigationLink {
                    ClientSessionDetailView(session: session,
                                            fromUsername: usernameFor(session.clientId))
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            avatar(rawUsername(session.clientId))
                            if session.status == .live {
                                Circle().fill(Theme.surplus).frame(width: 11, height: 11)
                                    .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            // "@bob finished Leg Day" — a friend-activity line.
                            // One interpolated Text (not Text+Text — Skip Fuse
                            // has no Text concatenation operator).
                            Text(activityLine(session))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(activityTimeline(session)).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: sym("chevron.right")).font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle()).padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                if session.id != clientSessions.last?.id { Divider().overlay(Theme.separatorFaint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// What to show instead of add buttons for someone you're already with.
    private func existingRelationshipLabel(_ kind: Connection.Kind) -> String {
        switch kind {
        case .coach: return "Your coach"
        case .client: return "Your client"
        case .friend: return "Friends"
        }
    }

    private func rawUsername(_ id: String) -> String {
        conns.first { $0.id == id }?.profile.username ?? "?"
    }

    private func usernameFor(_ id: String) -> String? {
        conns.first { $0.id == id }.map { "@\($0.profile.username)" }
    }

    private func activityLine(_ s: LiveWorkoutDTO) -> String {
        let who = usernameFor(s.clientId) ?? "A friend"
        let verb = s.status == .live ? "is doing" : "finished"
        return "\(who) \(verb) \(s.templateName ?? "a workout")"
    }

    private func activityTimeline(_ s: LiveWorkoutDTO) -> String {
        if s.status == .live { return "training now · live 🔴" }
        guard let d = s.activityDate else { return "completed" }
        return RelativeTime.string(from: d)
    }

    /// Identity header (#1156 slice 1) — the hub anchors on WHO YOU ARE, the
    /// way Threads' profile row does, instead of a "Signed in" caption. The
    /// second line is the thing most worth noticing: pending requests first,
    /// else your connection count.
    private var identityCard: some View {
        HStack(spacing: 12) {
            Text(String((svc.currentUsername ?? "?").prefix(1)).uppercased())
                .font(.title2.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(svc.currentUsername ?? "")")
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                if !requests.isEmpty {
                    Text("\(requests.count) request\(requests.count == 1 ? "" : "s") waiting")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                } else {
                    Text(conns.isEmpty
                         ? "Find friends & coaches below"
                         : "\(conns.count) connection\(conns.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button("Sign out") {
                Task { @MainActor in
                    await svc.signOut()
                    reset()
                    stage = .needsUsername
                }
            }
            .font(.caption).foregroundStyle(Theme.surplus)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Threads-style quick-access row (#1156 slice 1): everyone you're
    /// connected to as tappable avatar circles, coaches first with an accent
    /// ring. One tap into chat (or the client page) without scanning the
    /// grouped sections — which stay below for management + coach sharing.
    @ViewBuilder
    private var peopleStrip: some View {
        if conns.count >= 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(stripOrder) { c in
                        NavigationLink {
                            if c.kind == .client {
                                ClientDetailView(client: c.profile)
                            } else {
                                ChatView(peer: c.profile, relationship: c.kind.rawValue)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(String(c.profile.username.prefix(1)).uppercased())
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Theme.accentGradient, in: Circle())
                                    .overlay {
                                        if c.kind == .coach {
                                            Circle().strokeBorder(Theme.chartTrend, lineWidth: 2)
                                        }
                                    }
                                Text("@\(c.profile.username)")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            #if os(Android)
            // hScroll IME-collapse guard — a MINIMUM, so content still grows
            // with font scale (the fixed-height variant clipped, b75cbb34).
            .frame(minHeight: 84)
            #endif
        }
    }

    /// Coaches first — they're who you open this tab for — then friends,
    /// then clients; alphabetical inside each band so the order is stable.
    private var stripOrder: [Connection] {
        func band(_ kind: Connection.Kind) -> Int {
            kind == .coach ? 0 : (kind == .friend ? 1 : 2)
        }
        return conns.sorted { a, b in
            band(a.kind) != band(b.kind)
                ? band(a.kind) < band(b.kind)
                : a.profile.username.lowercased() < b.profile.username.lowercased()
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD FRIENDS").sectionHeading()
            HStack(spacing: 8) {
                Image(systemName: sym("magnifyingglass")).foregroundStyle(Theme.textSecondary)
                TextField("Search @username", text: $searchText)
                    #if !os(Android)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }
                    // Live search as you type (debounced) — don't make the user
                    // hunt for a return key.
                    .onChange(of: searchText) { _, _ in
                        searchGen &+= 1
                        let gen = searchGen
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if gen == searchGen { await search() }
                        }
                    }
                if searching { ProgressView().scaleEffect(0.8) }
                if !searchText.isEmpty {
                    Button { searchText = ""; searchResults = []; searchedOnce = false } label: {
                        Image(systemName: sym("xmark")).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(10)
            .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            if searchedOnce, searchResults.isEmpty, !searching,
               searchText.trimmingCharacters(in: .whitespaces).count >= 1 {
                Text("No one found for “\(searchText)”. Make sure your friend has opened Friends and picked the same @username on their phone.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 2)
            }

            ForEach(searchResults) { profile in
                HStack(spacing: 10) {
                    avatar(profile.username)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("@\(profile.username)").font(.subheadline.weight(.medium))
                        if let name = profile.displayName, !name.isEmpty {
                            Text(name).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    // Already connected? Say so. Offering "Add friend" to your
                    // own coach reads as broken and, tapped, 409s on the
                    // duplicate edge (operator screenshot 2026-07-29: @cindyk
                    // is the coach AND shows Add friend/Coach).
                    if let existing = conns.first(where: { $0.id == profile.id }) {
                        Text(existingRelationshipLabel(existing.kind))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.chartTrend.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.chartTrend)
                    } else if pendingIDs.contains(profile.id) || requestedIDs.contains(profile.id) {
                        Label("Requested", systemImage: sym("checkmark"))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.deficit)
                    } else {
                        Button { Task { await sendRequest(to: profile, role: .friend) } } label: {
                            Text("Add friend").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
                        }.buttonStyle(.plain)
                        Button { Task { await sendRequest(to: profile, role: .trainer) } } label: {
                            Text("Coach").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.chartTrend, in: Capsule()).foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var requestsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FRIEND REQUESTS").sectionHeading()
            ForEach(requests) { req in
                let sender = requestSenders[req.requesterId]
                HStack(spacing: 10) {
                    avatar(sender?.username ?? "?")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("@\(sender?.username ?? "someone")")
                            .font(.subheadline.weight(.medium))
                        Text(req.role == .trainer ? "wants you as their coach" : "sent a friend request")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { Task { await respond(req, accept: true) } } label: {
                        Image(systemName: sym("checkmark")).foregroundStyle(.white)
                            .padding(8).background(Theme.deficit, in: Circle())
                    }.buttonStyle(.plain)
                    Button { Task { await respond(req, accept: false) } } label: {
                        Image(systemName: sym("xmark")).foregroundStyle(Theme.textSecondary)
                            .padding(8).background(Theme.pillBackground, in: Circle())
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var incomingTemplatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHARED WITH YOU").sectionHeading()
            ForEach(incomingTemplates) { dto in
                VStack(alignment: .leading, spacing: 6) {
                    Text(dto.name).font(.subheadline.weight(.semibold))
                    Text("\(dto.exercises.count) exercises\(dto.note.map { " · \($0)" } ?? "")")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        Button { Task { await acceptTemplate(dto) } } label: {
                            Text("Add to my workouts").font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
                        }.buttonStyle(.plain)
                        Button { Task { await declineTemplate(dto) } } label: {
                            Text("Decline").font(.caption).foregroundStyle(Theme.textSecondary)
                        }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                if dto.id != incomingTemplates.last?.id { Divider().overlay(Theme.separator) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var privacyFootnote: some View {
        HStack(spacing: 6) {
            Image(systemName: sym("lock.fill")).font(.caption2).foregroundStyle(Theme.deficit)
            Text("Only your @username, display name, and the workouts you explicitly share leave this device. Everything else stays local.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4).padding(.top, 4)
    }

    // MARK: - Building blocks

    private func avatar(_ seed: String) -> some View {
        let letter = seed.first.map { String($0).uppercased() } ?? "?"
        return Text(letter)
            .font(.headline).foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Theme.accentGradient, in: Circle())
    }

    private func primaryButton(_ title: String, busy: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                Spacer()
                if busy { ProgressView().tint(.white) } else { Text(title).font(.subheadline.weight(.semibold)) }
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func bootstrap() async {
        // A stored session might be stale (account deleted / token dead after a
        // reset) — validate it first so we recover to the picker instead of a
        // credential-refresh error. Skips the network when signed out.
        if svc.isSignedIn {
            let ok = await svc.validateSession()
            if !ok { reset(); stage = .needsUsername; return }
        }
        if svc.isSignedIn, svc.currentUsername != nil {
            await afterSignIn()
        } else {
            stage = .needsUsername
        }
    }

    private func afterSignIn() async {
        guard svc.currentUsername != nil else { stage = .needsUsername; return }
        stage = .ready
        await refreshHub()
        // If a call during refresh invalidated the session (orphaned account),
        // drop back to the picker rather than showing a broken hub.
        if !svc.isSignedIn { reset(); stage = .needsUsername }
    }

    private func refreshHub() async {
        async let reqs = try? await svc.incomingRequests()
        async let tmpls = try? await svc.incomingSharedTemplates()
        // Connections are NOT `try?`. Every other call here degrades gracefully
        // when it fails — a missing request badge is invisible. This one does
        // not: collapsing a failed fetch to [] renders "No friends yet", which
        // tells someone with 8 friends that they have none. A failed load and
        // an empty list must never look the same.
        async let connections = svc.connections()
        async let sessions = try? await svc.clientSessions()
        async let pending = try? await svc.pendingEdges()
        requests = await reqs ?? []
        incomingTemplates = await tmpls ?? []
        clientSessions = await sessions ?? []
        let me = svc.currentSession?.userID
        pendingIDs = Set((await pending ?? []).map {
            $0.requesterId == me ? $0.addresseeId : $0.requesterId
        })

        do {
            conns = try await connections
            connectionsFailed = false
        } catch {
            // Keep whatever we already had on screen rather than blanking it.
            connectionsFailed = true
        }

        // Opening your own Friends hub refreshes what your coaches see. The
        // briefing is a local-first snapshot, so without this it only moved
        // when a toggle was flipped — meaning a coach could be reading
        // week-old numbers while the client's app had fresh ones all along.
        // Fire-and-forget: a failed push must never block the hub rendering.
        Task { await BriefingRepush.afterNotesChanged() }
        if requests.isEmpty {
            requestSenders = [:]
        } else {
            let profs = (try? await svc.profiles(ids: requests.map(\.requesterId))) ?? []
            requestSenders = Dictionary(profs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Shown instead of the empty state when the fetch itself failed. Your
    /// friends are on the server; we just couldn't reach them.
    private var couldNotLoadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FRIENDS").sectionHeading()
            Text("Couldn't load your friends just now — they're safe, this device just couldn't reach the server.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Button { Task { await refreshHub() } } label: {
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

    private var coaches: [Connection] { conns.filter { $0.kind == .coach } }
    private var clients: [Connection] { conns.filter { $0.kind == .client } }
    private var friendConns: [Connection] { conns.filter { $0.kind == .friend } }

    private func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; searchedOnce = false; return }
        searching = true
        await run(showBusy: false) {
            searchResults = try await svc.searchUsers(q)
        }
        searching = false
        searchedOnce = true
    }

    private func sendRequest(to profile: SharedProfile, role: FriendRole) async {
        await run(showBusy: false) {
            if role == .trainer { try await svc.addCoach(profile.id) }
            else { try await svc.sendRequest(to: profile.id, role: .friend) }
            requestedIDs.insert(profile.id)
        }
    }

    private func respond(_ req: FriendshipDTO, accept: Bool) async {
        await run(showBusy: false) {
            try await svc.respondToRequest(req.id, accept: accept)
            requests.removeAll { $0.id == req.id }
            if accept { await refreshHub() }
        }
    }

    private func acceptTemplate(_ dto: SharedTemplateDTO) async {
        await run(showBusy: false) {
            _ = try await svc.acceptSharedTemplate(dto)
            incomingTemplates.removeAll { $0.id == dto.id }
        }
    }

    private func declineTemplate(_ dto: SharedTemplateDTO) async {
        await run(showBusy: false) {
            try await svc.declineSharedTemplate(dto)
            incomingTemplates.removeAll { $0.id == dto.id }
        }
    }

    private func reset() {
        username = ""; searchText = ""
        searchResults = []; requests = []; requestSenders = [:]; conns = []
        incomingTemplates = []
        clientSessions = []; requestedIDs = []; searchedOnce = false
    }

    /// Run an async action with unified busy/error handling.
    private func run(showBusy: Bool = true, _ action: @escaping () async throws -> Void) async {
        if showBusy { busy = true }
        error = nil
        do { try await action() }
        catch let e as SharingError { error = Self.message(for: e) }
        catch let e { error = e.localizedDescription }
        busy = false
    }

    private static func message(for e: SharingError) -> String {
        switch e {
        case .notConfigured: return "Sharing isn't available in this build."
        case .notSignedIn: return "Please sign in again."
        case .network(let m): return "Network error: \(m)"
        case .http(_, let m): return m
        case .conflict(let m): return m.lowercased().contains("username") || m.lowercased().contains("duplicate")
            ? "That username is taken — try another." : m
        case .forbidden: return "Your session expired — sign in again."
        case .decoding(let m): return "Unexpected response: \(m)"
        }
    }
}

/// A friend's workout as it appears in your app — live (refreshes) or completed.
/// Groups the flat set rows back under their exercises.
struct ClientSessionDetailView: View {
    let session: LiveWorkoutDTO
    let fromUsername: String?

    @State var sets: [LiveWorkoutSetDTO] = []
    @State var loading = true

    private var svc: SharingService { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.templateName ?? "Workout").font(.title3.weight(.bold))
                    Text("\(fromUsername ?? "A friend") · \(session.status == .live ? "training now 🔴" : "completed")")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if sets.isEmpty {
                    Text("No sets logged yet.").font(.caption).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24).card()
                } else {
                    ForEach(groupedExercises, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name).font(.subheadline.weight(.semibold))
                            ForEach(group.sets, id: \.id) { s in
                                HStack {
                                    Text("Set \(s.setOrder)\(s.isWarmup ? " · warmup" : "")")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(setSummary(s)).font(.caption.weight(.medium).monospacedDigit())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(fromUsername ?? "Workout")
        #if !os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private struct ExerciseGroup { let name: String; let sets: [LiveWorkoutSetDTO] }

    private var groupedExercises: [ExerciseGroup] {
        var order: [String] = []
        var byName: [String: [LiveWorkoutSetDTO]] = [:]
        for s in sets.sorted(by: { ($0.exerciseOrder, $0.setOrder) < ($1.exerciseOrder, $1.setOrder) }) {
            if byName[s.exerciseName] == nil { order.append(s.exerciseName) }
            byName[s.exerciseName, default: []].append(s)
        }
        return order.map { ExerciseGroup(name: $0, sets: byName[$0] ?? []) }
    }

    private func setSummary(_ s: LiveWorkoutSetDTO) -> String {
        let weight = s.weightLbs.map { WeightFormat.display($0) } ?? "—"
        let reps = s.reps.map { "\($0)" } ?? "—"
        return "\(weight) × \(reps)"
    }

    private func load() async {
        loading = true
        sets = (try? await svc.sessionSets(session.id)) ?? []
        loading = false
    }
}

/// Compact "time ago" for the friend-activity feed ("just now", "2h ago", "3d ago").
enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60))m ago"
        case ..<86_400: return "\(Int(s / 3600))h ago"
        case ..<604_800: return "\(Int(s / 86_400))d ago"
        default: return "\(Int(s / 604_800))w ago"
        }
    }
}

/// Small weight formatter honoring the user's unit preference.
enum WeightFormat {
    static func display(_ lbs: Double) -> String {
        if Preferences.weightUnit == .kg {
            return String(format: "%.0f kg", lbs / 2.2046226218)
        }
        return String(format: "%.0f lb", lbs)
    }
}
