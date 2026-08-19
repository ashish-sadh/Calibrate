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
    /// What this coach has written about you. Not gated by any toggle — your
    /// coach's notes about you are yours to read unconditionally.
    @State var notesFromCoach: [CoachAuthoredNote] = []
    /// Whether this coach has been granted the client's full training past
    /// (migration 0015). Absent grant = only since they became your coach.
    @State var fullHistoryShared = false
    @State var historyBusy = false
    /// The goal the user chose to share with this coach. Editing is explicit —
    /// see `goalRow`.
    @State var goalDraft = Preferences.sharedGoalStatement ?? ""
    @State var editingGoal = false
    /// Folded by default — see the body comment. Not private: Fuse can't bridge
    /// private @State.
    @State var expanded = false

    /// One-line consent state for the collapsed header: how much of what's
    /// available is on. "Sharing 4 of 6" reads instantly; "4" alone doesn't say
    /// whether that's most or barely any.
    var summary: String {
        let on = level.descriptions.count
        guard on > 0 else { return "Not sharing" }
        return "Sharing \(on) of \(BriefingSharingLevel.allCategories.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ROLLED UP by default (operator 2026-07-29: "no need to see all
            // the time how many things are being shared… also what if I have
            // multiple coaches"). Six toggles inline ate half the Friends
            // screen, and one card PER coach made the hub unusable past the
            // first one. Consent still has to be READABLE, so the collapsed
            // header states the count and the categories in one line — you can
            // see what you share without unfolding anything.
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("SHARING WITH @\(coach.username)").sectionHeading()
                    Spacer()
                    if syncing {
                        Text("Updating…").font(.caption2).foregroundStyle(Theme.textTertiary)
                    } else {
                        Text(summary)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(level == .none ? Theme.textTertiary : Theme.chartTrend)
                    }
                    Image(systemName: sym(expanded ? "chevron.up" : "chevron.down"))
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !expanded, level != .none {
                // The categories, named, without six switch rows.
                Text(level.descriptions.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }

            if expanded {
                // The label names EVERYTHING this level shares — since
                // 2026-07-29 that includes coach-relevant notes distilled from
                // AI-coach chats. Consent people can't read is not consent.
                goalRow
                historyTransferRow
                row("Training history, injuries & your goal", .history)
                row("Average sleep", .sleep)
                row("Average calories & protein", .nutrition)
                row("Weight trend", .weight)
                row("Body composition (DEXA: fat %, lean mass, regional)", .bodyComp)
                row("Training detail (best sets & recovery)", .strength)

                Text(level == .none
                     ? "Your coach sees only the workouts you share."
                     : "Averages and scan summaries only — your coach never sees individual meals, weigh-ins, nights or scan documents.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }

            // The mirror (#1156): the client can read EXACTLY what the coach
            // reads — the preview is the coach's own view fed local data, so
            // the two can never drift apart.
            if level != .none {
                Button {
                    showingPreview.toggle()
                    if showingPreview { Task { await loadPreview() } }
                } label: {
                    #if os(Android)
                    // skip-ui maps no eye/visibility glyph — sym("eye") fell
                    // through to the WARNING TRIANGLE, which in front of "see
                    // what your coach sees" reads as a privacy alarm (#1233).
                    // Drawn eye instead (EyeGlyph.swift).
                    Label {
                        Text(showingPreview ? "Hide preview" : "See what @\(coach.username) sees")
                    } icon: {
                        EyeShape().fill(Theme.chartTrend).frame(width: 13, height: 13)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.chartTrend)
                    #else
                    Label(showingPreview ? "Hide preview" : "See what @\(coach.username) sees",
                          systemImage: sym("eye"))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.chartTrend)
                    #endif
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

            // What your coach wrote about you, dated and attributed. Shown
            // regardless of the toggles: these are their words about you, and
            // withholding them from you would be the one-way file the design
            // explicitly refuses (migration 0006).
            if !notesFromCoach.isEmpty {
                Divider().overlay(Theme.separatorFaint)
                Text("NOTES FROM @\(coach.username.uppercased())").sectionHeading()
                ForEach(notesFromCoach.prefix(5)) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.dateOnly)
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        Text(note.text)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if let error {
                Text(error).font(.caption2).foregroundStyle(Theme.surplus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task {
            level = BriefingSharingLevel.stored(for: coach.id)
            notesFromCoach = (try? await SharingService.shared.coachNotes(
                clientID: SharingService.shared.currentSession?.userID ?? "",
                coachID: coach.id)) ?? []
            await loadHistoryGrant()
        }
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
        DriftToggle(isOn: Binding(
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
    /// Handing over your whole training past — the operator's "transfer forever
    /// history".
    ///
    /// Off by default, and the default is NOT "nothing": a coach always sees
    /// what you've done since they became your coach. This switch decides
    /// whether they also see everything BEFORE that, which is what makes
    /// changing or restarting with a coach not mean starting from zero.
    ///
    /// Separate from the `.history` consent bit above, which governs the
    /// distilled briefing. This one governs raw sessions, and they are genuinely
    /// different asks.
    var historyTransferRow: some View {
        DriftToggle(isOn: Binding(
            get: { fullHistoryShared },
            set: { on in
                fullHistoryShared = on
                Task { await setFullHistory(on) }
            }
        ), enabled: !historyBusy) {
            VStack(alignment: .leading, spacing: 1) {
                Text("My full training history").font(.caption)
                Text(fullHistoryShared
                     ? "Everything, back to your first session"
                     : "Only since @\(coach.username) became your coach")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    func setFullHistory(_ on: Bool) async {
        historyBusy = true
        defer { historyBusy = false }
        do {
            if on {
                // nil = forever.
                try await SharingService.shared.setHistoryGrant(coachID: coach.id, from: nil)
            } else {
                try await SharingService.shared.clearHistoryGrant(coachID: coach.id)
            }
        } catch let failure {
            // Reflect the failure rather than leaving the switch lying about
            // what the coach can see. (`catch` shadows the @State `error`, so
            // the binding is named.)
            _ = failure
            fullHistoryShared = !on
            error = "Couldn't update history sharing. Try again."
        }
    }

    func loadHistoryGrant() async {
        guard let grant = try? await SharingService.shared.historyGrant(coachID: coach.id)
        else { return }
        // A grant with no date is forever; no grant at all is the default.
        fullHistoryShared = grant.hasGrant && grant.from == nil
    }

    /// Set or revise the goal your coach reads.
    ///
    /// This is what a human coach gets INSTEAD of your AI-chat notes. Those
    /// notes are things you told a machine in passing — injuries, pain levels,
    /// "back's sore again" — and nobody experiences saying that to an assistant
    /// as telling their trainer. So they're no longer sent at all, and what
    /// replaces them is one sentence you wrote on purpose and pressed a button
    /// to share (operator 2026-07-30).
    ///
    /// Dated when saved, so a coach reads "as of the 12th" rather than an
    /// ageless statement they can't tell is stale.
    @ViewBuilder var goalRow: some View {
        if editingGoal {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT YOU'RE WORKING TOWARD").sectionHeading()
                // Skip Fuse has neither `TextField(_:text:axis:)` nor the
                // `lineLimit(2...4)` range overload — both fail the Android
                // compile, so the multiline affordance is iOS-only and Android
                // gets a single-line field rather than nothing.
                #if os(Android)
                TextField("e.g. add 20 lbs to my deadlift by December", text: $goalDraft)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                #else
                TextField("e.g. add 20 lbs to my deadlift by December, without aggravating my shoulder",
                          text: $goalDraft, axis: .vertical)
                    .font(.caption)
                    .lineLimit(4)
                    .textFieldStyle(.roundedBorder)
                #endif
                Text("Only this — and what you share above — reaches @\(coach.username). Your AI-coach chats never do.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        let trimmed = goalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Preferences.sharedGoalStatement = trimmed.isEmpty ? nil : trimmed
                        Preferences.sharedGoalDate = DateFormatters.dateOnly.string(from: Date())
                        editingGoal = false
                        // Push straight away — a goal that reaches the coach on
                        // some later trigger is a goal you can't tell you shared.
                        Task { await BriefingRepush.afterNotesChanged() }
                    } label: {
                        Text("Share with coach").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)

                    Button {
                        goalDraft = Preferences.sharedGoalStatement ?? ""
                        editingGoal = false
                    } label: { Text("Cancel").font(.caption) }
                    .buttonStyle(.bordered).tint(Theme.textSecondary)
                }
            }
        } else {
            Button { editingGoal = true } label: {
                HStack(spacing: 6) {
                    #if os(Android)
                    // "target" is deliberately unmapped (Symbols.swift) — draw
                    // the rings, matching the Today tab icon (#1233).
                    TargetShape().fill(Theme.accent).frame(width: 12, height: 12)
                    #else
                    Image(systemName: sym("target"))
                        .font(.caption2).foregroundStyle(Theme.accent)
                    #endif
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Preferences.sharedGoalStatement == nil
                             ? "Set a goal to share" : "Revise your goal")
                            .font(.caption).foregroundStyle(Theme.textPrimary)
                        Text(Preferences.sharedGoalStatement
                             ?? "Your coach sees what you're working toward — not your AI chats")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: sym("chevron.right"))
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

}
