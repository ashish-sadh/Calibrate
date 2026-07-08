import SwiftUI
import DriftCore

/// Loading-state placeholders for the dashboard (#963). Shown while
/// `DashboardViewModel.isLoading` is true so the first frame isn't an empty
/// jump-cut into populated cards. Neutral grey blocks with a gentle shimmer —
/// no numbers, no layout shift when the real content swaps in.

/// A single shimmering grey block sized to stand in for real content.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = Theme.radiusSmall
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.cardBackgroundElevated)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(shimmer ? 0.55 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

/// Stand-in for the calorie-balance / macro-rings hero card.
struct SkeletonCalorieBalanceCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Theme.cardBackgroundElevated)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(height: 14, width: 120)
                SkeletonBlock(height: 12, width: 80)
                SkeletonBlock(height: 12, width: 100)
            }
            Spacer()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 128)
        .card()
    }
}

/// Stand-in for the meal timeline rail (a few placeholder rows).
struct SkeletonMealTimelineSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.cardBackgroundElevated)
                        .frame(width: 10, height: 10)
                    SkeletonBlock(height: 12, width: 160)
                    Spacer()
                    SkeletonBlock(height: 12, width: 44)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// Stand-in for the WEIGHT / SLEEP / READINESS 3-card row.
struct SkeletonBodySummaryCardsRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 8) {
                    SkeletonBlock(height: 12, width: 48)
                    SkeletonBlock(height: 20, width: 60)
                }
                .frame(maxWidth: .infinity, minHeight: 84)
                .card()
            }
        }
    }
}
