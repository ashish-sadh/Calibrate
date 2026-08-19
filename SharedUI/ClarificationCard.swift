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

    func chipButton(for option: ClarificationOption) -> some View {
        Button {
            onPick(option)
        } label: {
            HStack(spacing: 8) {
                if let icon = option.displayIcon {
                    clarificationGlyph(icon,
                                       tint: Theme.accent,
                                       font: .system(size: Theme.FontSize.footnote),
                                       drawnSize: Theme.FontSize.footnote)
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

    var otherChipButton: some View {
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

/// Renders a `ClarificationOption.displayIcon` — raw SF Symbol names minted in
/// DriftCore's `ClarificationBuilder`, never routed through `sym()` upstream.
///
/// Four of the nine names the builder can produce are unmapped in the pinned
/// skip-ui 1.58 (#1134) and shipped the WARNING TRIANGLE on Drift Coach's
/// disambiguation chips — the highest-traffic clarification is a food-name
/// pick, so an Indian-food query put a hazard triangle beside every option
/// (#1248, directive 0a: a missing mapping means the closest same-meaning
/// icon, never a different object). Same mechanism as `behaviorInsightGlyph`
/// (V6CoachingNudge.swift): draw the real object on Android, pass the SF name
/// through untouched on Darwin.
///
/// `font` drives the Darwin path so iOS keeps its exact type-scaled symbol;
/// `drawnSize` is the point size for the Android shapes, which have no font.
/// A NEW builder icon falls through to `sym()` and surfaces as the triangle
/// tripwire, so the gap is caught rather than hidden.
@ViewBuilder
func clarificationGlyph(_ symbol: String, tint: Color, font: Font, drawnSize: CGFloat) -> some View {
    #if os(Android)
    switch symbol {
    // The food-name disambiguation chip. Material's mapped set has no food
    // glyph at all (the cart stand-in read as SHOPPING — operator 2026-07-19),
    // so the app draws its own; same shape the Food tab icon uses.
    case "fork.knife":
        ForkKnifeShape().fill(tint).frame(width: drawnSize, height: drawnSize)
    // Supplement chip. No mapped capsule; the -45° tilt is what separates "a
    // pill" from "a bar" at this size (SupplementsTabView / V6CoachingNudge).
    case "pills.fill":
        PillShape().fill(tint).frame(width: drawnSize, height: drawnSize)
            .rotationEffect(.degrees(-45))
    // The lbs/kg chips on a bare-number message. `scalemass.fill` has no case
    // and bare `scalemass` maps to `chart.bar.xaxis`, which is 1.59-only under
    // the pin — a triangle either way. BarChartShape is already the app's
    // Android weight mark (WeightTab.swift:439), so drawing a second scale
    // glyph here would create a rival mark rather than close a gap.
    case "scalemass.fill":
        BarChartShape().fill(tint).frame(width: drawnSize, height: drawnSize)
    // The "set goal" chip. Material has no bullseye; TargetShape is the same
    // drawn rings the Today tab icon shows.
    case "target":
        TargetShape().fill(tint).frame(width: drawnSize, height: drawnSize)
    // magnifyingglass / info.circle / figure.run are mapped — keep them on the
    // real symbol path so they type-scale like iOS.
    default:
        Image(systemName: sym(symbol)).font(font).foregroundStyle(tint)
    }
    #else
    Image(systemName: symbol).font(font).foregroundStyle(tint)
    #endif
}
