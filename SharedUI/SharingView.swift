import SwiftUI
import DriftCore

/// Friends & Trainer sharing — single-source hub for iOS + Android.
///
/// Opt-in and off by default: nothing here touches the network until the user
/// signs in with an email code and claims a @username. The transport lives in
/// DriftCore (`SharingService`), so this file is pure presentation and works on
/// both platforms (buffered HTTPS — no streaming/websocket dependency).
struct SharingView: View {

    private enum Stage: Equatable {
        case loading, signedOut, awaitingCode, needsUsername, ready
    }

    @State private var stage: Stage = .loading
    @State private var busy = false
    @State private var error: String?

    // Auth
    @State private var email = ""
    @State private var code = ""
    @State private var username = ""

    // Hub data
    @State private var searchText = ""
    @State private var searchResults: [SharedProfile] = []
    @State private var requests: [FriendshipDTO] = []
    @State private var friends: [SharedProfile] = []
    @State private var incomingTemplates: [SharedTemplateDTO] = []

    private var svc: SharingService { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch stage {
                case .loading:
                    ProgressView().padding(.top, 60)
                case .signedOut:
                    signInCard
                case .awaitingCode:
                    codeCard
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

    // MARK: - Auth stages

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SIGN IN").sectionHeading()
            Text("Sharing uses a lightweight account so friends can find you by @username. Your email is only for sign-in — it's never shown to anyone.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                #if !os(Android)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            primaryButton("Send login code", busy: busy) {
                await run {
                    try await svc.sendEmailCode(email.trimmingCharacters(in: .whitespaces))
                    stage = .awaitingCode
                }
            }
            .disabled(email.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ENTER CODE").sectionHeading()
            Text("We emailed a 6-digit code to \(email). Enter it to finish signing in.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            TextField("123456", text: $code)
                .textFieldStyle(.roundedBorder)
                #if !os(Android)
                .keyboardType(.numberPad)
                #endif
            primaryButton("Verify", busy: busy) {
                await run {
                    try await svc.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces),
                                                  code: code.trimmingCharacters(in: .whitespaces))
                    await afterSignIn()
                }
            }
            .disabled(code.count < 6)
            Button("Use a different email") { stage = .signedOut; code = "" }
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PICK A USERNAME").sectionHeading()
            Text("This is how friends find you. Lowercase letters, numbers and underscores, 3–20 characters.")
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
                    try await svc.claimUsername(normalizedUsername)
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
            friendsCard
        }
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
                svc.signOut()
                reset()
                stage = .signedOut
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
                if !searchText.isEmpty {
                    Button { searchText = ""; searchResults = [] } label: {
                        Image(systemName: sym("xmark")).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(10)
            .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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
                    Button {
                        Task { await sendRequest(to: profile) }
                    } label: {
                        Text("Add").font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.ink, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
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

    private var friendsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FRIENDS").sectionHeading()
            if friends.isEmpty {
                Text("No friends yet. Search a @username above to send a request.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(friends) { f in
                    HStack(spacing: 10) {
                        avatar(f.username)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(f.username)").font(.subheadline.weight(.medium))
                            if let name = f.displayName, !name.isEmpty {
                                Text(name).font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
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
        guard svc.isConfigured else { stage = .signedOut; return }
        if svc.isSignedIn {
            if svc.currentUsername == nil { stage = .needsUsername }
            else { await afterSignIn() }
        } else {
            stage = .signedOut
        }
    }

    private func afterSignIn() async {
        if svc.currentUsername == nil { stage = .needsUsername; return }
        stage = .ready
        await refreshHub()
    }

    private func refreshHub() async {
        async let reqs = try? await svc.incomingRequests()
        async let tmpls = try? await svc.incomingSharedTemplates()
        async let edges = try? await svc.acceptedFriendships()
        requests = await reqs ?? []
        incomingTemplates = await tmpls ?? []
        if let edges = await edges {
            let me = svc.currentSession?.userID
            let otherIDs = edges.map { $0.requesterId == me ? $0.addresseeId : $0.requesterId }
            friends = (try? await svc.profiles(ids: otherIDs)) ?? []
        }
    }

    private func search() async {
        await run(showBusy: false) {
            searchResults = try await svc.searchUsers(searchText)
        }
    }

    private func sendRequest(to profile: SharedProfile) async {
        await run(showBusy: false) {
            try await svc.sendRequest(to: profile.id)
            searchResults.removeAll { $0.id == profile.id }
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
        email = ""; code = ""; username = ""; searchText = ""
        searchResults = []; requests = []; friends = []; incomingTemplates = []
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
