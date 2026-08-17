#if os(Android)
import SwiftUI
import DriftCore

// MARK: - Proposed Meal Card, Android (#1174)
//
// The iOS card lives in Drift/Views/AI/AIChatView+Cards.swift:14-89 alongside
// the other twelve, which is an app-target file the Skip passes never see. This
// is the ONE card the photo turn can't work without — without a Log-all button
// the parsed meal is unreachable — so it is ported here and the rest stay in
// #1125. Structure, copy, spacing and colors are the iOS card verbatim; the
// three deviations are noted inline (drawn fork/knife, no monospacedDigit,
// `.stroke` not `.strokeBorder`).

extension AIChatView {

    func proposedMealCardAndroid(_ card: AIChatViewModel.ProposedMealCardData, messageId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // fork.knife has no Material mapping and the cart stand-in read
                // as SHOPPING (directive 0a) — draw it, as every other food
                // surface does. iOS uses fork.knife.circle.fill at .caption.
                ForkKnifeShape()
                    .fill(Theme.calorieBlue)
                    .frame(width: 13, height: 13)
                Text("Detected meal")
                    .font(.caption.weight(.semibold))
                Spacer()
                // No .monospacedDigit() — SkipUI drops the modifier.
                Text("\(card.items.reduce(0) { $0 + $1.calories }) cal")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.separator)

            ForEach(card.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.caption.weight(.medium))
                        Text("\(item.grams)g · \(item.protein)P \(item.carbs)C \(item.fat)F")
                            .font(.system(size: Theme.FontSize.nano)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text("\(item.calories) cal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.calorieBlue)
                }
            }

            HStack(spacing: 10) {
                Button {
                    vm.clearPendingProposal()
                    vm.inputText = "Change "
                    inputFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sym("pencil"))
                            .font(.system(size: Theme.FontSize.micro, weight: .medium))
                        Text("Edit")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    // `.stroke` not `.strokeBorder` — SkipUI's strokeBorder
                    // overload set is ambiguous here (AIChatView.swift:523).
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Spacer()

                Button {
                    vm.confirmProposedMeal(card, messageId: messageId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sym("checkmark.circle.fill"))
                            .font(.system(size: Theme.FontSize.micro, weight: .medium))
                        Text("Log all")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.calorieBlue))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(vm.isGenerating)
                .accessibilityLabel("Log all items")
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .stroke(Theme.calorieBlue.opacity(0.25), lineWidth: 0.5)
        )
    }
}
#endif
