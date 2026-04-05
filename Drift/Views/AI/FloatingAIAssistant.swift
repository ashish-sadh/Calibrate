import SwiftUI

/// Floating AI assistant bubble — sits above tab bar on all screens.
struct FloatingAIAssistant: View {
    @State private var isExpanded = false
    @State private var aiService = LocalAIService.shared
    @State private var modelManager = AIModelManager.shared

    @State private var showReadyBanner = false

    var body: some View {
        VStack(spacing: 8) {
            // "I'm ready" banner
            if showReadyBanner {
                Button { showReadyBanner = false; isExpanded = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.caption)
                        Text("AI is ready").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)
                }
                .transition(.scale.combined(with: .opacity))
            }

            if isExpanded {
                expandedChat
            } else {
                minimizedBubble
            }
        }
        .padding(.bottom, 70)
        .padding(.trailing, 16)
        .animation(.spring(response: 0.3), value: isExpanded)
        .animation(.spring(response: 0.3), value: showReadyBanner)
        .onChange(of: modelManager.downloadState) { old, new in
            // Auto-minimize when download starts
            if case .downloading = new, isExpanded {
                isExpanded = false
            }
            // Pop "I'm ready" when download completes
            if case .completed = new {
                if case .downloading = old {
                    showReadyBanner = true
                    // Auto-dismiss after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        showReadyBanner = false
                    }
                }
            }
        }
    }

    // MARK: - Minimized Bubble

    private var minimizedBubble: some View {
        Button { withAnimation { isExpanded = true } } label: {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)

                if case .downloading(let progress) = modelManager.downloadState {
                    // Download progress ring
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Chat

    private var expandedChat: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Drift AI").font(.subheadline.weight(.semibold))
                Text("Beta").font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
                Spacer()
                Button { withAnimation { isExpanded = false } } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Chat content
            if !modelManager.isModelDownloaded {
                downloadPrompt
            } else {
                AIChatView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.45)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.leading, 16)
    }

    // MARK: - Download Prompt (inside expanded chat)

    private var downloadPrompt: some View {
        VStack(spacing: 14) {
            Spacer()

            if case .downloading(let progress) = modelManager.downloadState {
                ProgressView(value: progress).tint(Theme.accent).padding(.horizontal, 40)
                Text("\(Int(progress * 100))% · Setting up AI").font(.caption).foregroundStyle(.secondary)
            } else if case .error(let msg) = modelManager.downloadState {
                Text(msg).font(.caption).foregroundStyle(Theme.surplus).multilineTextAlignment(.center).padding(.horizontal, 20)
                Button { Task { await aiService.downloadModel() } } label: {
                    Label("Try Again", systemImage: "arrow.clockwise").font(.caption)
                }.buttonStyle(.bordered)
            } else {
                Image(systemName: "arrow.down.circle").font(.title).foregroundStyle(Theme.accent.opacity(0.6))
                Text("~\(aiService.downloadSizeText)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("Wi-Fi recommended").font(.caption2).foregroundStyle(.tertiary)
                Button {
                    Task { await aiService.downloadModel() }
                } label: {
                    Label("Set Up AI", systemImage: "sparkles").font(.subheadline)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }

            Spacer()

            Text("100% on-device · Your data stays private")
                .font(.system(size: 9)).foregroundStyle(.quaternary)
                .padding(.bottom, 8)
        }
    }
}
