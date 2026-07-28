import SwiftUI

/// Animated three-dot typing indicator (chat bubble style).
///
/// Driven by a `.task` + `Task.sleep` loop rather than a `Timer` or
/// `TimelineView`: `Timer` callbacks don't drive UI under Compose and SkipUI has
/// no `TimelineView`, so both left the dots frozen on phase 0 — the coach looked
/// hung during every generation (#1066). `Task.sleep(nanoseconds:)` runs on both
/// platforms (proven in SharedUI/ChatView's poll loop); the `.task` auto-cancels
/// when the indicator leaves the screen.
struct TypingDotsView: View {
    @State var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.accent.opacity(phase == i ? 0.9 : 0.3))
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.35), value: phase)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}
