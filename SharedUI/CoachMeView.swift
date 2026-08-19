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
    /// Start this session NOW. The host dismisses the coach and opens the
    /// active-workout sheet — a nested sheet from in here races the dismiss
    /// (the lesson `previewFollowUp` in WorkoutView already encodes).
    var onStart: (WorkoutTemplate) -> Void = { _ in }
    @Environment(\.dismiss) var dismiss

    @State var notes = CoachNotes.load()
    @State var messages: [Message] = []
    @State var draft = ""
    @State var thinking = false
    @State var program: [WorkoutTemplate] = []
    @State var saving = false
    /// Chips for the question the LLM actually asked (#1158). While the cloud
    /// coach drives, the scripted intake's nextStep chips are WRONG whenever
    /// the model picks its own question order — so once a live turn lands,
    /// only the model's suggestions render (empty = free-text answer, no
    /// chips). The scripted chips remain the offline fallback.
    @State var llmSuggestions: [String] = []
    @State var llmDriving = false
    /// One session now, or a weekly split. Sticky once known: the model returns
    /// null on turns where it's mid-question, and re-deciding every turn flipped
    /// a today-session back into a program mid-conversation.
    @State var ask: CoachProgramBuilder.Ask?
    /// A muscle or movement they named for today ("lats", "push", "legs").
    @State var focus: String?

    /// A single session can be STARTED; a weekly split can only be filed.
    var isSingleSession: Bool { ask == .today && program.count == 1 }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let fromCoach: Bool
        /// An anatomy card that belongs with this message, when the moment
        /// warranted one. Attached to the MESSAGE rather than kept as one
        /// floating card so it stays anchored to the thing it explains as the
        /// conversation scrolls on.
        var lesson: MuscleEducation.Lesson? = nil
    }

    /// Muscles already explained in this conversation. The anti-lecture guard —
    /// one muscle, one explanation, however many times it comes up.
    @State var taught: Set<String> = []
    /// The anatomy aside that belongs with the drafted plan.
    @State var sessionLesson: MuscleEducation.Lesson?

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

            ScrollViewReader { proxy in
                ScrollView {
                    // Android needs a LAZY stack here or nothing scrolls at all.
                    // SkipUI's ScrollViewProxy gets its action from whatever
                    // contributes `ScrollToIDPreferenceKey`, and only the lazy
                    // containers and List do (LazyVStack.swift:97, List.swift:249)
                    // — under a plain VStack the proxy reduces to the default
                    // no-op, so every `scrollTo` here was silently discarded and
                    // the conversation stayed pinned at offset 0: six turns in,
                    // the newest reply rendered below the fold while the iPhone
                    // at the identical state had scrolled it into view (#1197).
                    // Same shape AIChatView:83 already ships (#1066). iOS keeps
                    // its eager VStack, so the iPhone is bit-identical.
                    #if os(Android)
                    LazyVStack(alignment: .leading, spacing: 10) { conversation }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    #else
                    VStack(alignment: .leading, spacing: 10) { conversation }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    #endif
                }
                // Keep the newest turn in view — tapping a chip used to leave
                // the conversation parked above the fold (operator 2026-07-29).
                // `anchor:` is ignored on Fuse by design (ScrollView.swift:163);
                // reaching the sentinel at all is what matters there.
                .onChange(of: messages.count) { _, _ in
                    proxy.scrollTo("coachBottom", anchor: .bottom)
                }
                .onChange(of: thinking) { _, _ in
                    proxy.scrollTo("coachBottom", anchor: .bottom)
                }
                .onChange(of: program.count) { _, _ in
                    proxy.scrollTo("coachBottom", anchor: .bottom)
                }
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

    /// The conversation itself, so the two platforms' scroll containers can
    /// differ without the content being written twice.
    @ViewBuilder
    var conversation: some View {
        ForEach(messages) { message in
            bubble(message)
        }
        if thinking {
            Text("…").font(.title3).foregroundStyle(Theme.textTertiary)
        }
        if !program.isEmpty {
            draftCard
        }
        Color.clear.frame(height: 1).id("coachBottom")
    }

    @ViewBuilder
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
        if let lesson = message.lesson {
            lessonCard(lesson)
        }
    }

    /// The anatomy card: the figure with ONE muscle lit, and what it does.
    ///
    /// Inline in the conversation rather than a sheet — it's an aside, not a
    /// destination, and something you have to tap and dismiss is a lecture. One
    /// side of the body only: the side that shows the muscle (`preferredSide`),
    /// because a back view with nothing highlighted on it is noise.
    func lessonCard(_ lesson: MuscleEducation.Lesson) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MuscleBodyView(side: lesson.side,
                           primarySlugs: Set(lesson.slugs),
                           fitBox: CGSize(width: 56, height: 108))
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.headline)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // The Latin trails, for whoever wants it — it never leads.
                Text(lesson.info.latinName)
                    .font(.caption2.italic())
                    .foregroundStyle(Theme.textTertiary)
                Text(lesson.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.cardBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .padding(.trailing, 40)
    }

    /// Tappable answers for the question just asked. Never the only path —
    /// "fit and mobile" is a better answer than any chip, so the text field
    /// stays live. LLM-provided while the cloud coach drives (#1158); the
    /// scripted step's chips only when offline.
    var currentSuggestions: [String] {
        llmDriving ? llmSuggestions : (notes.intake.nextStep?.suggestions ?? [])
    }

    var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(currentSuggestions, id: \.self) { suggestion in
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
                #if os(Android)
                // sym("arrow.up.circle.fill") used to return the paperplane —
                // a different object from iOS's circled up-arrow (#1210).
                SendUpShape().fill(Theme.accent).frame(width: 26, height: 26)
                #else
                Image(systemName: sym("arrow.up.circle.fill"))
                    .font(.title2).foregroundStyle(Theme.accent)
                #endif
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
            Text(isSingleSession ? "Here's your session" : "Here's the plan")
                .font(.subheadline.weight(.semibold))
            // The coach explains itself — why this shape, from the intake.
            Text(isSingleSession
                 ? CoachProgramBuilder.todayRationale(
                     for: notes.intake, focus: focus,
                     recentBodyParts: Array(ExerciseService.recentBodyParts()))
                 : CoachProgramBuilder.rationale(for: notes.intake))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            ForEach(program, id: \.name) { template in
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    let coverage = CoachProgramBuilder.muscleCoverage(of: template)
                    if !coverage.isEmpty {
                        Text(coverage.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(template.exercises.indices, id: \.self) { i in
                        let exercise = template.exercises[i]
                        Text("\(exercise.isWarmup ? "Warmup · " : "")\(exercise.name) — \(exercise.sets)×\(exercise.notes ?? "")")
                            .font(.caption2)
                            .foregroundStyle(exercise.isWarmup ? Theme.textTertiary : Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let sessionLesson {
                lessonCard(sessionLesson)
            }

            Text("Want it different? Say so — \u{201C}swap the deadlift\u{201D}, \u{201C}make it harder\u{201D}, \u{201C}add mobility\u{201D}.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)

            // One session someone asked for RIGHT NOW leads with Start —
            // filing it is the secondary thing they might also want. A weekly
            // program has nothing to start, so it keeps Save as the only action.
            if isSingleSession, let session = program.first {
                Button {
                    dismiss()
                    onStart(session)
                } label: {
                    Text("Start workout")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { Task { await save() } } label: {
                    Text(saving ? "Saving…" : "Save as template")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(saving)
            } else {
                Button { Task { await save() } } label: {
                    Text(saving ? "Saving…" : "Save \(program.count) template\(program.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
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
        // What they typed decides the ask when the model hasn't. Sticky, and
        // never downgraded from an explicit model call.
        if ask == nil { ask = CoachProgramBuilder.Ask.detect(from: trimmed) }

        if let turn = await NebiusCoach.turn(history: history,
                                             known: notes.intake,
                                             briefing: notes.briefing()) {
            notes.intake.merge(turn.learned)
            notes.intake.noteInjuryTalk(inCoachReply: turn.reply)
            if let note = turn.note { notes.record(note, kind: .moment) }
            notes.save()
            messages.append(Message(text: turn.reply, fromCoach: true,
                                    lesson: lessonFor(trimmed)))
            llmDriving = true
            llmSuggestions = turn.suggestions
            if let modelAsk = turn.ask { ask = modelAsk }
            if let named = turn.focus, !named.isEmpty { focus = named }
            // #1158: a reply that asks a question must not answer itself with
            // a plan in the same breath — the draft waits for the next turn.
            let stillAsking = turn.reply.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
            // A today-session needs only how long they have — gating it on
            // `canDraft` (days/week, equipment, injuries asked) is the weekly
            // interview, and running it on someone standing in the gym is the
            // complaint this whole path exists to fix.
            let ready = turn.readyToDraft
                || (ask == .today ? notes.intake.canDraftToday : notes.intake.canDraft)
            if ready && !stillAsking { redraft() }
        } else {
            // Offline: the scripted intake still advances the conversation.
            llmDriving = false
            if ask == .today {
                // A today-session asks ONE thing, not the weekly interview.
                if notes.intake.sessionMinutes == nil,
                   let minutes = Int(trimmed.filter(\.isNumber).prefix(2)), minutes > 0 {
                    notes.intake.sessionMinutes = minutes
                }
                notes.save()
                if notes.intake.canDraftToday {
                    redraft()
                } else {
                    messages.append(Message(text: CoachIntake.Step.duration.question,
                                            fromCoach: true, lesson: lessonFor(trimmed)))
                }
            } else {
                applyOffline(trimmed)
                if let step = notes.intake.nextStep {
                    messages.append(Message(text: step.question, fromCoach: true,
                                            lesson: lessonFor(trimmed)))
                } else if notes.intake.canDraft {
                    redraft()
                }
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

    /// An anatomy aside for what the user just said, if the moment warrants one.
    ///
    /// Records the muscle so it's never explained twice — the guard that keeps
    /// this an aside rather than a lecture.
    func lessonFor(_ text: String) -> MuscleEducation.Lesson? {
        guard let lesson = MuscleEducation.lesson(forUserText: text, alreadyTaught: taught)
        else { return nil }
        taught.insert(lesson.muscle)
        return lesson
    }

    func redraft() {
        // ONE session when that's what was asked for. The old path only ever
        // produced a week of templates, so "I just want one exercise" ended at
        // a filing cabinet instead of a workout you could start.
        if ask == .today {
            program = [CoachProgramBuilder.todaySession(
                from: notes.intake,
                focus: focus,
                recentBodyParts: Array(ExerciseService.recentBodyParts()))]
        } else {
            program = CoachProgramBuilder.draft(from: notes.intake)
        }
        // "That's why we're picking these" — the draft explains the muscle it
        // leads with, once, and only if it hasn't already come up.
        if let session = program.first,
           let lesson = MuscleEducation.lesson(forSession: session, alreadyTaught: taught) {
            taught.insert(lesson.muscle)
            sessionLesson = lesson
        }
    }

    func save() async {
        saving = true
        defer { saving = false }
        for template in program {
            var copy = template
            try? WorkoutService.saveTemplate(&copy)
        }
        notes.recordProgram(program.map(\.name))
        // The human coach reads the CURRENT picture — a new program is exactly
        // what they'd want to know about, so re-push the briefing now rather
        // than waiting for the client to revisit the sharing toggle.
        Task { await BriefingRepush.afterNotesChanged() }
        onSaved()
        dismiss()
    }

    func reset() {
        notes = CoachNotes()
        notes.save()
        messages = []
        program = []
        // A fresh conversation gets to hear the anatomy again — leaving `taught`
        // populated would silence every lesson after the first Reset.
        taught = []
        sessionLesson = nil
        ask = nil
        focus = nil
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
