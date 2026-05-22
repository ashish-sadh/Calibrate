import SwiftUI
import DriftCore

/// V7 Phase-2 body summary 3-card row. Three side-by-side cards
/// (WEIGHT / SLEEP / READINESS) under the Today timeline. Tapping any card
/// navigates the user into the Body tab so the detail entry points stay
/// consistent across the three vitals.
///
/// The WEIGHT card uses goal-aware coloring (green when the weekly rate is
/// aligned with the user's goal direction, red when against). SLEEP and
/// READINESS stay neutral — they aren't goal-tracked surfaces, just data
/// readouts. Empty-state copy is pinned by Done-When criterion 2 of #821; do
/// not rephrase without updating the spec.
struct BodySummaryCardsRow: View {
    let payloads: BodySummaryPayloads
    let onTapBody: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            card(payloads.weight)
            card(payloads.sleep)
            card(payloads.readiness)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private func card(_ payload: BodySummaryCardPayload) -> some View {
        Button(action: onTapBody) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(payload.tone)
                        .frame(width: 7, height: 7)
                    Text(payload.label)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }

                if let value = payload.value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(payload.valueColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !payload.unit.isEmpty {
                            Text(payload.unit)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if let detail = payload.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    // Empty state — render the spec string in the body of
                    // the card so users see the explicit nudge instead of
                    // a "--" placeholder. The label header above still
                    // identifies which card this is.
                    Text(payload.emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(payload.accessibilityLabel)
        .accessibilityHint("Open \(payload.label.lowercased()) details on the Body tab")
        .accessibilityIdentifier("body-summary-\(payload.label.lowercased())")
    }
}

/// Pre-formatted payload for one card. Goal-aware coloring is baked into
/// `valueColor` so the rendering layer stays dumb.
struct BodySummaryCardPayload: Equatable {
    var label: String          // "WEIGHT" / "SLEEP" / "READINESS"
    var value: String?         // nil → render emptyText
    var unit: String
    var detail: String?        // e.g. "+0.50 lbs/wk this wk" / "last night"
    var emptyText: String      // spec-pinned empty-state copy
    var tone: Color            // dot color (brand accent)
    var valueColor: Color      // goal-aware on WEIGHT; primary on others

    var accessibilityLabel: String {
        if let value {
            let unitPart = unit.isEmpty ? "" : " \(unit)"
            let detailPart = detail.map { ", \($0)" } ?? ""
            return "\(label.capitalized): \(value)\(unitPart)\(detailPart)"
        }
        return "\(label.capitalized): \(emptyText)"
    }
}

/// Bundle of all three card payloads so the call site (Dashboard) can build
/// them in one factory call.
struct BodySummaryPayloads: Equatable {
    var weight: BodySummaryCardPayload
    var sleep: BodySummaryCardPayload
    var readiness: BodySummaryCardPayload
}

extension BodySummaryCardsRow {
    /// Empty-state strings — pinned by #821 Done-When criterion 2. Exposed
    /// statics so tests can assert the constants without a hardcoded literal
    /// drifting silently.
    static let weightEmptyText = "Log your weight to track progress"
    static let sleepEmptyText = "Connect Apple Health for sleep data"
    static let readinessEmptyText = "Connect Whoop or log a manual score"

    /// Build the full payload bundle from viewmodel-published values.
    ///
    /// `goalDirection` is the user's intended direction — `.lose` / `.gain` /
    /// `.maintain`. When the weekly rate aligns with the direction, the
    /// WEIGHT card value renders in `Theme.deficit` (green); when against,
    /// `Theme.surplus` (red). Without a goal or a trend it stays primary ink.
    ///
    /// Defensively guards non-finite or non-positive weight so a corrupt
    /// entry can't render "-165.3 lbs" on the dashboard, matching the
    /// `V6BodyTile.weightPayload` discipline this view replaces.
    static func payloads(
        weightKg: Double?,
        weeklyRateKg: Double?,
        sleepHours: Double,
        recoveryScore: Int,
        hrvMs: Double,
        goalDirection: GoalDirection
    ) -> BodySummaryPayloads {
        BodySummaryPayloads(
            weight: weightPayload(
                weightKg: weightKg,
                weeklyRateKg: weeklyRateKg,
                goalDirection: goalDirection
            ),
            sleep: sleepPayload(hours: sleepHours),
            readiness: readinessPayload(recoveryScore: recoveryScore, hrvMs: hrvMs)
        )
    }

    static func weightPayload(
        weightKg: Double?,
        weeklyRateKg: Double?,
        goalDirection: GoalDirection
    ) -> BodySummaryCardPayload {
        let unit = Preferences.weightUnit
        guard let kg = weightKg, kg.isFinite, kg > 0 else {
            return BodySummaryCardPayload(
                label: "WEIGHT",
                value: nil,
                unit: "",
                detail: nil,
                emptyText: weightEmptyText,
                tone: Theme.accent,
                valueColor: Theme.textPrimary
            )
        }
        let displayValue = unit.convert(fromKg: kg)
        let detail: String?
        if let rate = weeklyRateKg, rate.isFinite, abs(rate) > 0.001 {
            let rateDisplay = unit.convert(fromKg: rate)
            detail = String(format: "%+.2f %@/wk", rateDisplay, unit.displayName)
        } else {
            detail = nil
        }
        let color: Color = goalAlignedColor(weeklyRateKg: weeklyRateKg, goalDirection: goalDirection)
        return BodySummaryCardPayload(
            label: "WEIGHT",
            value: String(format: "%.1f", displayValue),
            unit: unit.displayName,
            detail: detail,
            emptyText: weightEmptyText,
            tone: Theme.accent,
            valueColor: color
        )
    }

    static func sleepPayload(hours: Double) -> BodySummaryCardPayload {
        guard hours.isFinite, hours > 0 else {
            return BodySummaryCardPayload(
                label: "SLEEP",
                value: nil,
                unit: "",
                detail: nil,
                emptyText: sleepEmptyText,
                tone: Theme.macroFiber,
                valueColor: Theme.textPrimary
            )
        }
        return BodySummaryCardPayload(
            label: "SLEEP",
            value: String(format: "%.1f", hours),
            unit: "h",
            detail: "last night",
            emptyText: sleepEmptyText,
            tone: Theme.macroFiber,
            valueColor: Theme.textPrimary
        )
    }

    static func readinessPayload(recoveryScore: Int, hrvMs: Double) -> BodySummaryCardPayload {
        guard recoveryScore > 0 else {
            return BodySummaryCardPayload(
                label: "READINESS",
                value: nil,
                unit: "",
                detail: nil,
                emptyText: readinessEmptyText,
                tone: Theme.macroProtein,
                valueColor: Theme.textPrimary
            )
        }
        let detail: String? = hrvMs > 0 ? "\(Int(hrvMs.rounded()))ms HRV" : nil
        return BodySummaryCardPayload(
            label: "READINESS",
            value: "\(recoveryScore)",
            unit: "",
            detail: detail,
            emptyText: readinessEmptyText,
            tone: Theme.macroProtein,
            valueColor: Theme.textPrimary
        )
    }

    /// Goal-aware color for the WEIGHT value. Returns `Theme.deficit` (green)
    /// when the weekly rate moves the user toward their goal direction,
    /// `Theme.surplus` (red) when against, and `Theme.textPrimary` (neutral)
    /// when the direction is `.maintain`, the rate is missing/zero, or no
    /// goal exists.
    static func goalAlignedColor(
        weeklyRateKg: Double?,
        goalDirection: GoalDirection
    ) -> Color {
        guard let rate = weeklyRateKg, rate.isFinite, abs(rate) > 0.001 else {
            return Theme.textPrimary
        }
        switch goalDirection {
        case .lose:
            return rate < 0 ? Theme.deficit : Theme.surplus
        case .gain:
            return rate > 0 ? Theme.deficit : Theme.surplus
        case .maintain, .none:
            return Theme.textPrimary
        }
    }
}

/// User's intended weight direction. Mapped from `WeightGoal.isLosing(...)`
/// at the call site; broken out so the WEIGHT payload's color flip is
/// testable without a stored `WeightGoal` fixture.
enum GoalDirection: Equatable {
    case lose
    case gain
    case maintain
    case none
}

#if DEBUG
#Preview("BodySummaryCardsRow — populated") {
    let payloads = BodySummaryCardsRow.payloads(
        weightKg: 75.0,
        weeklyRateKg: -0.30,
        sleepHours: 7.4,
        recoveryScore: 82,
        hrvMs: 65,
        goalDirection: .lose
    )
    return BodySummaryCardsRow(payloads: payloads, onTapBody: {})
        .padding()
        .background(Theme.background)
}

#Preview("BodySummaryCardsRow — all empty") {
    let payloads = BodySummaryCardsRow.payloads(
        weightKg: nil,
        weeklyRateKg: nil,
        sleepHours: 0,
        recoveryScore: 0,
        hrvMs: 0,
        goalDirection: .none
    )
    return BodySummaryCardsRow(payloads: payloads, onTapBody: {})
        .padding()
        .background(Theme.background)
}
#endif
