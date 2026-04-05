import SwiftUI

/// Entry point for the AI feature — shows chat when model is ready.
struct AIView: View {
    @State private var aiService = LocalAIService.shared

    var body: some View {
        NavigationStack {
            Group {
                switch aiService.state {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading AI model...").font(.subheadline).foregroundStyle(.secondary)
                    }
                case .ready:
                    AIChatView()
                case .error(let msg):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.surplus.opacity(0.6))
                        Text("AI Unavailable").font(.headline)
                        Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
        }
    }
}
