import SwiftUI
import DriftCore

/// Coach Me — a conversation that ends in a program, replacing the old button
/// that threw a generated session at you with no questions asked.
///
/// Single-source for both apps. The coach talks (Nebius), remembers
/// (`CoachNotes`), drafts (`CoachProgramBuilder`), and only then saves — you
/// can refine before anything lands in your templates.
///
/// Offline it falls back to the scripted `CoachIntake.Step` questions, so the
/// feature still works on a plane; it just stops sounding like a person.
struct CoachMeView: View {
    /// Called after templates are saved so the host can refresh its list.
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) var dismiss

    @State var notes = CoachNotes.load()
    @State var messages: [Message] = []
    @State var draft = ""
    @State var thinking = false
    @State var program: [WorkoutTemplate] = []
    @State var saving = false

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let fromCoach: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            // In-content chrome (#1089): a nav bar in a sheet reserves a dead
            // band on Android.
            HStack {
                Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                Spacer()
                Text("Coach").font(.headline)
                Spacer()
                Button("Reset") { reset() }
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        bubble(message)
                    }
                    if thinking {
                        Text("…").font(.title3).foregroundStyle(Theme.textTertiary)
                    }
                    if !program.isEmpty {
                        draftCard
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }

            if program.isEmpty {
                suggestionRow
            }
            inputBar
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await start() }
    }

    // MARK: - Chat

    func bubble(_ message: Message) -> some View {
        HStack {
            if !message.fromCoach { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.fromCoach ? Theme.textPrimary : .white)
                .padding(10)
                .background(message.fromCoach ? Theme.cardBackgroundElevated : Theme.accent,
                            in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            if message.fromCoach { Spacer(minLength: 40) }
        }
    }

    /// Tappable answers for the step we're on. Never the only path — "fit and
    /// mobile" is a better answer than any chip, so the text field stays live.
    var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(notes.intake.nextStep?.suggestions ?? [], id: \.self) { suggestion in
                    Button { Task { await send(suggestion) } } label: {
                        Text(suggestion)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.cardBackgroundElevated, in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
    }

    var inputBar: some View {
        HStack(spacing: 8) {
            CoachDraftField(draft: $draft)
            Button {
                let text = draft
                draft = ""
                Task { await send(text) }
            } label: {
                Image(systemName: sym("arrow.up.circle.fill"))
                    .font(.title2).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Draft

    var draftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Here's the plan").font(.subheadline.weight(.semibold))
            ForEach(program, id: \.name) { template in
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    ForEach(template.exercises.indices, id: \.self) { i in
                        let exercise = template.exercises[i]
                        Text("\(exercise.isWarmup ? "Warmup · " : "")\(exercise.name) — \(exercise.sets)×\(exercise.notes ?? "")")
                            .font(.caption2)
                            .foregroundStyle(exercise.isWarmup ? Theme.textTertiary : Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Text("Want it different? Say so — \u{201C}swap the deadlift\u{201D}, \u{201C}make it harder\u{201D}, \u{201C}add mobility\u{201D}.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)

            Button { Task { await save() } } label: {
                Text(saving ? "Saving…" : "Save \(program.count) template\(program.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Conversation

    func start() async {
        guard messages.isEmpty else { return }
        // A returning user gets picked up mid-thought, not re-interviewed.
        if let returning = notes.returningGreeting {
            messages.append(Message(text: returning, fromCoach: true))
        } else if notes.intake.canDraft {
            messages.append(Message(
                text: "Welcome back. I've still got: \(notes.intake.summary). Want the same again, or shall we change something?",
                fromCoach: true))
        } else {
            messages.append(Message(
                text: "Let's build you something. \(CoachIntake.Step.schedule.question)",
                fromCoach: true))
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        messages.append(Message(text: trimmed, fromCoach: false))
        thinking = true
        defer { thinking = false }

        // A refine request once a draft exists re-drafts rather than restarting
        // intake — "make it harder" is not a new interview.
        let history = messages.map { "\($0.fromCoach ? "coach" : "user"): \($0.text)" }

        if let turn = await NebiusCoach.turn(history: history,
                                             known: notes.intake,
                                             briefing: notes.briefing()) {
            notes.intake.merge(turn.learned)
            if let note = turn.note { notes.record(note, kind: .moment) }
            notes.save()
            messages.append(Message(text: turn.reply, fromCoach: true))
            if turn.readyToDraft || notes.intake.canDraft { redraft() }
        } else {
            // Offline: the scripted intake still advances the conversation.
            applyOffline(trimmed)
            if let step = notes.intake.nextStep {
                messages.append(Message(text: step.question, fromCoach: true))
            } else if notes.intake.canDraft {
                redraft()
            }
        }
    }

    /// Cloud-free slot filling so the feature degrades instead of dying. Only
    /// the unambiguous shapes — a number for the step we asked, or free text
    /// for the free-text slots.
    func applyOffline(_ text: String) {
        guard let step = notes.intake.nextStep else { return }
        let digits = Int(text.filter(\.isNumber).prefix(2))
        switch step {
        case .schedule:  notes.intake.daysPerWeek = digits
        case .goal:      notes.intake.goal = text
        case .duration:  notes.intake.sessionMinutes = digits
        case .equipment: notes.intake.equipment = text
        case .style:     notes.intake.usesBarbell = !text.lowercased().contains("machine")
        case .familiar:
            notes.intake.familiarExercises = text
                .components(separatedBy: CharacterSet(charactersIn: ",/"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case .injuries:
            notes.intake.askedInjuries = true
            let lowered = text.lowercased()
            if !lowered.contains("no") && !lowered.contains("nothing") {
                notes.intake.problemAreas = [text]
            }
        case .pain:      notes.intake.painLevel = digits.map { min(max($0, 0), 10) }
        case .requests:
            notes.intake.askedRequests = true
            if !text.lowercased().contains("nothing") { notes.intake.requests = [text] }
        }
        notes.save()
    }

    func redraft() {
        program = CoachProgramBuilder.draft(from: notes.intake)
    }

    func save() async {
        saving = true
        defer { saving = false }
        for template in program {
            var copy = template
            try? WorkoutService.saveTemplate(&copy)
        }
        notes.recordProgram(program.map(\.name))
        onSaved()
        dismiss()
    }

    func reset() {
        notes = CoachNotes()
        notes.save()
        messages = []
        program = []
        Task { await start() }
    }
}

/// Own View — Fuse binds only the FIRST TextField per ViewBuilder scope.
struct CoachDraftField: View {
    @Binding var draft: String
    var body: some View {
        TextField("Tell the coach…", text: $draft)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
    }
}
