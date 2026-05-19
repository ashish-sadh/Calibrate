import SwiftUI
import DriftCore

/// V6 Body tile — small KPI card with a colored dot, label, value+unit, and
/// a delta sublabel. Three of these sit in a row under "Body" on the Dashboard,
/// matching anatomy step 5 in `Docs/design-references/v6-2026-05-14/v6/v6-today.jsx`.
///
/// The view is intentionally dumb: all formatting (rate signs, unit
/// conversion, "--" fallbacks) happens at the call site so tests can lock the
/// formatter independently of the rendering layer.
///
/// The optional `onAdd` "+" button is for the Weight tile only — Sleep and
/// Readiness don't have a one-tap log path. Tapping the "+" must NEVER bubble
/// up to `onTap` (the body recompute handler that opens the detail view), so
/// the button calls `onAdd` with a `simultaneousGesture`-free `Button` placed
/// outside the tap surface and the outer Button explicitly avoids covering it.
struct V6BodyTile: View {
    let label: String
    let value: String
    let unit: String
    let delta: String?
    let deltaLabel: String
    let tone: Color
    let onTap: () -> Void
    var onAdd: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tone)
                            .frame(width: 7, height: 7)
                        Text(label.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        // Reserve space for the "+" button so its hit-target
                        // doesn't visually clip the label even though it lives
                        // in the outer ZStack overlay. `.allowsHitTesting(false)`
                        // so a stray tap on the placeholder routes to the outer
                        // tile, not into a no-op transparent area.
                        if onAdd != nil {
                            Color.clear
                                .frame(width: 22, height: 22)
                                .allowsHitTesting(false)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    // Always render an HStack with one or two text runs so
                    // mixed populated/empty tiles in the same row keep equal
                    // intrinsic heights. Populated → "delta deltaLabel";
                    // empty → just deltaLabel in the tertiary color.
                    HStack(spacing: 4) {
                        if let delta {
                            Text(delta)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(deltaLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Open \(label.lowercased()) details")

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(width: 22, height: 22)
                        .background(Theme.textPrimary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log \(label.lowercased())")
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [label]
        if value == "--" {
            parts.append("no data")
        } else {
            parts.append(unit.isEmpty ? value : "\(value) \(unit)")
        }
        if let delta {
            parts.append("\(delta) \(deltaLabel)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Pre-formatted payload for one tile. Pure value type — the formatters that
/// build it (e.g. `V6BodyTile.weight(...)`) are static so tests can pin them
/// without instantiating a SwiftUI view.
struct V6BodyTilePayload: Equatable {
    var label: String
    var value: String
    var unit: String
    var delta: String?
    var deltaLabel: String
}

extension V6BodyTile {
    /// Builds the Weight tile payload from raw kg + kg/week. Locale-aware via
    /// `Preferences.weightUnit`. Returns "--" with an empty delta when no
    /// weight has ever been logged, so the Dashboard renders a clean empty
    /// state instead of "0.0".
    ///
    /// Defensively guards non-finite or non-positive kg so a corrupt entry
    /// can't render "-165.3 lbs" on the dashboard. Surfaces a "stale" hint
    /// in the deltaLabel when `isStale` is true so the user knows the weekly
    /// rate is based on outdated data — same affordance the legacy
    /// Weight+Trend card had via a yellow "Tap to update" line.
    static func weightPayload(
        weightKg: Double?,
        weeklyRateKg: Double?,
        isStale: Bool = false
    ) -> V6BodyTilePayload {
        let unit = Preferences.weightUnit
        guard let kg = weightKg, kg.isFinite, kg > 0 else {
            return V6BodyTilePayload(
                label: "Weight",
                value: "--",
                unit: unit.displayName,
                delta: nil,
                deltaLabel: "no data"
            )
        }
        let valueDisplay = unit.convert(fromKg: kg)
        let deltaStr: String?
        if let rate = weeklyRateKg, rate.isFinite {
            let display = unit.convert(fromKg: rate)
            deltaStr = String(format: "%+.2f %@/wk", display, unit.displayName)
        } else {
            deltaStr = nil
        }
        let baseDeltaLabel = deltaStr == nil ? "log to track" : "this wk"
        return V6BodyTilePayload(
            label: "Weight",
            value: String(format: "%.1f", valueDisplay),
            unit: unit.displayName,
            delta: deltaStr,
            deltaLabel: isStale && deltaStr != nil ? "\(baseDeltaLabel) · stale" : baseDeltaLabel
        )
    }

    /// Builds the Sleep tile payload from hours. Zero hours = no data → "--".
    static func sleepPayload(hours: Double) -> V6BodyTilePayload {
        if hours <= 0 || !hours.isFinite {
            return V6BodyTilePayload(
                label: "Sleep",
                value: "--",
                unit: "h",
                delta: nil,
                deltaLabel: "no data"
            )
        }
        return V6BodyTilePayload(
            label: "Sleep",
            value: String(format: "%.1f", hours),
            unit: "h",
            delta: "last night",
            deltaLabel: ""
        )
    }

    /// Builds the Readiness tile payload from recovery score + HRV. Score 0 =
    /// no data → "--". When score is present, the HRV value is shown as the
    /// delta line so the user gets a quick at-a-glance vital alongside the
    /// score.
    static func readinessPayload(recoveryScore: Int, hrvMs: Double) -> V6BodyTilePayload {
        if recoveryScore <= 0 {
            return V6BodyTilePayload(
                label: "Readiness",
                value: "--",
                unit: "",
                delta: nil,
                deltaLabel: "no data"
            )
        }
        let delta: String? = hrvMs > 0 ? "\(Int(hrvMs))ms HRV" : nil
        return V6BodyTilePayload(
            label: "Readiness",
            value: "\(recoveryScore)",
            unit: "",
            delta: delta,
            deltaLabel: delta == nil ? "score" : ""
        )
    }
}

#if DEBUG
#Preview("V6BodyTile row") {
    HStack(spacing: 8) {
        V6BodyTile(
            label: "Weight", value: "165.4", unit: "lbs",
            delta: "+0.30 lbs/wk", deltaLabel: "this wk",
            tone: Theme.V6.ringMove,
            onTap: {}, onAdd: {}
        )
        V6BodyTile(
            label: "Sleep", value: "7.5", unit: "h",
            delta: "last night", deltaLabel: "",
            tone: Theme.V6.ringStand,
            onTap: {}
        )
        V6BodyTile(
            label: "Readiness", value: "82", unit: "",
            delta: "65ms HRV", deltaLabel: "",
            tone: Theme.V6.ringEx,
            onTap: {}
        )
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("V6BodyTile empty states") {
    HStack(spacing: 8) {
        V6BodyTile(
            label: "Weight", value: "--", unit: "lbs",
            delta: nil, deltaLabel: "no data",
            tone: Theme.V6.ringMove,
            onTap: {}, onAdd: {}
        )
        V6BodyTile(
            label: "Sleep", value: "--", unit: "h",
            delta: nil, deltaLabel: "no data",
            tone: Theme.V6.ringStand,
            onTap: {}
        )
        V6BodyTile(
            label: "Readiness", value: "--", unit: "",
            delta: nil, deltaLabel: "no data",
            tone: Theme.V6.ringEx,
            onTap: {}
        )
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}
#endif
