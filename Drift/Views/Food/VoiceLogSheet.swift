import SwiftUI
import DriftCore

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
///   3. Parse via `FoodLogIntentExtractor.extract(text:)` (Apple
///      FoundationModels, iOS 26+). For older OSes we fall back to a
///      simple single-item entry where `foodName = transcript`.
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

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
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
        .task { await viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Listening

    private var listeningView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 140, height: 140)
                    .scaleEffect(viewModel.pulse ? 1.05 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: viewModel.pulse
                    )
                Image(systemName: "mic.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
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
                    Text("I heard:")
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
                    NotificationCenter.default.post(
                        name: .expandAIAssistant,
                        object: nil,
                        userInfo: ["prefill": viewModel.transcript]
                    )
                    dismiss()
                } label: {
                    Text("Edit in chat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.textSecondary)
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
                    Task { await viewModel.start() }
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
    var pulse: Bool = false

    private let speech = SpeechRecognitionService.shared
    private let foodLogVM = FoodLogViewModel()

    func start() async {
        transcript = ""
        parsedItems = []
        phase = .listening
        pulse = true
        speech.startRecording(
            onTranscript: { [weak self] partial in
                self?.transcript = partial
            },
            onDone: { [weak self] final in
                Task { await self?.parse(final) }
            }
        )
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
        pulse = false
    }

    private func parse(_ text: String) async {
        guard !text.isEmpty else {
            phase = .error("Didn't catch any speech. Try again — make sure the mic permission is granted.")
            return
        }
        phase = .parsing

        // Apple Foundation Models extractor only available on iOS 26+.
        // Older OS users get a fallback that treats the whole transcript
        // as one ad-hoc food entry — they can edit before logging.
        if #available(macOS 26, iOS 26, *) {
            do {
                let intent = try await FoodLogIntentExtractor.extract(text: text)
                parsedItems = mapToParsedItems(intent: intent)
                phase = .confirming
                return
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
        let candidates = FoodService.searchFood(query: name)
        if let match = candidates.first {
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
