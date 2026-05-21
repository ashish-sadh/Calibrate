import SwiftUI
import DriftCore

/// V7 Phase 5 — sheet that replaces the V6 `FloatingAIAssistant` overlay.
/// Presented from the per-screen `ChatIconButton`. The sheet owns the
/// visible backend picker — two options now per mobile review:
///   - **Local** (on-device — Apple FM if available, falls back to
///     legacy GGUF for old prefs)
///   - **Cloud (BYOK)** — user's own provider key
/// — bound to `Preferences.preferredAIBackend`, then embeds the existing
/// `AIChatView` underneath. The inline backend-tiles header inside
/// AIChatView was removed in the same pass to avoid two stacked pickers.
struct DriftCoachSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional pre-filled user message — used by "Edit in chat" from
    /// VoiceLogSheet to hand off the raw transcript into the chat input
    /// for free-form editing/refining.
    let prefill: String

    init(prefill: String = "") {
        self.prefill = prefill
    }

    /// Initialized from the persisted preference. The simplified picker
    /// shows `.foundationModels` as "Local" and `.remote` as "Cloud
    /// (BYOK)". `.llamaCpp` is the legacy on-device backend kept for
    /// backwards-compat and migrated to `.foundationModels` on launch
    /// (see DriftApp.task); not user-selectable here.
    @State private var backend: AIBackendType = Preferences.preferredAIBackend

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modelPickerHeader
                Divider().overlay(Theme.separator)
                AIChatView(prefill: prefill)
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

            // V7 mobile pass: collapsed the picker to "Local" + "Cloud
            // (BYOK)" per user feedback "Local and cloud (BYOK) was
            // enough of a switch." `.foundationModels` is the local
            // implementation (Apple Intelligence on iOS 26+ devices);
            // legacy `.llamaCpp` is migrated to `.foundationModels` on
            // launch and never surfaced here.
            Picker("Model", selection: $backend) {
                Text("Local").tag(AIBackendType.foundationModels)
                Text("Cloud (BYOK)").tag(AIBackendType.remote)
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
