import SwiftUI
import DriftCore

/// Inline recipient list for sending something to your people. The ONE share
/// surface component (workout completion, template send) — coaches pinned on
/// top with a badge, search once the list is long enough to need it, one-tap
/// "Share with all", per-row Send → spinner → Sent.
///
/// Owns its own load/send state; the caller supplies the actual send via
/// `onSend` and can react per-recipient via `onSent` (e.g. telemetry, toasts).
///
/// Skip Fuse notes: no `private` on @State (Fuse can't bridge it), and this
/// struct holds exactly one TextField — Fuse binds only the first TextField
/// per ViewBuilder scope, so the search field must not share a scope with a
/// caller's fields.
struct FriendSharePicker: View {
    /// Sends the payload to one recipient; a throw shows the error inline.
    let onSend: (Connection) async throws -> Void
    /// Called after each successful send (telemetry, "sent" toasts).
    var onSent: (Connection) -> Void = { _ in }

    @State var connections: [Connection] = []
    @State var loaded = false
    @State var query = ""
    @State var sendingTo: String? = nil   // profile id; "*" while broadcasting
    @State var sentTo: Set<String> = []
    @State var sendError: String? = nil

    /// Search only earns its row once scanning the list beats typing.
    var searchable: Bool { connections.count >= 6 }

    var filtered: [Connection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return connections }
        return connections.filter {
            $0.profile.username.lowercased().contains(q)
                || ($0.profile.displayName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if !loaded {
                ProgressView()
            } else if connections.isEmpty {
                Text("No connections yet — add a friend or coach in More → Friends.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                if searchable { searchField }
                if connections.count > 1 && query.isEmpty {
                    shareWithAllButton
                    Divider().overlay(Theme.separatorFaint)
                }
                if filtered.isEmpty {
                    Text("No matches for “\(query)”")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(filtered) { row($0) }
                }
            }
            if let sendError {
                Text(sendError).font(.caption2).foregroundStyle(Theme.surplus)
            }
        }
        .task { await load() }
    }

    var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: sym("magnifyingglass"))
                .font(.caption).foregroundStyle(Theme.textTertiary)
            TextField("Search people", text: $query)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
    }

    var shareWithAllButton: some View {
        Button { Task { await sendToAll() } } label: {
            HStack {
                Spacer()
                if sendingTo == "*" { ProgressView().tint(.white) }
                else { Text("Share with all \(connections.count)").font(.caption.weight(.semibold)) }
                Spacer()
            }
            .padding(.vertical, 8)
            .background(Theme.chartTrend, in: Capsule()).foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    func row(_ c: Connection) -> some View {
        HStack(spacing: 10) {
            Text(c.profile.username.first.map { String($0).uppercased() } ?? "?")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("@\(c.profile.username)").font(.subheadline)
                    if c.kind == .coach {
                        Text("COACH").font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.chartTrend.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.chartTrend)
                    } else if c.kind == .client {
                        Text("CLIENT").font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.textTertiary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if let name = c.profile.displayName, !name.isEmpty {
                    Text(name).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if sentTo.contains(c.id) {
                Label("Sent", systemImage: sym("checkmark"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.deficit)
            } else if sendingTo == c.id {
                ProgressView()
            } else {
                Button("Send") { Task { await send(to: c) } }
                    .font(.caption.weight(.semibold)).tint(Theme.chartTrend)
            }
        }
    }

    func load() async {
        loaded = false
        // Coaches first — they're who you share with on purpose; then friends,
        // then clients. Alphabetical inside each band so the order is stable.
        func band(_ k: Connection.Kind) -> Int { k == .coach ? 0 : (k == .friend ? 1 : 2) }
        let conns = (try? await SharingService.shared.connections()) ?? []
        connections = conns.sorted {
            band($0.kind) != band($1.kind)
                ? band($0.kind) < band($1.kind)
                : $0.profile.username.lowercased() < $1.profile.username.lowercased()
        }
        loaded = true
    }

    func send(to c: Connection) async {
        sendingTo = c.id
        sendError = nil
        do {
            try await onSend(c)
            sentTo.insert(c.id)
            onSent(c)
        } catch {
            sendError = (error as? SharingError).map(String.init(describing:)) ?? error.localizedDescription
        }
        sendingTo = nil
    }

    /// One-tap broadcast to everyone not already sent. An error mid-loop is
    /// surfaced but doesn't stop the remaining sends.
    func sendToAll() async {
        sendingTo = "*"
        sendError = nil
        for c in connections where !sentTo.contains(c.id) {
            do {
                try await onSend(c)
                sentTo.insert(c.id)
                onSent(c)
            } catch {
                sendError = (error as? SharingError).map(String.init(describing:)) ?? error.localizedDescription
            }
        }
        sendingTo = nil
    }
}
