import SwiftUI
import DriftCore

/// How a `VoiceLogSheet` collects the meal description before it funnels
/// through the shared parse → multi-item confirmation-card pipeline.
/// `.voice` (default) starts `SpeechRecognitionService`; `.text` shows the
/// "Describe your meal" typed-text field and never touches the mic (no
/// second `AVAudioSession` owner). Both modes converge on the SAME
/// `parse(_:)` → `confirmView`, so a multi-item utterance becomes multiple
/// confirmable rows either way.
enum VoiceEntryMode {
    case voice
    case text
}

/// V7 Phase 5 — standalone voice-first meal logger. Used by both the
/// dashboard quick-log "Voice" chip and the Voice mode inside the
/// unified Log-a-Meal sheet. Replaces the V6 "Voice opens full chat
/// with mic active" flow that users described as too heavy for the
/// 90% case of "log two eggs."
///
/// Pipeline:
///   1. `onAppear` → `SpeechRecognitionService.shared.startListening(...)`.
///      Live partial transcripts feed `transcript`.
///   2. User taps Stop → service emits the final transcript via the
///      `onDone` callback. Phase flips to `.parsing`.
///   3. Parse via `FoundationModelsFoodExtractor.extract(text:)` (Apple
///      FoundationModels facade, iOS 26+). The facade short-circuits to
///      `.unavailable` when `Preferences.fmFoodIntentExtractEnabled` is OFF
///      or on iOS<26; in either case we fall back to a simple single-item
///      entry where `foodName = transcript`.
///   4. Phase flips to `.confirming` with a list of parsed items.
///   5. User taps "Log all" → resolve each item against the local food
///      DB (`FoodService.searchFood`) and call `FoodLogViewModel.quickAdd`
///      to insert the entry. Multi-item meals each become one entry.
///   6. Dismiss with a `lastLoggedAt` notification so the dashboard can
///      refresh.
///
/// If parse fails or the user wants the full multi-turn editing flow,
/// the "Edit in chat" path dismisses the sheet and re-posts the
/// transcript into the Drift Coach chat via NotificationCenter.
struct VoiceLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = VoiceLogViewModel()
    /// Buffer for the `.text` entry mode's "Describe your meal" field. Kept
    /// as view state so a parse error → "Try again" returns the user to the
    /// typing screen with their text intact.
    @State private var draft = ""

    let entryMode: VoiceEntryMode

    init(entryMode: VoiceEntryMode = .voice) {
        self.entryMode = entryMode
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .typing:
                typingView
            case .listening:
                listeningView
            case .parsing:
                parsingView
            case .confirming:
                // Reuse Snap's editable review sheet: tweak amounts/macros, drop
                // items, then log. #food-logging-reuse
                MealReviewSheet(
                    items: viewModel.reviewItems,
                    foodLog: viewModel.foodLog,
                    onLogged: {
                        NotificationCenter.default.post(
                            name: .navigateToTab, object: nil, userInfo: ["tab": 2])
                        dismiss()
                    })
            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task { await viewModel.start(mode: entryMode) }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Typing (Describe your meal)

    private var typingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.ink.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "keyboard")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityIdentifier("describe-meal-icon")

                Text("Describe your meal")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Type what you ate — e.g. \u{201C}dal, rice and two rotis.\u{201D} I'll break it into items you can confirm.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            TextField("dal, rice and two rotis", text: $draft, axis: .vertical)
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
                .accessibilityIdentifier("describe-meal-field")

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
                .accessibilityIdentifier("describe-meal-submit")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Listening

    private var listeningView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Shared mic-disc component (see VoiceMicButton). Food keeps the
            // Theme.accent tint at the default 140/44 size — pixel-identical to
            // the inline disc this replaced, so no food-path visual change.
            VoiceMicButton(tint: Theme.accent)
                .accessibilityIdentifier("voice-log-mic")

            Text("Listening…")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(viewModel.transcript.isEmpty
                 ? "\"Two eggs, toast with avocado, and a black coffee\" — speak naturally."
                 : "\"\(viewModel.transcript)\"")
                .font(.subheadline)
                .foregroundStyle(viewModel.transcript.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(minHeight: 60)
                .accessibilityIdentifier("voice-log-transcript")

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
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
                .accessibilityIdentifier("voice-log-stop")
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
            Text("Understanding what you ate…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.surplus)
            Text("Couldn't hear that")
                .font(.headline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    Task { await viewModel.start(mode: entryMode) }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).tint(Theme.ink)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class VoiceLogViewModel {
    enum Phase: Equatable {
        case typing
        case listening
        case parsing
        case confirming
        case error(String)
    }

    var phase: Phase = .listening
    var transcript: String = ""
    /// Parsed food items shown in the editable review sheet (Snap's surface).
    var reviewItems: [PhotoLogItem] = []

    private let speech = SpeechRecognitionService.shared
    /// Shared with `MealReviewSheet` so its logged entries + meal-type
    /// resolution run through one view model.
    let foodLog = FoodLogViewModel()

    func start(mode: VoiceEntryMode = .voice) async {
        transcript = ""
        // Typed free-text entry skips the speech stack entirely — it never
        // starts SpeechRecognitionService (no second AVAudioSession owner)
        // and lands the user on the typing screen. The typed text is then
        // funneled through the SAME parse → confirmation-card path as voice.
        reviewItems = []
        guard mode == .voice else {
            phase = .typing
            return
        }
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

    /// Typed-text counterpart to the speech `onDone` callback: routes the
    /// "Describe your meal" field through the identical `parse(_:)` pipeline,
    /// so a multi-item utterance ("dal, rice and two rotis") yields the same
    /// multi-row confirmation card the voice path produces.
    func submitTyped(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript = trimmed
        await parse(trimmed)
    }

    func stopAndParse() {
        // `gracefulStop` flushes any final partial transcription before
        // firing the `onDone` callback, which then drives `parse(_:)`.
        speech.gracefulStop()
    }

    func cancel() {
        // No matching cancel — `forceStop` tears down audio engine and
        // recognition task without invoking `onDone`. Safer than leaving
        // a half-open mic if the sheet is dismissed mid-recording.
        speech.forceStop()
    }

    private func parse(_ text: String) async {
        guard !text.isEmpty else {
            phase = .error("Didn't catch any speech. Try again — make sure the mic permission is granted.")
            return
        }
        phase = .parsing

        // 1. Drift Coach cloud model (same model as chat) — best macros, handles
        //    Indian portions + multi-item utterances. Returns nil when no key /
        //    unreachable / nothing parsed.
        if let resp = await MealTextLogger.parse(text), !resp.items.isEmpty {
            reviewItems = resp.items
            phase = .confirming
            return
        }

        // 2. On-device FoundationModels extractor (iOS 26+, gated). Resolve each
        //    parsed item against the local food DB for macros.
        if #available(macOS 26, iOS 26, *) {
            if let intent = try? await FoundationModelsFoodExtractor.extract(text: text) {
                reviewItems = mapToPhotoLogItems(intent: intent)
                phase = .confirming
                return
            }
        }

        // 3. Ad-hoc single item — name only, zero macros. The review sheet lets
        //    the user fill in the details before logging.
        reviewItems = [PhotoLogItem(name: text, grams: 0, calories: 0,
                                    proteinG: 0, carbsG: 0, fatG: 0,
                                    confidence: .low)]
        phase = .confirming
    }

    @available(macOS 26, iOS 26, *)
    private func mapToPhotoLogItems(intent: FMFoodLogIntent) -> [PhotoLogItem] {
        var items = [resolvePhotoItem(name: intent.foodName, quantity: intent.quantity)]
        for sub in intent.additionalItems {
            items.append(resolvePhotoItem(name: sub.foodName, quantity: sub.quantity))
        }
        return items
    }

    /// Resolve a parsed name+quantity against the local food DB into a
    /// `PhotoLogItem` (macros scaled by quantity). Falls back to a name-only
    /// item the user can edit. Re-ranks DB hits so "egg" beats comma-laden USDA
    /// Legacy rows (#bad-food-matches).
    private func resolvePhotoItem(name: String, quantity: Double) -> PhotoLogItem {
        let ranked = FoodService.searchFood(query: name).sorted { a, b in
            let aCommas = a.name.filter { $0 == "," }.count
            let bCommas = b.name.filter { $0 == "," }.count
            if aCommas != bCommas { return aCommas < bCommas }
            return a.name.count < b.name.count
        }
        if let m = ranked.first {
            return PhotoLogItem(
                name: m.name,
                grams: m.servingSize * quantity,
                calories: m.calories * quantity,
                proteinG: m.proteinG * quantity,
                carbsG: m.carbsG * quantity,
                fatG: m.fatG * quantity,
                fiberG: m.fiberG * quantity,
                confidence: .medium)
        }
        return PhotoLogItem(name: name, grams: 0, calories: 0,
                            proteinG: 0, carbsG: 0, fatG: 0, confidence: .low)
    }
}

#Preview {
    VoiceLogSheet()
}
