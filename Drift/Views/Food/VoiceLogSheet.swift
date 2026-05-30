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
                confirmView
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

    // MARK: - Confirm

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
                    Text(entryMode == .text ? "You typed:" : "I heard:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.8)
                        .padding(.horizontal, 16)

                    Text("\"\(viewModel.transcript)\"")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)

                    Text("Items to log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.8)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        ForEach(viewModel.parsedItems) { item in
                            confirmRow(item)
                            if item.id != viewModel.parsedItems.last?.id {
                                Divider().overlay(Theme.separator)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
            }

            VStack(spacing: 10) {
                Button {
                    Task {
                        await viewModel.logAll()
                        // V7 polish: same as Recent/Done paths in
                        // LogMealSheet — after a successful voice
                        // log, route to the Food Diary so the user
                        // sees what they just added.
                        NotificationCenter.default.post(
                            name: .navigateToTab,
                            object: nil,
                            userInfo: ["tab": 2]
                        )
                        dismiss()
                    }
                } label: {
                    Label("Log \(viewModel.parsedItems.count) item\(viewModel.parsedItems.count == 1 ? "" : "s")",
                          systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .accessibilityIdentifier("voice-log-confirm")

                Button {
                    // V7 mobile fix: "Edit in chat" wasn't working
                    // because nothing listened for the V6
                    // `.expandAIAssistant` notification anymore (the
                    // FloatingAIAssistant overlay was removed when
                    // DriftCoachSheet took its place). Now posts the
                    // dedicated `.openDriftCoach` notification with a
                    // `prefill` userInfo — ContentView listens and
                    // presents DriftCoachSheet(prefill:) with the
                    // transcript routed into AIChatView's input bar.
                    NotificationCenter.default.post(
                        name: .openDriftCoach,
                        object: nil,
                        userInfo: ["prefill": viewModel.transcript]
                    )
                    dismiss()
                } label: {
                    Text("Edit in chat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.textPrimary)
            }
            .padding(16)
        }
    }

    private func confirmRow(_ item: VoiceLogViewModel.ParsedItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let kcal = item.calories {
                Text("\(Int(kcal)) kcal")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("est.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    struct ParsedItem: Identifiable, Equatable {
        let id = UUID()
        let displayName: String
        let detail: String?
        let calories: Double?
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double
        let mealType: MealType
        let servingSizeG: Double
        let servings: Double
    }

    var phase: Phase = .listening
    var transcript: String = ""
    var parsedItems: [ParsedItem] = []

    private let speech = SpeechRecognitionService.shared
    private let foodLogVM = FoodLogViewModel()

    func start(mode: VoiceEntryMode = .voice) async {
        transcript = ""
        parsedItems = []
        // Typed free-text entry skips the speech stack entirely — it never
        // starts SpeechRecognitionService (no second AVAudioSession owner)
        // and lands the user on the typing screen. The typed text is then
        // funneled through the SAME parse → confirmation-card path as voice.
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

        // Route through the FoundationModelsFoodExtractor facade — gated
        // by `Preferences.fmFoodIntentExtractEnabled` AND iOS 26+. The
        // facade throws `.unavailable` when the kill-switch is OFF or the
        // host is iOS<26 / macOS<26, in which case we fall back to a
        // single-item ad-hoc entry the user can edit before logging.
        // Other FM errors (.notFoodLog, .bounded, .sessionFailed) surface
        // to the user via the error phase so they can retry or edit.
        if #available(macOS 26, iOS 26, *) {
            do {
                let intent = try await FoundationModelsFoodExtractor.extract(text: text)
                parsedItems = mapToParsedItems(intent: intent)
                phase = .confirming
                return
            } catch FMFoodLogIntentExtractorError.unavailable {
                // Fall through to the ad-hoc single-item entry below.
            } catch let err as FMFoodLogIntentExtractorError {
                phase = .error("Parser said: \(err)")
                return
            } catch {
                phase = .error(String(describing: error))
                return
            }
        }
        parsedItems = [
            ParsedItem(
                displayName: text,
                detail: "1 serving",
                calories: nil,
                proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0,
                mealType: defaultMealType(),
                servingSizeG: 0,
                servings: 1
            )
        ]
        phase = .confirming
    }

    @available(macOS 26, iOS 26, *)
    private func mapToParsedItems(intent: FMFoodLogIntent) -> [ParsedItem] {
        var items: [ParsedItem] = []
        let meal = (intent.mealType.flatMap { MealType(rawValue: $0.rawValue) }) ?? defaultMealType()

        items.append(resolveItem(name: intent.foodName, quantity: intent.quantity, mealType: meal))
        for sub in intent.additionalItems {
            items.append(resolveItem(name: sub.foodName, quantity: sub.quantity, mealType: meal))
        }
        return items
    }

    private func resolveItem(name: String, quantity: Double, mealType: MealType) -> ParsedItem {
        // V7 mobile fix (#bad-food-matches): user reported
        // "egg" → "Fish, Whitefish, Eggs (Alaska Native)". The food
        // DB has lots of comma-laden USDA Legacy entries that match
        // simple queries before the clean single-word entries.
        // Re-rank: fewer commas first, then shorter names. So "Egg"
        // beats "Fish, Whitefish, Eggs (Alaska Native)" every time.
        let candidates = FoodService.searchFood(query: name)
        let ranked = candidates.sorted { a, b in
            let aCommas = a.name.filter { $0 == "," }.count
            let bCommas = b.name.filter { $0 == "," }.count
            if aCommas != bCommas { return aCommas < bCommas }
            return a.name.count < b.name.count
        }
        if let match = ranked.first {
            return ParsedItem(
                displayName: match.name,
                detail: "\(formatQty(quantity)) serving\(quantity == 1 ? "" : "s")",
                calories: match.calories * quantity,
                proteinG: match.proteinG * quantity,
                carbsG: match.carbsG * quantity,
                fatG: match.fatG * quantity,
                fiberG: match.fiberG * quantity,
                mealType: mealType,
                servingSizeG: match.servingSize * quantity,
                servings: quantity
            )
        }
        return ParsedItem(
            displayName: name,
            detail: "\(formatQty(quantity)) serving\(quantity == 1 ? "" : "s") · est.",
            calories: nil,
            proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0,
            mealType: mealType,
            servingSizeG: 0,
            servings: quantity
        )
    }

    private func formatQty(_ q: Double) -> String {
        q.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(q))
            : String(format: "%.1f", q)
    }

    private func defaultMealType() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    func logAll() async {
        for item in parsedItems {
            foodLogVM.quickAdd(
                name: item.displayName,
                calories: item.calories ?? 0,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                fiberG: item.fiberG,
                mealType: item.mealType,
                servingSizeG: item.servingSizeG,
                servings: 1
            )
        }
    }
}

#Preview {
    VoiceLogSheet()
}
