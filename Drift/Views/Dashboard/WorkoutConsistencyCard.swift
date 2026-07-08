import SwiftUI
import DriftCore

struct WorkoutConsistencyCard: View {
    let insight: BehaviorInsight
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .font(.body)
                .foregroundStyle(insight.isPositive ? Theme.deficit : Theme.stepsOrange)
                .frame(width: 32, height: 32)
                .background(
                    (insight.isPositive ? Theme.deficit : Theme.stepsOrange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.caption.weight(.semibold))
                Text(insight.detail).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(6)
                    .background(Theme.cardBackgroundElevated, in: Circle())
            }
            .accessibilityLabel("Dismiss workout consistency card")
        }
        .card()
    }
}
