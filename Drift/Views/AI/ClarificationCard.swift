import SwiftUI
import DriftCore

/// Chip-style card rendered inside a chat bubble when the AI has 2-5 concrete
/// alternatives and wants the user to pick one instead of re-typing. Tapping a
/// chip dispatches `onPick`; >5 options fold the overflow into an "Other" chip
/// that opens the keyboard via `onOther`. #316.
struct ClarificationCard: View {
    let options: [ClarificationOption]
    let isDisabled: Bool
    let onPick: (ClarificationOption) -> Void
    let onOther: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(visibleOptions) { option in
                chipButton(for: option)
            }
            if showsOtherChip {
                otherChipButton
            }
        }
    }

    // MARK: - Chip layout helpers

    var visibleOptions: [ClarificationOption] {
        options.count <= 5 ? options : Array(options.prefix(4))
    }

    var showsOtherChip: Bool { options.count > 5 }

    // MARK: - Option chip

    private func chipButton(for option: ClarificationOption) -> some View {
        Button {
            onPick(option)
        } label: {
            HStack(spacing: 8) {
                if let icon = option.displayIcon {
                    Image(systemName: icon)
                        .font(.system(size: Theme.FontSize.footnote))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                } else {
                    Text("\(option.id)")
                        .font(.system(size: Theme.FontSize.tiny, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20, height: 20)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if let hint = option.secondaryText {
                        Text(hint)
                            .font(.system(size: Theme.FontSize.micro))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusChip)
                    .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    // MARK: - Other chip (overflow fallback)

    private var otherChipButton: some View {
        Button {
            onOther()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: Theme.FontSize.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                Text("Other (type answer)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusChip)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}
