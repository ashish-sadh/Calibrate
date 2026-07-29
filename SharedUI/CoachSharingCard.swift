import SwiftUI
import DriftCore

/// The client's control over what one coach can see beyond their workouts.
///
/// Four separate switches rather than one "share everything", because "my coach
/// sees my protein" and "my coach sees my injuries" are genuinely different
/// decisions and a person may want exactly one of them. Off by default:
/// connecting to a coach is consent to share workouts, not a standing grant
/// over health data.
///
/// Flipping a switch pushes immediately, so what the coach sees always matches
/// what the switches say — a toggle that needs a separate "sync" step is a
/// toggle that will silently lie about consent.
struct CoachSharingCard: View {
    let coach: SharedProfile

    @State var level = BriefingSharingLevel.none
    @State var syncing = false
    @State var error: String?
    @State var showingPreview = false
    @State var preview: ClientBriefing?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SHARE WITH @\(coach.username)").sectionHeading()
                Spacer()
                if syncing {
                    Text("Updating…").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            // The label names EVERYTHING this level shares — since 2026-07-29
            // that includes coach-relevant notes distilled from AI-coach
            // chats. Consent people can't read is not consent.
            row("Training history, injuries & AI-chat notes", .history)
            row("Average sleep", .sleep)
            row("Average calories & protein", .nutrition)
            row("Weight trend", .weight)
            row("Body composition (DEXA)", .bodyComp)

            Text(level == .none
                 ? "Your coach sees only the workouts you share."
                 : "Averages and scan summaries only — your coach never sees individual meals, weigh-ins, nights or scan documents.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)

            // The mirror (#1156): the client can read EXACTLY what the coach
            // reads — the preview is the coach's own view fed local data, so
            // the two can never drift apart.
            if level != .none {
                Button {
                    showingPreview.toggle()
                    if showingPreview { Task { await loadPreview() } }
                } label: {
                    Label(showingPreview ? "Hide preview" : "See what @\(coach.username) sees",
                          systemImage: sym("eye"))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.chartTrend)
                }
                .buttonStyle(.plain)

                if showingPreview {
                    if let preview {
                        CoachBriefingView(
                            briefing: preview,
                            emptyText: "Nothing to show yet — the shared categories have no data.")
                            .padding(10)
                            .background(Theme.cardBackgroundElevated,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    } else {
                        ProgressView()
                    }
                }
            }

            if let error {
                Text(error).font(.caption2).foregroundStyle(Theme.surplus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task { level = BriefingSharingLevel.stored(for: coach.id) }
    }

    /// Build the preview from LOCAL data at the current level — the same
    /// snapshot + notes the push sends, rendered by the same view the coach
    /// renders. Rebuilt on every open so toggle flips reflect immediately.
    func loadPreview() async {
        preview = nil
        let metrics = await BriefingSnapshot.metrics(level: level)
        let notes = CoachNotes.load()
        let sharesHistory = level.contains(.history)
        preview = ClientBriefing(
            clientID: "preview",
            summary: sharesHistory ? notes.intake.summary : "",
            notes: sharesHistory ? notes.notes : [],
            metrics: metrics)
    }

    func row(_ label: String, _ option: BriefingSharingLevel) -> some View {
        Toggle(isOn: Binding(
            get: { level.contains(option) },
            set: { on in
                if on { level.insert(option) } else { level.remove(option) }
                Task { await push() }
                // A preview that lags the switches is a preview that lies.
                if showingPreview { Task { await loadPreview() } }
            }
        )) {
            Text(label).font(.subheadline).foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.accent)
    }

    /// Persist the choice locally FIRST, then push. If the network fails the
    /// switch still reflects what the user asked for and the next push carries
    /// it — but a REVOCATION must not be left to a retry, so turning everything
    /// off deletes server-side and surfaces any failure.
    func push() async {
        level.store(for: coach.id)
        syncing = true
        error = nil
        defer { syncing = false }

        do {
            if level == .none {
                try await SharingService.shared.revokeBriefing(from: coach.id)
                return
            }
            let notes = CoachNotes.load()
            let metrics = await BriefingSnapshot.metrics(level: level)
            try await SharingService.shared.shareBriefing(
                with: coach.id, level: level, notes: notes, metrics: metrics)
        } catch {
            self.error = "Couldn't update sharing — it'll retry next time you open this."
        }
    }
}
