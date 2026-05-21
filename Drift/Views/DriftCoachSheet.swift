import SwiftUI
import DriftCore

/// V7 Phase 5 — sheet that replaces the V6 `FloatingAIAssistant` overlay.
/// Presented from the per-screen `ChatIconButton` (issue #822) on every
/// primary tab root. The sheet owns the visible backend picker (Apple
/// Foundation Models / Local Gemma / Bring Your Own Key) bound to
/// `Preferences.preferredAIBackend`, then embeds the existing
/// `AIChatView` underneath so the chat surface itself is untouched.
struct DriftCoachSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Initialized from the persisted preference so the segmented control
    /// reflects current state on present. Writes back synchronously on
    /// change so subsequent presentations of the sheet (and the embedded
    /// `AIChatView` selector) read the new value immediately. The async
    /// backend swap is fired alongside via `AIBackendCoordinator` so the
    /// next message routes through the picked backend.
    @State private var backend: AIBackendType = Preferences.preferredAIBackend

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modelPickerHeader
                Divider().overlay(Theme.separator)
                AIChatView()
                    .task { await AIDataCache.shared.refreshIfNeeded() }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Drift Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("drift-coach-done")
                }
            }
        }
    }

    private var modelPickerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Picker("Model", selection: $backend) {
                Text("Apple Foundation Models").tag(AIBackendType.foundationModels)
                Text("Local Gemma").tag(AIBackendType.llamaCpp)
                Text("Bring Your Own Key").tag(AIBackendType.remote)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drift-coach-model-picker")
            .onChange(of: backend) { _, next in
                Preferences.preferredAIBackend = next
                Task { await AIBackendCoordinator.applyPreferredBackend() }
            }

            Text(privacyBlurb(for: backend))
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBackground)
    }

    private func privacyBlurb(for backend: AIBackendType) -> String {
        switch backend {
        case .foundationModels:
            return "On-device · Apple Intelligence. Nothing leaves your phone."
        case .llamaCpp, .mlx:
            return "On-device · Local Gemma. Nothing leaves your phone."
        case .remote:
            return "Cloud · uses your BYOK key. Messages leave your device."
        }
    }
}

#Preview {
    DriftCoachSheet()
}
