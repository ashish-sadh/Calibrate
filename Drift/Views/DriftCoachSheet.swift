import SwiftUI
import DriftCore

/// V7 — sheet hosting Drift Coach (replaces the V6 `FloatingAIAssistant`).
/// Presented from the per-screen `ChatIconButton`. NO backend picker: the coach
/// just works on the cloud brain (Nebius), installed on open, with a silent
/// fall-back to the on-device backend when no key is provisioned. The
/// Local-vs-Cloud choice was removed per user feedback ("make it simpler").
struct DriftCoachSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional pre-filled user message — used by "Edit in chat" from
    /// VoiceLogSheet to hand off the raw transcript into the chat input.
    let prefill: String

    init(prefill: String = "") {
        self.prefill = prefill
    }

    var body: some View {
        NavigationStack {
            AIChatView(prefill: prefill)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Drift Coach")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("drift-coach-done")
                    }
                }
                .task {
                    // Coach just works on the cloud brain; installCoachBackend()
                    // no-ops and leaves the on-device backend in place when no
                    // key is provisioned (silent fallback). Replaces the removed
                    // Local/Cloud picker.
                    AIBackendCoordinator.installCoachBackend()
                    await AIDataCache.shared.refreshIfNeeded()
                }
        }
    }
}

#Preview {
    DriftCoachSheet()
}
