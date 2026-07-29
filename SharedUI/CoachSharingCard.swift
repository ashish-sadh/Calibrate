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

            Text(level == .none
                 ? "Your coach sees only the workouts you share."
                 : "Averages only — your coach never sees individual meals, weigh-ins or nights.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)

            if let error {
                Text(error).font(.caption2).foregroundStyle(Theme.surplus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task { level = BriefingSharingLevel.stored(for: coach.id) }
    }

    func row(_ label: String, _ option: BriefingSharingLevel) -> some View {
        Toggle(isOn: Binding(
            get: { level.contains(option) },
            set: { on in
                if on { level.insert(option) } else { level.remove(option) }
                Task { await push() }
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
