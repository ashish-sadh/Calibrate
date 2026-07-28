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
    @State var requests: [FriendshipDTO] = []
    @State var conns: [Connection] = []
    @State var incomingTemplates: [SharedTemplateDTO] = []
    @State var clientSessions: [LiveWorkoutDTO] = []

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
            searchCard
            if !requests.isEmpty { requestsCard }
            if !incomingTemplates.isEmpty { incomingTemplatesCard }
            if !clientSessions.isEmpty { workoutsFromFriendsCard }
            if !coaches.isEmpty { connectionSection("YOUR COACHES", coaches, subtitle: "coaches you") }
            if !clients.isEmpty { connectionSection("YOUR CLIENTS", clients, subtitle: "you coach") }
            connectionSection("FRIENDS", friendConns, subtitle: nil,
                              emptyText: "No friends yet. Search a @username above to add a friend or a coach.")
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
                        Image(systemName: sym("bubble.left.fill"))
                            .font(.caption).foregroundStyle(Theme.chartTrend)
                        Image(systemName: sym("chevron.right"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle()).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                if c.id != list.last?.id { Divider().overlay(Theme.separatorFaint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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

    private var identityCard: some View {
        HStack(spacing: 12) {
            avatar(svc.currentUsername ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(svc.currentUsername ?? "")")
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Text("Signed in").font(.caption2).foregroundStyle(Theme.textSecondary)
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
                    if requestedIDs.contains(profile.id) {
                        Label("Sent", systemImage: sym("checkmark"))
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
                HStack(spacing: 10) {
                    avatar("?")
                    Text(req.role == .trainer ? "Trainer request" : "Friend request")
                        .font(.subheadline)
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
        async let connections = try? await svc.connections()
        async let sessions = try? await svc.clientSessions()
        requests = await reqs ?? []
        incomingTemplates = await tmpls ?? []
        clientSessions = await sessions ?? []
        conns = await connections ?? []
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
        searchResults = []; requests = []; conns = []; incomingTemplates = []
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
