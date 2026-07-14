import SwiftUI
import DriftCore

/// V7 — sheet hosting Drift Coach (replaces the V6 `FloatingAIAssistant`).
/// Presented from the per-screen `ChatIconButton`. NO backend picker: the coach
/// just works on the cloud brain (Nebius), installed on open, with a silent
/// fall-back to the on-device backend when no key is provisioned. The
/// Local-vs-Cloud choice was removed per user feedback ("make it simpler").
struct DriftCoachSheet: View {
    /// Optional pre-filled user message — used by "Edit in chat" from
    /// VoiceLogSheet to hand off the raw transcript into the chat input.
    let prefill: String
    /// #936: Ask-AI seeds fire as a turn immediately; edit-in-chat (false)
    /// leaves the prefill in the input for the user to refine.
    let autoSubmit: Bool

    init(prefill: String = "", autoSubmit: Bool = false) {
        self.prefill = prefill
        self.autoSubmit = autoSubmit
    }

    var body: some View {
        NavigationStack {
            AIChatView(prefill: prefill, autoSubmit: autoSubmit)
                .background(Theme.background.ignoresSafeArea())
                // AIChatView renders its own header (voice cluster + title +
                // close) — the system bar would double it. Kept inside a
                // NavigationStack for the sheets it presents.
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    // Backend install moved to AIChatView.onAppear (synchronous, so
                    // the first turn can't race it). Here we just warm the data cache.
                    await AIDataCache.shared.refreshIfNeeded()
                }
        }
    }
}

#Preview {
    DriftCoachSheet()
}
