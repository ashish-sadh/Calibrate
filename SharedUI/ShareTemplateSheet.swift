import SwiftUI
import DriftCore

/// Pick a friend to send/assign a workout template to. Pushed from the template
/// preview's "Send to a friend" action. Single-source (iOS + Android). Pushed
/// rather than sheet-presented so it never stacks a second presentation
/// modifier on the preview sheet (Skip Fuse breaks on stacked presentations).
struct ShareTemplateSheet: View {
    let template: WorkoutTemplate
    var onSent: () -> Void = {}

    @State var friends: [SharedProfile] = []
    @State var loading = true
    @State var sendingTo: String?
    @State var sentTo: Set<String> = []
    @State var note = ""
    @State var error: String?

    private var svc: SharingService { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.headline)
                    Text("\(template.exercises.count) exercises").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTE (OPTIONAL)").sectionHeading()
                    TextField("e.g. Try this for leg day 💪", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if !svc.isSignedIn {
                    signInPrompt
                } else if friends.isEmpty {
                    emptyState
                } else {
                    friendList
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(Theme.surplus)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Send to a friend")
        #if !os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var friendList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FRIENDS").sectionHeading()
            ForEach(friends) { f in
                HStack(spacing: 10) {
                    Text(f.username.first.map { String($0).uppercased() } ?? "?")
                        .font(.headline).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("@\(f.username)").font(.subheadline.weight(.medium))
                        if let name = f.displayName, !name.isEmpty {
                            Text(name).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    if sentTo.contains(f.id) {
                        Label("Sent", systemImage: sym("checkmark"))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.deficit)
                    } else if sendingTo == f.id {
                        ProgressView()
                    } else {
                        Button { Task { await send(to: f) } } label: {
                            Text("Send").font(.caption.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No friends yet").font(.subheadline.weight(.semibold))
            Text("Add friends from More → Friends, then come back to share this workout.")
                .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).card()
    }

    private var signInPrompt: some View {
        VStack(spacing: 8) {
            Text("Sign in to share").font(.subheadline.weight(.semibold))
            Text("Open More → Friends to set up sharing, then send this workout to a friend.")
                .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).card()
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard svc.isSignedIn else { return }
        if let edges = try? await svc.acceptedFriendships() {
            let me = svc.currentSession?.userID
            let ids = edges.map { $0.requesterId == me ? $0.addresseeId : $0.requesterId }
            friends = (try? await svc.profiles(ids: ids)) ?? []
        }
    }

    private func send(to friend: SharedProfile) async {
        sendingTo = friend.id
        error = nil
        do {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try await svc.shareTemplate(template, to: friend.id, note: trimmed.isEmpty ? nil : trimmed)
            sentTo.insert(friend.id)
            onSent()
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:)) ?? error.localizedDescription
        }
        sendingTo = nil
    }
}
