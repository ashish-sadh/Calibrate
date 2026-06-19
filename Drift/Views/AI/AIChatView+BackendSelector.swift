import SwiftUI
import DriftCore

// MARK: - Backend selector header (#540)
//
// Side-by-side Local Brain / Cloud AI selector cards shown at the top of the
// chat sheet when both backends are available. Replaces the tiny icon toggle
// that users couldn't find.

extension AIChatView {

    var backendSelectorHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                backendCard(
                    title: "Local Brain",
                    icon: "cpu",
                    subtitle: localBrainSubtitle,
                    selected: vm.activeBackend != .remote,
                    action: { vm.toggleBackend(to: .llamaCpp) }
                )
                backendCard(
                    title: "Drift Coach",
                    icon: "cloud.fill",
                    subtitle: cloudAISubtitle,
                    selected: vm.activeBackend == .remote,
                    action: { vm.toggleBackend(to: .remote) }
                )
            }
            .padding(.horizontal, 12)

            Text(vm.activeBackend == .remote
                ? "Drift Coach \u{00B7} cloud-powered for faster, smarter answers. Messages leave your device when this is on."
                : "On-device \u{00B7} runs entirely on your phone. Free, private, no internet needed.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .animation(.easeInOut(duration: 0.2), value: vm.activeBackend)
        }
        .padding(.top, 10).padding(.bottom, 6)
        .background(Color.white.opacity(0.03))
        .accessibilityIdentifier("ai-backend-selector")
    }

    private func backendCard(title: String, icon: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Theme.accent.opacity(0.8) : Color.secondary.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Theme.accent.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Theme.accent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.plain)
        .disabled(vm.isGenerating)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title): \(subtitle). \(selected ? "Selected." : "Tap to select.")")
    }

    private var localBrainSubtitle: String {
        switch vm.aiService.state {
        case .notSetUp: return "Not installed"
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        case .loading: return "Loading..."
        case .ready where vm.aiService.isModelLoaded: return "Loaded"
        case .ready: return "Ready to load"
        case .error: return "Error"
        case .notEnoughSpace: return "Not enough space"
        }
    }

    private var cloudAISubtitle: String {
        AIBackendCoordinator.hasCoachCloud ? "Cloud \u{00B7} fast" : "Unavailable"
    }
}
