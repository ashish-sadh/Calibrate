import SwiftUI

/// Floating AI assistant bubble — sits above tab bar on all screens.
struct FloatingAIAssistant: View {
    let currentTab: Int
    @State private var isExpanded = false
    @State private var aiService = LocalAIService.shared
    @State private var modelManager = AIModelManager.shared
    @State private var showReadyBanner = false

    var body: some View {
        ZStack {
            // Dim background when expanded
            if isExpanded {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { isExpanded = false } }
                    .transition(.opacity)
            }

            VStack {
                Spacer()

                // "I'm ready" banner
                if showReadyBanner && !isExpanded {
                    HStack {
                        Spacer()
                        Button { showReadyBanner = false; withAnimation { isExpanded = true } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").font(.caption)
                                Text("AI is ready").font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                            .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)
                        }
                        .padding(.trailing, 16)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                if isExpanded {
                    // Full chat panel
                    expandedChat
                        .padding(.horizontal, 12)
                        .padding(.bottom, 60)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Minimized bubble
                    HStack {
                        Spacer()
                        minimizedBubble
                            .padding(.trailing, 16)
                            .padding(.bottom, 70)
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .animation(.spring(response: 0.3), value: showReadyBanner)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                aiService.cancelUnload()
            } else {
                aiService.scheduleUnload(delay: 60)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // App going to background — unload immediately to free GPU memory
            if aiService.isModelLoaded {
                Log.app.info("AI: app backgrounding — scheduling quick unload")
                aiService.scheduleUnload(delay: 10)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // App came back — cancel unload if chat is open
            if isExpanded {
                aiService.cancelUnload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { _ in
            // Collapse chat so user sees the target screen
            if isExpanded { withAnimation { isExpanded = false } }
        }
        .onChange(of: modelManager.downloadState) { old, new in
            if case .downloading = new, isExpanded { isExpanded = false }
            if case .completed = new {
                if case .downloading = old {
                    showReadyBanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { showReadyBanner = false }
                }
            }
        }
    }

    // MARK: - Minimized Bubble

    @State private var pulseAnimation = false

    private var minimizedBubble: some View {
        let isDownloading = modelManager.downloadState != .idle && modelManager.downloadState != .completed && modelManager.downloadState != .error("")

        return Button { withAnimation { isExpanded = true } } label: {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 10, y: 4)

                if case .downloading = modelManager.downloadState {
                    // Pulsing ring animation during download
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        .frame(width: 58, height: 58)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulseAnimation)
                        .onAppear { pulseAnimation = true }

                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
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
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    Text("Drift AI").font(.subheadline.weight(.semibold))
                    Text("Beta").font(.system(size: 9)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                Spacer()
                Button { withAnimation { isExpanded = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.06))

            // Chat content
            if !modelManager.isModelDownloaded {
                downloadPrompt
            } else {
                AIChatView()
                    .task { await AIDataCache.shared.refreshIfNeeded() }
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.55)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(white: 0.1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: -5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Download Prompt

    private var downloadPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            if case .downloading = modelManager.downloadState {
                ProgressView().tint(Theme.accent)
                Text("Downloading Drift Brain...")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("This may take a few minutes")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if case .error(let msg) = modelManager.downloadState {
                Text(msg).font(.caption).foregroundStyle(Theme.surplus)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)
                Button { Task { await aiService.downloadModel() } } label: {
                    Label("Try Again", systemImage: "arrow.clockwise").font(.caption)
                }.buttonStyle(.bordered)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36)).foregroundStyle(Theme.accent.opacity(0.5))

                Text("Download Drift Brain")
                    .font(.subheadline.weight(.semibold))

                VStack(spacing: 2) {
                    let freeGB = String(format: "%.1f", DeviceCapability.freeDiskGB)
                    let freeRAM = String(format: "%.0f", DeviceCapability.ramGB)
                    let ramNeeded = modelManager.currentTier == .large ? "~2.9 GB" : "~0.4 GB"
                    Text("Storage: \(aiService.downloadSizeText) needed · \(freeGB) GB available")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("Memory: \(ramNeeded) while chatting (\(freeRAM) GB on device)")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("Won't use memory or slow your phone when not chatting")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("You can always clean up from Settings")
                        .font(.caption2).foregroundStyle(.quaternary)
                }

                Button { Task { await aiService.downloadModel() } } label: {
                    Label("Download", systemImage: "sparkles").font(.subheadline)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill").font(.system(size: 9))
                Text("100% on-device · Nothing leaves your phone")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.quaternary)
            .padding(.bottom, 12)
        }
    }
}
