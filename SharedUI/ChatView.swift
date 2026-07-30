import SwiftUI
import DriftCore

/// One-to-one chat with a friend or coach. Messages are DB-backed (Supabase
/// `messages` table, RLS-scoped to the two parties). Polls every few seconds
/// for new messages — buffered HTTPS, so it works identically on iOS + Android
/// (no websocket dependency). Single-source SharedUI.
struct ChatView: View {
    let peer: SharedProfile
    /// Shown under the title, e.g. "your coach" / "your client" / "friend".
    var relationship: String = "friend"

    @State var messages: [MessageDTO] = []
    @State var draft = ""
    @State var loading = true
    @State var sending = false
    @State var myID: String?
    @State var error: String?

    private var svc: SharingService { .shared }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if loading {
                        ProgressView().padding(.top, 40)
                    } else if messages.isEmpty {
                        Text("Say hi to @\(peer.username) 👋")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .padding(.top, 40)
                    }
                    ForEach(messages) { m in bubble(m) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            }
            #if !os(Android)
            .defaultScrollAnchor(.bottom)
            #endif

            if let error {
                Text(error).font(.caption2).foregroundStyle(Theme.surplus)
                    .padding(.horizontal, 14).padding(.bottom, 4)
            }

            inputBar
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("@\(peer.username)")
        #if !os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            myID = svc.currentSession?.userID
            await load()
            await pollLoop()
        }
    }

    private func bubble(_ m: MessageDTO) -> some View {
        let mine = m.senderId == myID
        return HStack {
            if mine { Spacer(minLength: 48) }
            Text(m.body)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Theme.ink : Theme.cardBackground,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(mine ? Color.white : Theme.textPrimary)
            if !mine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message @\(peer.username)", text: $draft)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(false)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.pillBackground, in: Capsule())
            Button {
                Task { @MainActor in await send() }
            } label: {
                Image(systemName: sym("paperplane.fill"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canSend ? Color.white : Theme.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Theme.ink : Theme.pillBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sending)
        }
        .padding(.horizontal, 12).padding(.top, 10)
        // Clear the app's floating tab bar (a global overlay that stays on
        // pushed screens) so the input isn't hidden behind it.
        .padding(.bottom, 96)
        .background(Theme.cardBackground.ignoresSafeArea(edges: .bottom))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() async {
        loading = true
        messages = (try? await svc.fetchMessages(with: peer.id)) ?? []
        loading = false
        markRead()
    }

    /// Reading the conversation IS reading it.
    ///
    /// Both marks: the LOCAL one keeps the UI instant and works offline, and the
    /// SERVER watermark (migration 0010) is what makes the count correct on the
    /// next launch and on another device. Local-only was the bug — it could not
    /// see messages the client hadn't downloaded, so unread silently read zero.
    private func markRead() {
        SeenMarks.markMessagesSeen(peer: peer.id)
        Task { try? await svc.markThreadRead(peer: peer.id) }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; error = nil
        draft = ""
        do {
            let msg = try await svc.sendMessage(to: peer.id, body: body)
            if !messages.contains(where: { $0.id == msg.id }) { messages.append(msg) }
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:)) ?? error.localizedDescription
            draft = body   // restore so the user doesn't lose their text
        }
        sending = false
    }

    /// Poll for new messages while the chat is open (auto-cancelled on leave).
    ///
    /// INCREMENTAL. This used to re-request the entire 200-message thread every
    /// 3 seconds and diff it against what was on screen — 20 requests a minute,
    /// up to 200 rows each, per open chat, of which essentially none were new.
    /// It now asks only for messages newer than the last one it holds, so the
    /// steady state is an empty response.
    ///
    /// The cursor is the newest message's SERVER timestamp, not a local clock:
    /// a device running a minute fast would otherwise skip everything sent in
    /// that minute and the messages would never appear.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { break }

            guard let cursor = messages.last?.createdAt else {
                // Empty thread — nothing to be newer than, so a full fetch is
                // both correct and cheap.
                if let fresh = try? await svc.fetchMessages(with: peer.id), !fresh.isEmpty {
                    messages = fresh
                    markRead()
                }
                continue
            }
            guard let arrived = try? await svc.messages(with: peer.id, since: cursor),
                  !arrived.isEmpty else { continue }

            // Append only what we don't already hold: a send that lands between
            // the poll firing and its response would otherwise double up.
            let known = Set(messages.map(\.id))
            let fresh = arrived.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { continue }
            messages.append(contentsOf: fresh)
            // Still on screen, so anything that just arrived is read.
            markRead()
        }
    }
}
