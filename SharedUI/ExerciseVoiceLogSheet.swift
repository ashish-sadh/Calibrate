import SwiftUI
import DriftCore

/// Workout-tab parity with food's `VoiceLogSheet` (#868, epic #867). A
/// dedicated voice + typed-free-text exercise logger so a user standing on the
/// Workout tab can say or type "3×10 bench at 135, then a 5k run" without first
/// opening chat.
///
/// Pipeline (both input paths converge):
///   1. `.input` — a combined screen offering BOTH a mic affordance (tap to
///      record) AND a "type your sets" field. Defaulting to this screen (not
///      auto-recording) avoids a surprise mic prompt and keeps both options
///      visible.
///   2. Voice → `SpeechRecognitionService.shared` live transcript → Stop, or
///      typed text → Continue. Either way the text funnels through
///      `FoundationModelsExerciseExtractor.extract(text:)`.
///   3. `.confirming` — an EDITABLE multi-exercise card: one row per exercise
///      (name + sets × reps × weight, or duration), each row tweakable, before
///      `WorkoutService.saveVoiceLoggedWorkout` persists them.
///
/// Reuses the SAME `SpeechRecognitionService.shared` singleton `VoiceLogSheet`
/// owns — no second `AVAudioSession` owner / speech actor. V7 visual: light
/// theme, `Theme.ink` CTA, no pink (`Theme.accent`) default.
struct ExerciseVoiceLogSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var viewModel = ExerciseVoiceLogViewModel()
    /// Buffer for the typed-entry field. Kept as view state so a parse error →
    /// "Try again" returns the user to the input screen with their text intact.
    @State var draft = ""
    /// Row whose name the user is resolving via the library picker. Identifiable
    /// wrapper so `.sheet(item:)` carries the target row id.
    @State var resolveTarget: ResolveTarget?

    struct ResolveTarget: Identifiable { let id: UUID }

    /// Called after a successful save so the Workout tab can reload its history.
    let onSaved: () -> Void

    init(onSaved: @escaping () -> Void = {}) {
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .input:
                inputView
            case .listening:
                #if DRIFT_IOS_APP
                listeningView
                #else
                // Unreachable off-iOS: startListening is a no-op without the
                // platform speech service, so the phase never becomes .listening.
                EmptyView()
                #endif
            case .parsing:
                parsingView
            case .confirming:
                confirmView
            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onDisappear { viewModel.cancel() }
        .sheet(item: $resolveTarget) { target in
            ExercisePickerView { name in
                viewModel.resolve(id: target.id, name: name)
            }
        }
    }

    // MARK: - Input (mic + typed text, both present)

    private var inputView: some View {
        VStack(spacing: 22) {
            Spacer()

            #if DRIFT_IOS_APP
            // Mic affordance — shared component, Theme.ink (no pink). Tapping
            // starts recording and flips to the listening screen. Off-iOS the
            // sheet is text-first until the Android SpeechRecognizer seam
            // lands (#1063).
            Button {
                viewModel.startListening()
            } label: {
                VStack(spacing: 12) {
                    VoiceMicButton(tint: Theme.ink)
                        .accessibilityIdentifier("exercise-voice-mic")
                    Text("Tap to speak your sets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record workout by voice")
            #else
            Text("Type your sets")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            #endif

            Text("e.g. \u{201C}3×10 bench at 135, then a 5k run\u{201D}")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            #if DRIFT_IOS_APP
            HStack(spacing: 10) {
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                Text("or type").font(.caption2).foregroundStyle(Theme.textTertiary)
                Rectangle().fill(Theme.separator).frame(height: 0.5)
            }
            .padding(.horizontal, 40)
            #endif

            InputDraftField(draft: $draft)
                .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(Theme.textPrimary)

                Button {
                    Task { await viewModel.submitTyped(draft) }
                } label: {
                    Label("Continue", systemImage: sym("arrow.forward.circle.fill"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("exercise-text-submit")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Listening

    #if DRIFT_IOS_APP
    private var listeningView: some View {
        VStack(spacing: 24) {
            Spacer()

            VoiceMicButton(tint: Theme.ink)
                .accessibilityIdentifier("exercise-voice-mic")

            Text("Listening…")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(viewModel.transcript.isEmpty
                 ? "\u{201C}3 sets of 10 bench press at 135, then a 5k run\u{201D} — speak naturally."
                 : "\u{201C}\(viewModel.transcript)\u{201D}")
                .font(.subheadline)
                .foregroundStyle(viewModel.transcript.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(minHeight: 60)
                .accessibilityIdentifier("exercise-voice-transcript")

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(Theme.textPrimary)

                Button {
                    viewModel.stopAndParse()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .disabled(viewModel.transcript.isEmpty)
                .accessibilityIdentifier("exercise-voice-stop")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
    #endif

    // MARK: - Parsing

    private var parsingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(Theme.ink)
            Text("Reading your workout…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Confirm (editable multi-exercise card)

    private var confirmView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Your session")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                // Balance the leading Cancel so the title stays centered.
                Button("Cancel") {}.opacity(0).disabled(true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let msg = viewModel.transientMessage {
                        Label(msg, systemImage: sym("exclamationmark.circle.fill"))
                            .font(.caption)
                            .foregroundStyle(Theme.fatYellow)
                            .padding(.horizontal, 16)
                    }

                    Text("Last heard: \u{201C}\(viewModel.transcript)\u{201D}")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        #if os(Android)
                        // skip-fuse-ui's binding-ForEach writes are dead — bind
                        // rows through the root @State by index instead.
                        ForEach(Array(viewModel.exercises.enumerated()), id: \.element.id) { pair in
                            if pair.offset < viewModel.exercises.count {
                                editableRow($viewModel.exercises[pair.offset])
                            }
                        }
                        #else
                        ForEach($viewModel.exercises) { $exercise in
                            editableRow($exercise)
                        }
                        #endif
                    }
                    .padding(.horizontal, 16)

                    // Keep the mic one tap away so logging set-by-set across a
                    // workout never means reopening the sheet.
                    Button {
                        viewModel.addMore()
                    } label: {
                        Label("Add another exercise", systemImage: addMoreIcon)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusControl)
                                #if os(Android)
                                .stroke(Theme.separator, lineWidth: 0.5)
                                #else
                                .strokeBorder(Theme.separator, lineWidth: 0.5)
                                #endif
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("exercise-voice-add-more")
                }
                .padding(.top, 8)
            }

            Button {
                viewModel.save()
                onSaved()
                dismiss()
            } label: {
                Label("Log \(viewModel.loggableCount) exercise\(viewModel.loggableCount == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .disabled(viewModel.loggableCount == 0)
            .padding(16)
            .accessibilityIdentifier("exercise-voice-confirm")
        }
    }

    /// One editable confirmation row. Strength shows sets × reps × weight;
    /// duration shows minutes. Neutral colors only — strength data is not
    /// goal-aligned/against, so no green/red treatment.
    private func editableRow(_ exercise: Binding<ExerciseVoiceLogViewModel.ExerciseDraft>) -> some View {
        VoiceLogExerciseRow(
            exercise: exercise,
            isNew: viewModel.recentlyAddedIDs.contains(exercise.wrappedValue.id),
            onRemove: { viewModel.remove(id: exercise.wrappedValue.id) },
            onResolve: { resolveTarget = ResolveTarget(id: exercise.wrappedValue.id) }
        )
    }

    /// iOS keeps the mic glyph; off-iOS the affordance re-opens typed entry, so
    /// it reads as "add", not "record".
    private var addMoreIcon: String {
        #if DRIFT_IOS_APP
        return "mic.fill"
        #else
        return sym("plus.circle")
        #endif
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Theme.FontSize.display1))
                .foregroundStyle(Theme.fatYellow)
            Text("Couldn't log that")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(Theme.textPrimary)
                Button {
                    viewModel.reset()
                } label: {
                    Label("Try again", systemImage: sym("arrow.clockwise"))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Field structs (one TextField per View scope)
//
// Same constraint as ActiveWorkoutView's SetCellField: skip-fuse-ui binds only
// the first TextField evaluated per ViewBuilder scope, so every field lives in
// its own struct. Identical render on iOS.

struct InputDraftField: View {
    @Binding var draft: String

    var body: some View {
        #if os(Android)
        // .stroke, not .strokeBorder: SkipSwiftUI declares two strokeBorder
        // overload families and the call is ambiguous; the half-linewidth
        // inset difference is sub-pixel at 0.5pt.
        // .plain or Material's OutlinedTextField draws its own border + blue
        // focus ring ON TOP of the overlay below — iOS has neither.
        TextField("3x10 bench at 135", text: $draft)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .stroke(Theme.separator, lineWidth: 0.5)
            )
            .accessibilityIdentifier("exercise-text-field")
        #else
        TextField("3x10 bench at 135", text: $draft, axis: .vertical)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1...4)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .accessibilityIdentifier("exercise-text-field")
        #endif
    }
}

struct VoiceLogExerciseRow: View {
    @Binding var exercise: ExerciseVoiceLogViewModel.ExerciseDraft
    let isNew: Bool
    let onRemove: () -> Void
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Exercise", text: $exercise.name)
                    #if os(Android)
                    // iOS renders this borderless; Material would box the name.
                    .textFieldStyle(.plain)
                    #endif
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("exercise-row-name")
                Spacer()
                Button(action: onRemove) {
                    #if os(Android)
                    // skip-ui maps only bare "xmark" (Icons.Outlined.Clear) — no
                    // circle-fill variant — so draw iOS's filled disc ourselves.
                    ZStack {
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 20, height: 20)
                        Image(systemName: sym("xmark"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.cardBackground)
                    }
                    #else
                    Image(systemName: sym("xmark.circle.fill"))
                        .font(.body)
                        .foregroundStyle(Theme.textTertiary)
                    #endif
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove exercise")
            }

            // Unmatched names didn't resolve to the library — let the user pick
            // the real exercise instead of logging a garbled/guessed name.
            if !exercise.matched && !exercise.isDuration {
                Button(action: onResolve) {
                    Label("Not in library — tap to pick", systemImage: "magnifyingglass")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.fatYellow)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exercise-row-resolve")
            }

            if exercise.isDuration {
                HStack(spacing: 10) {
                    VoiceLogNumberField(label: "Min", text: $exercise.durationMinutes)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    VoiceLogNumberField(label: "Sets", text: $exercise.sets)
                    Text("×").font(.caption).foregroundStyle(Theme.textTertiary)
                    VoiceLogNumberField(label: "Reps", text: $exercise.reps)
                    Text("@").font(.caption).foregroundStyle(Theme.textTertiary)
                    VoiceLogNumberField(label: "Lbs", text: $exercise.weight)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl)
            #if os(Android)
            .stroke(isNew ? Theme.ink : Theme.separator, lineWidth: isNew ? 1.5 : 0.5)
            #else
            .strokeBorder(isNew ? Theme.ink : Theme.separator, lineWidth: isNew ? 1.5 : 0.5)
            #endif
        )
        .animation(.easeOut(duration: 0.25), value: isNew)
    }
}

struct VoiceLogNumberField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 3) {
            TextField("—", text: $text)
                #if os(Android)
                // The rounded fill below IS the field on iOS — no outline.
                .textFieldStyle(.plain)
                #endif
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 54)
                .padding(.vertical, 7)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: Theme.FontSize.nano, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class ExerciseVoiceLogViewModel {
    enum Phase: Equatable {
        case input
        case listening
        case parsing
        case confirming
        case error(String)
    }

    /// Editable confirmation row. Numerics are held as strings for direct
    /// `TextField` binding; converted back to `WorkoutService.VoiceLoggedExercise`
    /// (parsing the strings) on save.
    struct ExerciseDraft: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var isDuration: Bool
        /// True when `name` resolved to a catalog entry (or is a duration entry
        /// where the strength catalog doesn't apply). False = spoken name didn't
        /// match the library, so the UI prompts the user to confirm/fix it.
        var matched: Bool
        var sets: String
        var reps: String
        var weight: String
        var durationMinutes: String
    }

    var phase: Phase = .input
    var transcript: String = ""
    /// The running session — utterances APPEND here so a user can log set by set
    /// across the workout, then commit the whole list with one Approve.
    var exercises: [ExerciseDraft] = []
    /// IDs added by the most recent utterance, highlighted briefly so the user
    /// sees exactly what their last words contributed.
    var recentlyAddedIDs: Set<UUID> = []
    /// Inline, non-fatal notice (e.g. a follow-up utterance that didn't parse)
    /// shown above the session list without wiping what's already there.
    var transientMessage: String?

    #if DRIFT_IOS_APP
    private let speech = SpeechRecognitionService.shared
    #endif

    /// Number of rows that would actually persist (blank-named rows are skipped
    /// by `buildVoiceLogSets`), used for the confirm button label + enablement.
    var loggableCount: Int {
        exercises.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    func startListening() {
        #if DRIFT_IOS_APP
        transcript = ""
        phase = .listening
        speech.startRecording(
            onTranscript: { [weak self] partial in
                self?.transcript = partial
            },
            onDone: { [weak self] final in
                Task { await self?.parse(final) }
            }
        )
        #endif
    }

    /// Typed-text counterpart to the speech `onDone` callback: routes the field
    /// through the identical `parse(_:)` pipeline, so a multi-exercise utterance
    /// yields the same multi-row confirmation card the voice path produces.
    func submitTyped(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript = trimmed
        await parse(trimmed)
    }

    func stopAndParse() {
        #if DRIFT_IOS_APP
        // `gracefulStop` flushes the final partial transcription before firing
        // the `onDone` callback, which then drives `parse(_:)`.
        speech.gracefulStop()
        #endif
    }

    func cancel() {
        #if DRIFT_IOS_APP
        // `forceStop` tears down the audio engine without invoking `onDone` —
        // safer than leaving a half-open mic if the sheet is dismissed mid-record.
        speech.forceStop()
        #endif
    }

    /// Continue an existing session: re-open the mic to add more exercises
    /// without discarding what's already been logged. Off-iOS (no speech
    /// service) it returns to the typed-entry screen instead.
    func addMore() {
        #if DRIFT_IOS_APP
        startListening()
        #else
        phase = .input
        #endif
    }

    /// Reset to the input screen (used by error "Try again"). Clears the session.
    func reset() {
        transcript = ""
        exercises = []
        recentlyAddedIDs = []
        transientMessage = nil
        phase = .input
    }

    func remove(id: UUID) {
        exercises.removeAll { $0.id == id }
        recentlyAddedIDs.remove(id)
    }

    /// Replace a row's name with a user-picked catalog entry (resolves an
    /// unmatched row from the library picker).
    func resolve(id: UUID, name: String) {
        guard let idx = exercises.firstIndex(where: { $0.id == id }) else { return }
        exercises[idx].name = name
        exercises[idx].matched = true
    }

    private func parse(_ text: String) async {
        guard !text.isEmpty else {
            failParse("Didn't catch that. Make sure microphone permission is granted.")
            return
        }
        phase = .parsing

        // Cloud-first (#969): the on-device Apple Foundation Model
        // pattern-completes a single utterance into a whole stereotypical workout
        // ("3 sets of back extensions" → squat/deadlift/curl/…), silently logging
        // exercises the user never said. The bigger Nebius cloud model extracts
        // only what was stated. Falls through to on-device FM when the cloud is
        // unconfigured / unreachable / returns nothing.
        // Unconditional: the coach cloud is the top rung of the AI ladder on
        // BOTH platforms (#1064). Android used to skip straight to the local
        // regex, which meant the same utterance got a worse answer there —
        // no kg→lbs conversion, no cardio/duration split, no Hinglish.
        if let entries = await NebiusExerciseLogger.parse(text), !entries.isEmpty {
            appendDrafts(entries.map { mapToDraft($0) })
            return
        }

        #if os(Android)
        // Offline fallback — no Apple FM here, so the local DriftCore parser is
        // the last rung. It handles multi-exercise strength utterances
        // ("3x10 bench at 135, 3x12 squats") and now drops segments carrying no
        // sets/reps signal rather than inventing a 3×10 row for them.
        let localEntries = await AIActionParser.parseWorkoutExercisesAsync(text)
        if !localEntries.isEmpty {
            appendDrafts(localEntries.map { mapLocalParse($0) })
            return
        }
        #endif

        // Route through FoundationModelsExerciseExtractor (iOS 26+). On
        // `.unavailable` (FM kill-switch off / iOS<26) or a parser hiccup we fall
        // back to a single editable entry seeded with the raw text rather than
        // dead-ending. `.empty` means the message wasn't a workout — surface that.
        if #available(macOS 26, iOS 26, *) {
            do {
                let entries = try await FoundationModelsExerciseExtractor.extract(text: text)
                appendDrafts(entries.map { mapToDraft($0) })
                return
            } catch FMExerciseExtractorError.unavailable {
                // Fall through to the ad-hoc single-entry below.
            } catch FMExerciseExtractorError.empty {
                failParse("That didn't sound like a workout. Try \u{201C}3×10 bench at 135\u{201D}.")
                return
            } catch {
                // .bounded / .sessionFailed — keep the user's text as one entry.
            }
        }
        appendDrafts([fallbackDraft(text)])
    }

    /// Append newly-parsed rows to the running session and highlight them. An
    /// empty parse mid-session surfaces a transient notice rather than wiping
    /// the list; on a first (empty) session it routes to the full error screen.
    private func appendDrafts(_ drafts: [ExerciseDraft]) {
        guard !drafts.isEmpty else {
            failParse("Couldn't find an exercise in that — try again.")
            return
        }
        exercises.append(contentsOf: drafts)
        let ids = Set(drafts.map(\.id))
        recentlyAddedIDs = ids
        transientMessage = nil
        phase = .confirming
        Task { @MainActor in
            #if os(Android)
            // Task.sleep(for:) never resumes here, so the ink "just added"
            // border stuck on every card forever; the nanoseconds overload does.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            #else
            try? await Task.sleep(for: .seconds(2.5))
            #endif
            recentlyAddedIDs.subtract(ids)
        }
    }

    /// A failed parse keeps an in-progress session intact (inline notice) and
    /// only falls back to the full error screen when nothing has been logged yet.
    private func failParse(_ message: String) {
        if exercises.isEmpty {
            phase = .error(message)
        } else {
            transientMessage = message
            phase = .confirming
        }
    }

    // No availability gate: FMExerciseEntry is version-agnostic and the cloud
    // (Nebius) path calls this on all iOS versions, not just 26+. (#969)
    private func mapToDraft(_ entry: FMExerciseEntry) -> ExerciseDraft {
        // strength → sets/reps/weight; cardio/mobility/sports → duration.
        let isDuration = entry.category != .strength
        // Ground strength names against the catalog. Cardio/mobility/sports are
        // not well covered by the strength-oriented library, so they pass as-is.
        var name = entry.exerciseName
        var matched = true
        if !isDuration {
            if let hit = ExerciseDatabase.match(name: entry.exerciseName) {
                name = hit.name
            } else {
                matched = false
            }
        }
        return ExerciseDraft(
            name: name,
            isDuration: isDuration,
            matched: matched,
            sets: entry.sets.map(String.init) ?? "",
            reps: entry.reps.map(String.init) ?? "",
            weight: entry.weight.map(formatWeight) ?? "",
            durationMinutes: entry.durationMinutes.map(String.init) ?? ""
        )
    }

    #if os(Android)
    /// Local-parser counterpart of `mapToDraft`: strength-only entries with the
    /// same catalog grounding.
    private func mapLocalParse(_ entry: AIActionParser.WorkoutExercise) -> ExerciseDraft {
        var name = entry.name
        var matched = true
        if let hit = ExerciseDatabase.match(name: entry.name) {
            name = hit.name
        } else {
            matched = false
        }
        return ExerciseDraft(
            name: name,
            isDuration: false,
            matched: matched,
            sets: String(entry.sets),
            reps: String(entry.reps),
            weight: entry.weight.map(formatWeight) ?? "",
            durationMinutes: ""
        )
    }
    #endif

    private func fallbackDraft(_ text: String) -> ExerciseDraft {
        // Raw-text fallback: try to ground it; if it doesn't match, flag for the
        // user to resolve via the library picker.
        let hit = ExerciseDatabase.match(name: text)
        return ExerciseDraft(name: hit?.name ?? text, isDuration: false,
                             matched: hit != nil, sets: "", reps: "", weight: "", durationMinutes: "")
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

    func save() {
        let logged = exercises.map { draft in
            WorkoutService.VoiceLoggedExercise(
                name: draft.name,
                isDuration: draft.isDuration,
                sets: Int(draft.sets),
                reps: Int(draft.reps),
                weightLbs: Double(draft.weight),
                durationMinutes: Int(draft.durationMinutes)
            )
        }
        try? WorkoutService.saveVoiceLoggedWorkout(name: workoutName(), exercises: logged)
    }

    /// Time-of-day workout name, matching how people label sessions.
    private func workoutName() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<22: return "Evening Workout"
        default: return "Workout"
        }
    }
}

#if DRIFT_IOS_APP
#Preview {
    ExerciseVoiceLogSheet()
}
#endif
