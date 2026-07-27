import SwiftUI
import DriftCore

/// V7 Phase 5 — the "Describe" meal logger (#935 merged the old separate
/// Voice and Text methods): ONE input you can type into or dictate into via
/// the inline mic; both fill the same draft, then Continue parses it.
///
/// Pipeline:
///   1. Opens on the typed field. Tapping the mic starts
///      `SpeechRecognitionService` and live partials feed `transcript`;
///      the final transcript fills the SAME draft for review.
///   2. Continue routes the draft through `parse(_:)`. Phase → `.parsing`.
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
    @State private var viewModel: VoiceLogViewModel
    /// Buffer for the "Describe your meal" field. Kept as view state so a
    /// parse error → "Try again" returns the user here with text intact;
    /// dictation fills the same buffer (#935: type or speak, one input).
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    /// Query handed off from the search tab's "log with AI" row — parsed
    /// immediately on appear so the tap lands straight in the AI review, not
    /// on an empty Describe field (field ask 2026-07-27).
    let initialQuery: String?

    /// `date` seeds the internal FoodLogViewModel so a Describe log lands on
    /// the day the user is viewing, not always today — this was the last
    /// LogMealSheet tab still logging past-day entries onto today (past-day
    /// logging fix, 2026-07-09). Defaults to today for standalone use.
    init(date: Date = Date(), initialQuery: String? = nil) {
        let vm = VoiceLogViewModel()
        vm.foodLog.selectedDate = date
        _viewModel = State(initialValue: vm)
        self.initialQuery = initialQuery
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
        // #966: the Cancel/Continue bar rides above the keyboard as a bottom
        // safe-area inset on THIS full-height container, which owns the
        // keyboard avoidance directly — insetting the inner typingView left it
        // short. Only the typing phase shows it; other phases carry their own
        // in-flow action rows.
        .safeAreaInset(edge: .bottom) {
            // In-flow bar only when the keyboard is DOWN. While typing, the
            // keyboard accessory toolbar carries Cancel/Continue (#966), so
            // hiding this avoids a duplicate row stacked at the same spot.
            if case .typing = viewModel.phase, !fieldFocused { typingBottomBar }
            // While the keyboard is UP, this sheet's keyboard safe area
            // undershoots by roughly the accessory bar (#966 note below), so
            // the accessory Cancel/Continue rendered ON TOP of the text field
            // (field report 2026-07-09). A spacer the accessory's height
            // lifts the field clear.
            if case .typing = viewModel.phase, fieldFocused {
                Color.clear.frame(height: 52)
            }
        }
        // .container only — the keyboard inset must still propagate so the
        // inset row rides above the keyboard. ignoresSafeArea() = .all would
        // absorb the keyboard bottom inset and defeat it. (#933/#966)
        .background(Theme.background.ignoresSafeArea(.container))
        .task {
            viewModel.start()
            if let q = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                // Seed the draft too, so a parse error → "Try again" returns
                // to the field with the query intact.
                draft = q
                await viewModel.submitTyped(q)
            }
        }
        .onChange(of: viewModel.dictatedDraft) { _, dictated in
            // Dictation fills the SAME draft the keyboard edits (#935).
            if !dictated.isEmpty { draft = dictated }
        }
        .onDisappear { viewModel.cancel() }
        // #966: the bottom safeAreaInset can't clear the keyboard's QuickType
        // suggestion bar in this sheet (SwiftUI's keyboard safe area undershoots
        // by ~its height, leaving Continue occluded). Mirror the actions into the
        // keyboard input accessory — UIKit pins this directly above the keyboard,
        // guaranteed — so the submit button is always reachable while typing.
        // The in-flow bottom bar still shows when the keyboard is down.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if case .typing = viewModel.phase {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button {
                        Task { await viewModel.submitTyped(draft) }
                    } label: {
                        Label("Continue", systemImage: "arrow.forward.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("describe-meal-submit-kbd")
                }
            }
        }
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
                        .font(.system(size: Theme.FontSize.display1, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityIdentifier("describe-meal-icon")

                Text("Describe your meal")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Type or speak what you ate — e.g. \u{201C}dal, rice and two rotis.\u{201D} I'll break it into items you can confirm.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // One input, two ways in (#935): type, or tap the mic to dictate
            // into the same field.
            HStack(spacing: 10) {
                TextField("dal, rice and two rotis", text: $draft, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("describe-meal-field")
                    .focused($fieldFocused)
                Button {
                    viewModel.beginListening()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: Theme.FontSize.large, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dictate your meal")
                .accessibilityIdentifier("describe-meal-mic")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // Cancel/Continue row for the typing phase. #966: this is applied as a
    // bottom safe-area inset on the OUTER body container (not on typingView),
    // so the FULL-HEIGHT, keyboard-aware view owns the inset and the row
    // reliably rides ABOVE the keyboard. Insetting the inner typingView left
    // it ~26pt short — still under the keyboard's QuickType suggestion bar.
    @ViewBuilder private var typingBottomBar: some View {
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
        .padding(.vertical, 12)
        .background(Theme.background)
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
                    viewModel.stopListening()
                } label: {
                    Label("Use It", systemImage: "checkmark")
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
                .font(.system(size: Theme.FontSize.display1))
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
                    viewModel.start()  // back to the Describe field, draft intact
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
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

    /// Dictated text handed back to the view's draft field — dictation and
    /// typing share ONE input (#935); the user reviews/edits, then Continues.
    var dictatedDraft = ""

    /// #935: one Describe screen. Starts on the typed field; the inline mic
    /// starts dictation into the same draft.
    func start() {
        transcript = ""
        reviewItems = []
        phase = .typing
    }

    func beginListening() {
        transcript = ""
        phase = .listening
        speech.startRecording(
            onTranscript: { [weak self] partial in
                self?.transcript = partial
            },
            onDone: { [weak self] final in
                // Fill the shared draft and return to the field — the user
                // confirms with Continue (same as typing). #935
                self?.dictatedDraft = final
                self?.phase = .typing
            },
            // Hand back ~1.8s after the user stops describing — no tap needed. #flowy-voice
            endpointSilence: 1.8
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

    func stopListening() {
        // `gracefulStop` flushes any final partial transcription before
        // firing the `onDone` callback, which fills the shared draft (#935).
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
