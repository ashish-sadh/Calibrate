import SwiftUI
import UIKit
import DriftCore

/// Coordinator that owns the three phases of the Photo Log sheet: capture
/// (pick photo), analyzing (waiting on cloud vision), and review (edit +
/// log). Keeps `FoodTabView` thin — it just presents this one sheet.
/// #224 / #267.
@MainActor
struct PhotoLogFlowView: View {
    let foodLog: FoodLogViewModel
    /// Injectable so tests can drive the flow without a live network call.
    /// In production this stays nil and `runAnalysis` builds one via
    /// `PhotoLogTool`'s default wiring (Keychain key + selected provider).
    var analyzer: (UIImage) async -> Result<PhotoLogResponse, Error> = Self.defaultAnalyzer

    @Environment(\.dismiss) private var dismiss
    @State private var state: PhotoLogViewState = .capture
    @State private var analysisTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            switch state {
            case .capture:
                PhotoLogCaptureView { image in
                    runAnalysis(on: image)
                }
            case .analyzing:
                analyzingView
            case .review(let items, let confidence, let notes):
                reviewView(initialItems: items, confidence: confidence, notes: notes)
            case .empty:
                emptyView
            case .error(let message):
                errorView(message: message)
            }
        }
        .onDisappear { analysisTask?.cancel() }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                ProgressView().scaleEffect(1.4).tint(Theme.accent)
                Text("Analyzing your meal…")
                    .font(.headline)
                Text("One photo → one call. Usually 3–6 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        analysisTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Review (unwrapped with binding)

    private func reviewView(initialItems: [PhotoLogEditableItem],
                            confidence: Confidence,
                            notes: String?) -> some View {
        ReviewHost(items: initialItems,
                   confidence: confidence,
                   notes: notes,
                   foodLog: foodLog,
                   onLogged: { dismiss() },
                   onRetake: { state = .capture })
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.textTertiary)
                Text("We couldn't spot any food in that photo.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Try one with the meal centered and in good light.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    state = .capture
                } label: {
                    Label("Take another", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func errorView(message: String) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.surplus)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button {
                    state = .capture
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Flow

    private func runAnalysis(on image: UIImage) {
        state = .analyzing
        analysisTask?.cancel()
        analysisTask = Task { @MainActor in
            let result = await analyzer(image)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let response):
                if response.items.isEmpty {
                    state = .empty
                } else {
                    let editable = response.items.map { PhotoLogEditableItem(from: $0) }
                    state = .review(editable, response.overallConfidence, response.notes)
                }
            case .failure(let error):
                state = .error(Self.friendlyMessage(for: error))
            }
        }
    }

    /// Default analyzer used in production: delegates to `PhotoLogTool`'s
    /// direct-run path which already knows how to build a service from the
    /// stored key. Tests pass a stub closure instead.
    nonisolated static func defaultAnalyzer(_ image: UIImage) async -> Result<PhotoLogResponse, Error> {
        do {
            let response = try await PhotoLogFlowService.analyze(image: image)
            return .success(response)
        } catch {
            return .failure(error)
        }
    }

    nonisolated static func friendlyMessage(for error: Error) -> String {
        switch error {
        case CloudVisionError.unauthorized:
            return "Your API key was rejected. Re-add it in Settings → Photo Log (Beta)."
        case CloudVisionError.rateLimited:
            return "Provider is throttling. Try again in a minute."
        case CloudVisionError.timeout:
            return "Photo analysis timed out. Check your connection and try again."
        case CloudVisionError.offline, PhotoLogService.Error.offline:
            return "Couldn't reach the provider. Check your connection and try again."
        case CloudVisionError.malformedPayload:
            return "Provider returned an unreadable response. Try a clearer photo."
        case PhotoLogService.Error.encodingFailed:
            return "Couldn't prepare that image. Try a different photo."
        case CloudVisionKey.StorageError.notFound:
            return "No key saved. Add one in Settings → Photo Log (Beta)."
        default:
            return "Photo analysis failed. Try again in a moment."
        }
    }
}

/// Hosts a mutable `[PhotoLogEditableItem]` for the review step so the
/// row-level edits survive re-renders. Extracted so the flow coordinator
/// stays a value type with simple @State.
private struct ReviewHost: View {
    @State var items: [PhotoLogEditableItem]
    let confidence: Confidence
    let notes: String?
    let foodLog: FoodLogViewModel
    let onLogged: () -> Void
    let onRetake: () -> Void

    var body: some View {
        PhotoLogReviewView(
            items: $items,
            overallConfidence: confidence,
            notes: notes,
            foodLog: foodLog,
            onLogged: onLogged,
            onRetake: onRetake
        )
    }
}

/// Thin wrapper that reuses `PhotoLogTool`'s default service wiring for the
/// UI flow. Kept separate from the tool so the tool layer doesn't need to
/// know about SwiftUI views.
@MainActor
enum PhotoLogFlowService {
    static func analyze(image: UIImage) async throws -> PhotoLogResponse {
        let provider = Preferences.photoLogProvider
        guard let key = try await CloudVisionKey.get(for: provider) else {
            throw CloudVisionKey.StorageError.notFound
        }
        let model = Preferences.photoLogModel(for: provider)
        let client: CloudVisionClient
        switch provider {
        case .anthropic: client = AnthropicVisionClient(apiKey: key, model: model)
        case .openai:    client = OpenAIVisionClient(apiKey: key, model: model)
        case .gemini:    client = GeminiVisionClient(apiKey: key, model: model)
        }
        let service = PhotoLogService(client: client)
        return try await service.analyze(image: image, prompt: PhotoLogTool.defaultPrompt)
    }
}
