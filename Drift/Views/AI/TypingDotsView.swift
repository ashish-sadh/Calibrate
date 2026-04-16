import SwiftUI

/// Animated three-dot typing indicator (chat bubble style).
struct TypingDotsView: View {
    @State private var phase = 0
    @State private var timer: Timer?

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
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
