import SwiftUI
import DriftCore

/// In-app support: file a bug or suggestion, then watch the thread. Single-source
/// for both apps (operator ask 2026-07-28 — "so customers can file bugs or
/// suggestions and we reply them and provide updates").
///
/// No sign-in required: tickets are keyed by the anonymous install id, because
/// making someone claim a @username before they can report a crash loses the
/// report. See `SupportService`.
struct SupportView: View {
    @State var tickets: [SupportTicketDTO] = []
    @State var loading = true
    @State var composing = false
    @State var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { composing = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sym("plus.circle.fill")).foregroundStyle(.white)
                        Text("Report a bug or suggest something")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                if let error {
                    Text(error).font(.caption).foregroundStyle(Theme.surplus)
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if tickets.isEmpty {
                    Text("Nothing filed yet. Anything you report shows up here with our reply and its status.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(tickets) { ticket in
                        NavigationLink { SupportThreadView(ticket: ticket) } label: {
                            ticketRow(ticket)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Support")
        .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) {
            SupportComposeView()
        }
        .task { await load() }
    }

    func ticketRow(_ ticket: SupportTicketDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ticket.subject)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                statusPill(ticket)
            }
            Text(ticket.body)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Status carries the whole promise of this feature — that a report goes
    /// somewhere — so it is the one element with colour.
    func statusPill(_ ticket: SupportTicketDTO) -> some View {
        let tint: Color = switch ticket.status {
        case .open: Theme.textSecondary
        case .inProgress: Theme.fatYellow
        case .fixed, .released: Theme.deficit
        case .wontFix: Theme.textTertiary
        }
        let label = ticket.status == .released && ticket.releasedIn != nil
            ? "Released \(ticket.releasedIn ?? "")"
            : ticket.status.displayName
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            tickets = try await SupportService.myTickets()
            error = nil
        } catch {
            // Offline is the common case here; don't shout about it.
            self.error = "Couldn't reach support just now — your reports are safe, try again later."
        }
    }
}

// MARK: - Compose

struct SupportComposeView: View {
    @Environment(\.dismiss) var dismiss
    @State var kind: SupportKind = .bug
    @State var subject = ""
    @State var body_ = ""
    @State var sending = false
    @State var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                        Spacer()
                    }

                    Picker("Kind", selection: $kind) {
                        ForEach(SupportKind.allCases, id: \.self) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    SupportSubjectField(subject: $subject)
                    SupportBodyEditor(text: $body_)

                    if let error {
                        Text(error).font(.caption).foregroundStyle(Theme.surplus)
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        Text(sending ? "Sending…" : "Send")
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || subject.trimmingCharacters(in: .whitespaces).isEmpty)

                    Text("Your app version and platform are attached so we can reproduce it. No health data is included.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
        }
    }

    func send() async {
        sending = true
        defer { sending = false }
        do {
            try await SupportService.fileTicket(
                kind: kind,
                subject: subject.trimmingCharacters(in: .whitespaces),
                body: body_.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            self.error = "Couldn't send that. Check your connection and try again."
        }
    }
}

/// Each TextField gets its own View — Fuse binds only the FIRST TextField per
/// ViewBuilder scope (skipui_one_textfield_per_scope).
struct SupportSubjectField: View {
    @Binding var subject: String
    var body: some View {
        TextField("What happened?", text: $subject)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
    }
}

struct SupportBodyEditor: View {
    @Binding var text: String
    var body: some View {
        // The multiline `axis:` initializer is unavailable on Fuse, as is the
        // range form of lineLimit — Android gets a plain growing field.
        #if os(Android)
        TextField("Steps to reproduce, or what you'd like instead", text: $text)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        #else
        TextField("Steps to reproduce, or what you'd like instead", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(4...10)
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        #endif
    }
}

// MARK: - Thread

struct SupportThreadView: View {
    let ticket: SupportTicketDTO
    @State var messages: [SupportMessageDTO] = []
    @State var draft = ""
    @State var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ticket.subject).font(.headline)
                    Text(ticket.body).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    if ticket.status == .released, let build = ticket.releasedIn {
                        Text("Fixed in build \(build) — update to get it.")
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.deficit)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                ForEach(messages) { message in
                    bubble(message)
                }

                SupportReplyField(draft: $draft)
                Button {
                    Task { await sendReply() }
                } label: {
                    Text("Reply").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Ticket")
        .task { await load() }
    }

    func bubble(_ message: SupportMessageDTO) -> some View {
        HStack {
            if message.fromStaff { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 4) {
                if message.fromStaff {
                    Text("Drift team").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                }
                Text(message.body).font(.subheadline)
                    .foregroundStyle(message.fromStaff ? .white : Theme.textPrimary)
            }
            .padding(10)
            .background(message.fromStaff ? Theme.accent : Theme.cardBackgroundElevated,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            if !message.fromStaff { Spacer(minLength: 24) }
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        messages = (try? await SupportService.messages(ticketID: ticket.id)) ?? []
    }

    func sendReply() async {
        let body = draft.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        draft = ""
        try? await SupportService.reply(ticketID: ticket.id, body: body)
        await load()
    }
}

struct SupportReplyField: View {
    @Binding var draft: String
    var body: some View {
        TextField("Add something…", text: $draft)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
    }
}
