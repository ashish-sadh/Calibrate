import SwiftUI
import DriftCore

/// A coach's view of ONE client — what makes "coach" more than "friend":
/// see how the client is doing (their shared workouts) and **assign** them a
/// workout from your own templates, plus message them. Single-source SharedUI.
struct ClientDetailView: View {
    let client: SharedProfile

    @State var sessions: [LiveWorkoutDTO] = []
    @State var templates: [WorkoutTemplate] = []
    @State var loading = true
    @State var assignedIDs: Set<Int64> = []
    @State var assigningID: Int64?
    @State var error: String?
    @State var briefing: ClientBriefing?
    @State var brief: CoachClientBrief.Brief?
    // Coach-authored notes — the coach's own dated log about this client,
    // which the client also reads (migration 0006).
    @State var myNotes: [CoachAuthoredNote] = []
    @State var noteDraft = ""
    @State var savingNote = false
    // Inline template building for this client.
    @State var showingBuilder = false
    /// Built but not yet routed — the coach still has to say whether it also
    /// belongs in their own library.
    @State var pendingBuild: WorkoutTemplate?
    @State var assigningBuild = false
    /// The template the coach tapped to preview before assigning (#4). Tapping a
    /// row's name opened nothing before — only the Assign button did anything, so
    /// the coach couldn't see what was inside a template without assigning it.
    @State var previewingTemplate: WorkoutTemplate?

    private var svc: SharingService { .shared }

    /// What the client chose to share, if anything. The coach sees only what
    /// was granted — and sees plainly when nothing was, rather than an empty
    /// card that reads like a client with no data.
    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What \(client.username) shares").font(.subheadline.weight(.semibold))

            // The AI read sits above the raw numbers: a coach opening a client
            // wants the story first and the evidence underneath it.
            if let brief {
                Text(brief.headline)
                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
                ForEach(brief.watch, id: \.self) { item in
                    Text("• \(item)").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if !brief.ask.isEmpty {
                    Text("Worth asking").font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary).padding(.top, 2)
                    ForEach(brief.ask, id: \.self) { question in
                        Text("• \(question)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Divider().overlay(Theme.separatorFaint).padding(.vertical, 2)
            }

            // The SAME component the client sees as their preview (#1156
            // mirror view) — what-you-think-you-share can't drift from
            // what-they-see when it's one view.
            CoachBriefingView(
                briefing: briefing ?? ClientBriefing(
                    clientID: client.id, summary: "", notes: [], metrics: .init()),
                emptyText: "Nothing shared beyond workouts. \(client.username) can share average sleep, nutrition, body composition or their training history from their Friends screen.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                briefingCard
                coachNotesCard
                messageCard
                recentWorkoutsCard
                assignCard
                if let error {
                    Text(error).font(.caption).foregroundStyle(Theme.surplus)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 110)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("@\(client.username)")
        #if !os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingBuilder) {
            // onBuild (not the default save path): nothing is persisted until
            // the coach picks where it goes.
            CreateTemplateView(
                onBuild: { built in pendingBuild = built },
                saveButtonTitle: "Done — choose where to send it",
                onSave: {})
        }
        .task { await load() }
    }

    /// The coach's OWN dated notes about this client — the counterpart to the
    /// AI's notes, and clearly separated from them (operator 2026-07-29: the
    /// AI notes read as if the trainer had written them).
    ///
    /// The client always reads these, and the composer says so before you
    /// type: a note about someone they can't see is a file kept on a person.
    private var coachNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR NOTES").sectionHeading()
            Text("Dated, and @\(client.username) can read these.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)

            // One TextField per ViewBuilder scope on Fuse — this card has
            // exactly one, and the extracted composer keeps it that way.
            CoachNoteComposer(draft: $noteDraft, saving: savingNote) {
                await saveNote()
            }

            if myNotes.isEmpty {
                Text("No notes yet. Write what you'd want to remember before their next session.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(myNotes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(note.dateOnly)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)
                            Text("YOU")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Button {
                                Task { await deleteNote(note) }
                            } label: {
                                Text("Delete")
                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(note.text)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if note.id != myNotes.last?.id {
                        Divider().overlay(Theme.separatorFaint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func saveNote() async {
        let text = noteDraft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        savingNote = true
        defer { savingNote = false }
        do {
            try await svc.addCoachNote(clientID: client.id, text: text)
            noteDraft = ""
            myNotes = (try? await svc.coachNotes(
                clientID: client.id,
                coachID: svc.currentSession?.userID ?? "")) ?? myNotes
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:))
                ?? error.localizedDescription
        }
    }

    private func deleteNote(_ note: CoachAuthoredNote) async {
        do {
            try await svc.deleteCoachNote(note.id)
            myNotes.removeAll { $0.id == note.id }
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:))
                ?? error.localizedDescription
        }
    }

    /// Where does the workout you just built belong? A one-off for this client,
    /// or a template you'll reuse with others. Asked inline rather than in a
    /// dialog (Fuse dialogs carry keyboard/focus traps, #1077), and asked at
    /// all because silently filling a coach's library with per-client one-offs
    /// is how a template list becomes unusable.
    private func pendingBuildCard(_ built: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\"\(built.name)\" · \(built.exercises.count) exercises")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)

            if assigningBuild {
                ProgressView()
            } else {
                Button { Task { await sendBuild(built, keepInLibrary: false) } } label: {
                    buildChoice("Send to @\(client.username) only",
                                "Not added to your templates",
                                tint: Theme.accent, filled: true)
                }
                .buttonStyle(.plain)

                Button { Task { await sendBuild(built, keepInLibrary: true) } } label: {
                    buildChoice("Send and save to my library",
                                "Reuse it with other clients",
                                tint: Theme.ink, filled: false)
                }
                .buttonStyle(.plain)

                Button { pendingBuild = nil } label: {
                    Text("Discard").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func buildChoice(_ title: String, _ subtitle: String,
                             tint: Color, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(filled ? .white : tint)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(filled ? Color.white.opacity(0.85) : Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(filled ? tint : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay {
            if !filled {
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    /// Share the built template, optionally keeping a copy. Sharing only needs
    /// the name + exercise JSON, so a one-off never touches the local library.
    private func sendBuild(_ built: WorkoutTemplate, keepInLibrary: Bool) async {
        assigningBuild = true
        defer { assigningBuild = false }
        do {
            if keepInLibrary {
                var copy = built
                try WorkoutService.saveTemplate(&copy)
                templates = (try? WorkoutService.fetchTemplates()) ?? templates
            }
            try await svc.shareTemplate(built, to: client.id, role: .trainer)
            pendingBuild = nil
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:))
                ?? error.localizedDescription
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(client.username.first.map { String($0).uppercased() } ?? "?")
                .font(.title3.weight(.bold)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(client.username)").font(.title3.weight(.bold))
                Text("Your client\(lastActiveSubtitle)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var lastActiveSubtitle: String {
        guard let d = sessions.compactMap(\.activityDate).max() else { return "" }
        return " · last active \(RelativeTime.string(from: d))"
    }

    private var messageCard: some View {
        NavigationLink { ChatView(peer: client, relationship: "client") } label: {
            HStack(spacing: 10) {
                Image(systemName: sym("bubble.left.fill")).foregroundStyle(Theme.chartTrend)
                Text("Message @\(client.username)").font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: sym("chevron.right")).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var recentWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW THEY'RE DOING").sectionHeading()
            if loading {
                ProgressView()
            } else if sessions.isEmpty {
                Text("No workouts shared with you yet. When @\(client.username) finishes a workout and shares it, it'll show up here.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(sessions.prefix(10)) { s in
                    NavigationLink {
                        ClientSessionDetailView(session: s, fromUsername: "@\(client.username)")
                    } label: {
                        HStack(spacing: 10) {
                            #if os(Android)
                            // Pinned skip-ui 1.58 has no chart glyph (sym's
                            // chart.bar.xaxis target is 1.59+) — drawn bars
                            // instead (ChartGlyph.swift).
                            BarChartShape().fill(Theme.accent).frame(width: 15, height: 15)
                            #else
                            Image(systemName: sym("chart.line.uptrend.xyaxis"))
                                .font(.subheadline).foregroundStyle(Theme.accent)
                            #endif
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.templateName ?? "Workout").font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(s.status == .live ? "training now · live 🔴"
                                     : (s.activityDate.map { RelativeTime.string(from: $0) } ?? "completed"))
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: sym("chevron.right")).font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle()).padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    if s.id != sessions.prefix(10).last?.id { Divider().overlay(Theme.separatorFaint) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var assignCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASSIGN A WORKOUT").sectionHeading()
            Text("Send @\(client.username) one of your templates, or build them something new. They accept it into their library and can run it.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)

            // Building for a client used to mean leaving this page for the
            // Workout tab and coming back (operator 2026-07-29: "it's not
            // super obvious the coach needs to go to the workout tab"). The
            // builder is inline now, and the coach chooses whether it also
            // lands in their own library.
            Button { showingBuilder = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: sym("plus.circle.fill"))
                        .font(.subheadline).foregroundStyle(Theme.accent)
                    Text("Build a new workout for @\(client.username)")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let built = pendingBuild {
                pendingBuildCard(built)
            }

            if templates.isEmpty {
                Text("You have no saved templates yet — build one above, or create them on the Workout tab.")
                    .font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            } else {
                ForEach(templates) { t in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.subheadline.weight(.medium))
                            Text("\(t.exercises.count) exercises").font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if let id = t.id, assignedIDs.contains(id) {
                            Label("Assigned", systemImage: sym("checkmark"))
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.deficit)
                        } else if assigningID == t.id {
                            ProgressView()
                        } else {
                            Button { Task { await assign(t) } } label: {
                                Text("Assign").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    if t.id != templates.last?.id { Divider().overlay(Theme.separatorFaint) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func load() async {
        loading = true
        templates = (try? WorkoutService.fetchTemplates()) ?? []
        let all = (try? await svc.clientSessions()) ?? []
        sessions = all.filter { $0.clientId == client.id }
        briefing = try? await svc.fetchBriefing(for: client.id)
        myNotes = (try? await svc.coachNotes(
            clientID: client.id, coachID: svc.currentSession?.userID ?? "")) ?? []
        loading = false
        // Opening the page IS seeing it — clear this client's "N new" badge
        // once the sessions are actually on screen, not before.
        SeenMarks.markSessionsSeen(client: client.id)

        // After the card is already on screen — the coach shouldn't wait on a
        // cloud round-trip to see the workouts they came for.
        if let briefing, !briefing.isEmpty {
            brief = await CoachClientBrief.generate(for: briefing, username: client.username)
                ?? CoachClientBrief.offline(for: briefing)
        }
    }

    private func assign(_ template: WorkoutTemplate) async {
        guard let id = template.id else { return }
        assigningID = id; error = nil
        do {
            try await svc.shareTemplate(template, to: client.id, role: .trainer,
                                        note: "Assigned by your coach")
            assignedIDs.insert(id)
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:)) ?? error.localizedDescription
        }
        assigningID = nil
    }
}

/// The coach's note field, extracted into its own View for two reasons: Fuse
/// binds only the FIRST TextField per ViewBuilder scope, and keeping the draft
/// binding here means typing doesn't re-evaluate the whole client page.
struct CoachNoteComposer: View {
    @Binding var draft: String
    let saving: Bool
    let onSave: () async -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("e.g. Knee felt better with the tempo squats", text: $draft)
                .font(.caption)
                #if !os(Android)
                .textFieldStyle(.roundedBorder)
                #endif
            Button {
                Task { await onSave() }
            } label: {
                if saving {
                    ProgressView()
                } else {
                    Text("Add").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(saving || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
