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
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExerciseVoiceLogViewModel()
    /// Buffer for the typed-entry field. Kept as view state so a parse error →
    /// "Try again" returns the user to the input screen with their text intact.
    @State private var draft = ""

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
                listeningView
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
    }

    // MARK: - Input (mic + typed text, both present)

    private var inputView: some View {
        VStack(spacing: 22) {
            Spacer()

            // Mic affordance — shared component, Theme.ink (no pink). Tapping
            // starts recording and flips to the listening screen.
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

            Text("e.g. \u{201C}3×10 bench at 135, then a 5k run\u{201D}")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 10) {
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                Text("or type").font(.caption2).foregroundStyle(Theme.textTertiary)
                Rectangle().fill(Theme.separator).frame(height: 0.5)
            }
            .padding(.horizontal, 40)

            TextField("3x10 bench at 135", text: $draft, axis: .vertical)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(14)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .accessibilityIdentifier("exercise-text-field")

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(Theme.textPrimary)

                Button {
                    Task { await viewModel.submitTyped(draft) }
                } label: {
                    Label("Continue", systemImage: "arrow.forward.circle.fill")
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("I heard:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    Text("\u{201C}\(viewModel.transcript)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)

                    Text("Exercises to log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.8)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    VStack(spacing: 10) {
                        ForEach($viewModel.exercises) { $exercise in
                            editableRow($exercise)
                        }
                    }
                    .padding(.horizontal, 16)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Exercise", text: exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("exercise-row-name")
                Spacer()
                Button {
                    viewModel.remove(id: exercise.wrappedValue.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove exercise")
            }

            if exercise.wrappedValue.isDuration {
                HStack(spacing: 10) {
                    numberField("Min", text: exercise.durationMinutes)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    numberField("Sets", text: exercise.sets)
                    Text("×").font(.caption).foregroundStyle(Theme.textTertiary)
                    numberField("Reps", text: exercise.reps)
                    Text("@").font(.caption).foregroundStyle(Theme.textTertiary)
                    numberField("Lbs", text: exercise.weight)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
    }

    private func numberField(_ label: String, text: Binding<String>) -> some View {
        VStack(spacing: 3) {
            TextField("—", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 54)
                .padding(.vertical, 7)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
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
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
            }
            .padding(.bottom, 24)
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
        var sets: String
        var reps: String
        var weight: String
        var durationMinutes: String
    }

    var phase: Phase = .input
    var transcript: String = ""
    var exercises: [ExerciseDraft] = []

    private let speech = SpeechRecognitionService.shared

    /// Number of rows that would actually persist (blank-named rows are skipped
    /// by `buildVoiceLogSets`), used for the confirm button label + enablement.
    var loggableCount: Int {
        exercises.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    func startListening() {
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
        // `gracefulStop` flushes the final partial transcription before firing
        // the `onDone` callback, which then drives `parse(_:)`.
        speech.gracefulStop()
    }

    func cancel() {
        // `forceStop` tears down the audio engine without invoking `onDone` —
        // safer than leaving a half-open mic if the sheet is dismissed mid-record.
        speech.forceStop()
    }

    /// Reset to the input screen (used by error "Try again").
    func reset() {
        transcript = ""
        exercises = []
        phase = .input
    }

    func remove(id: UUID) {
        exercises.removeAll { $0.id == id }
    }

    private func parse(_ text: String) async {
        guard !text.isEmpty else {
            phase = .error("Didn't catch that. Try again — make sure microphone permission is granted.")
            return
        }
        phase = .parsing

        // Route through FoundationModelsExerciseExtractor (iOS 26+). On
        // `.unavailable` (FM kill-switch off / iOS<26) or a parser hiccup we fall
        // back to a single editable entry seeded with the raw text rather than
        // dead-ending. `.empty` means the message wasn't a workout — surface that.
        if #available(macOS 26, iOS 26, *) {
            do {
                let entries = try await FoundationModelsExerciseExtractor.extract(text: text)
                exercises = entries.map { mapToDraft($0) }
                phase = .confirming
                return
            } catch FMExerciseExtractorError.unavailable {
                // Fall through to the ad-hoc single-entry below.
            } catch FMExerciseExtractorError.empty {
                phase = .error("That didn't sound like a workout. Try \u{201C}3×10 bench at 135\u{201D}.")
                return
            } catch {
                // .bounded / .sessionFailed — keep the user's text as one entry.
            }
        }
        exercises = [fallbackDraft(text)]
        phase = .confirming
    }

    @available(macOS 26, iOS 26, *)
    private func mapToDraft(_ entry: FMExerciseEntry) -> ExerciseDraft {
        // strength → sets/reps/weight; cardio/mobility/sports → duration.
        let isDuration = entry.category != .strength
        return ExerciseDraft(
            name: entry.exerciseName,
            isDuration: isDuration,
            sets: entry.sets.map(String.init) ?? "",
            reps: entry.reps.map(String.init) ?? "",
            weight: entry.weight.map(formatWeight) ?? "",
            durationMinutes: entry.durationMinutes.map(String.init) ?? ""
        )
    }

    private func fallbackDraft(_ text: String) -> ExerciseDraft {
        ExerciseDraft(name: text, isDuration: false, sets: "", reps: "", weight: "", durationMinutes: "")
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

#Preview {
    ExerciseVoiceLogSheet()
}
