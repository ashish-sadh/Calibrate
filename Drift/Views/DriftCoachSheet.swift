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

            // V7 mobile pass: "we don't need Drift Brain if there's
            // Apple Foundation Models" — the picker is the user's
            // entire mental model for which AI is talking to them, and
            // dropping the GGUF option simplifies that to "system
            // intelligence vs. your own cloud key." The .llamaCpp case
            // still exists in `AIBackendType` for any old user prefs
            // that resolved to it before Apple FM became the default;
            // a launch-time migration in DriftApp.task flips those to
            // .foundationModels. Removing the picker entry means new
            // users never *select* Drift Brain, and existing ones get
            // moved off it automatically.
            Picker("Model", selection: $backend) {
                Text("Apple Foundation Models").tag(AIBackendType.foundationModels)
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
            // V7: legacy backend retained in the enum so old prefs
            // resolve, but no longer surfaced in the picker. If a user
            // somehow lands here pre-migration, show the same on-device
            // privacy line so the privacy story doesn't break.
            return "On-device · legacy local model (migrating to Apple Foundation Models on next launch)."
        case .remote:
            return "Cloud · uses your BYOK key. Messages leave your device."
        }
    }
}

#Preview {
    DriftCoachSheet()
}
