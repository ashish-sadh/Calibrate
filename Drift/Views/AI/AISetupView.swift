import SwiftUI
import DriftCore

/// Entry point for the AI feature — handles download + shows chat when ready.
struct AIView: View {
    @State private var aiService = LocalAIService.shared

    var body: some View {
        NavigationStack {
            Group {
                // Remote backend takes precedence: when the user has flipped
                // their preference to cloud and the key is configured, treat
                // the chat as ready even if the local model isn't downloaded.
                // Spec §LocalAIService.state: ready when EITHER backend
                // available. #515.
                if shouldShowChat {
                    AIChatView()
                        .onAppear { Task { await AIBackendCoordinator.applyPreferredBackend() } }
                } else {
                    switch aiService.state {
                    case .notSetUp:
                        AIChooserView()
                    case .downloading(let progress):
                        downloadingView(progress: progress)
                    case .loading:
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading AI...").font(.subheadline).foregroundStyle(.secondary)
                        }
                    case .ready:
                        AIChatView()
                    case .error(let msg):
                        errorView(message: msg)
                    case .notEnoughSpace(let msg):
                        notEnoughSpaceView(message: msg)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
        }
    }

    /// True when at least one backend is ready to serve a chat turn — skips
    /// the chooser / download / loading UI entirely.
    ///
    /// 2026-05-19: Apple FoundationModels is now the default backend on
    /// supported hardware. FM is system-managed (no weights to download, no
    /// per-call cost, ships with the OS), so when it's the preferred backend
    /// we go straight into the chat. The old chooser/download flow only
    /// applied to the local llama.cpp era — we keep its branches for users
    /// who explicitly switched to llama.cpp via the in-chat backend toggle.
    /// Remote BYOK still requires a stored key.
    private var shouldShowChat: Bool {
        switch Preferences.preferredAIBackend {
        case .foundationModels: return true
        case .remote: return AIBackendCoordinator.hasRemoteKey
        case .llamaCpp, .mlx: return false
        }
    }

    // MARK: - Downloading

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.6))
                .symbolEffect(.pulse)

            Text("Setting up Drift AI")
                .font(.title3.weight(.semibold))

            ProgressView(value: progress)
                .tint(Theme.accent)
                .padding(.horizontal, 60)

            Text("\(Int(progress * 100))%")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.accent)

            Text("Downloading AI model. This only happens once.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.surplus.opacity(0.6))
            Text("Setup Failed").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button {
                Task { await aiService.downloadModel() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }.buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Not Enough Space

    private func notEnoughSpaceView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Not Enough Storage").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Text("Free up some space and try again.")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
    }
}
