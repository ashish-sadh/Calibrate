import SwiftUI

/// Entry point for the AI feature — handles download + shows chat when ready.
struct AIView: View {
    @State private var aiService = LocalAIService.shared

    var body: some View {
        NavigationStack {
            Group {
                switch aiService.state {
                case .notSetUp:
                    downloadPrompt
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
            .background(Theme.background.ignoresSafeArea())
        }
    }

    // MARK: - Download Prompt

    private var downloadPrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.6))

            Text("Drift AI")
                .font(.title2.weight(.bold))

            Text("Chat with an AI health assistant that understands your data. Runs entirely on your device — nothing leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 4) {
                Text("One-time setup")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("~\(aiService.downloadSizeText) · Wi-Fi recommended")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await aiService.downloadModel() }
            } label: {
                Label("Set Up AI", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Theme.deficit)
                        .font(.caption)
                    Text("100% on-device")
                        .font(.caption.weight(.medium))
                }
                Text("The AI runs locally on your iPhone. Your health data never leaves your device.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
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
