import SwiftUI
import DriftCore

/// Your coach, as a page rather than a chat shortcut.
///
/// The Today surface used to say "Tap to message your coach" and drop you into a
/// message thread. The operator's objection (2026-07-30): messaging is the
/// smallest part of having a coach — "it can also be something like *your coach*
/// page, where you see more than a message, like what they assigned to you".
///
/// Reading order is what a client actually wants to know, most actionable first:
///
///   1. **What they assigned you** — a plan waiting to be accepted is the only
///      thing on this page that's blocking you.
///   2. **Message** — one action among several, not the headline.
///   3. **What they wrote and what they can see** — delegated to
///      `CoachSharingCard`, which already renders this coach's dated notes and
///      the rolled-up consent state. Reused rather than reimplemented: two
///      places rendering consent is two places for it to disagree.
///
/// The assignment section hides when empty. A page of empty-state cards teaches
/// people the page is never worth opening.
struct CoachPageView: View {
    let coach: SharedProfile

    /// Not private — Fuse can't bridge private @State.
    @State var assignments: [SharedTemplateDTO] = []
    @State var unread = 0
    @State var loading = true
    @State var busy = false
    @State var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Theme.surplus)
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    if !assignments.isEmpty { assignedSection }
                    messageRow
                    CoachSharingCard(coach: coach)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Your coach")
        .task { await load() }
    }

    // MARK: - Header

    var header: some View {
        HStack(spacing: 10) {
            Text(String(coach.username.prefix(1)).uppercased())
                .font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(coach.displayName ?? "@\(coach.username)")
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Text("@\(coach.username) · coaches you")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .card()
    }

    // MARK: - Assigned plans

    var assignedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASSIGNED TO YOU").sectionHeading()
            ForEach(assignments) { dto in
                VStack(alignment: .leading, spacing: 6) {
                    Text(dto.name)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    // Say what's in it before asking someone to accept it.
                    Text(planSummary(dto))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = dto.note, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(.caption).italic().foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button {
                            Task { await accept(dto) }
                        } label: {
                            Text("Add to my workouts").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        .disabled(busy)

                        Button {
                            Task { await decline(dto) }
                        } label: {
                            Text("Not now").font(.caption)
                        }
                        .buttonStyle(.bordered).tint(Theme.textSecondary)
                        .disabled(busy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    func planSummary(_ dto: SharedTemplateDTO) -> String {
        let exercises = dto.exercises
        guard !exercises.isEmpty else { return "Empty plan" }
        let names = exercises.prefix(3).map(\.name).joined(separator: " · ")
        let more = exercises.count > 3 ? " +\(exercises.count - 3) more" : ""
        return "\(exercises.count) exercises — \(names)\(more)"
    }

    // MARK: - Message

    var messageRow: some View {
        NavigationLink { ChatView(peer: coach, relationship: "coach") } label: {
            HStack(spacing: 10) {
                Image(systemName: sym("bubble.left.and.bubble.right.fill"))
                    .font(.subheadline).foregroundStyle(Theme.chartTrend)
                Text("Message").font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if unread > 0 {
                    Text("\(unread) new")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent, in: Capsule())
                }
                Image(systemName: sym("chevron.right"))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    func accept(_ dto: SharedTemplateDTO) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await SharingService.shared.acceptSharedTemplate(dto)
            assignments.removeAll { $0.id == dto.id }
            FeatureUsage.record(TelemetryEvent.templateShared)
        } catch {
            errorText = "Couldn't add that plan. Try again."
        }
    }

    func decline(_ dto: SharedTemplateDTO) async {
        busy = true
        defer { busy = false }
        do {
            try await SharingService.shared.declineSharedTemplate(dto)
            assignments.removeAll { $0.id == dto.id }
        } catch {
            errorText = "Couldn't dismiss that plan. Try again."
        }
    }

    // MARK: - Load

    func load() async {
        let svc = SharingService.shared
        async let incoming = try? svc.incomingSharedTemplates()
        async let inbox = try? svc.recentInbox()

        // Only THIS coach's assignments — the page is about one person, and
        // someone with two coaches must not see them merged.
        assignments = ((await incoming) ?? []).filter { $0.ownerId == coach.id }
        unread = SeenMarks.unreadCount(peer: coach.id, messages: (await inbox) ?? [])
        loading = false
    }
}
