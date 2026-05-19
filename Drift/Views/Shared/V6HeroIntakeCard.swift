import SwiftUI

/// V6 Today-tab hero intake card — anatomy step 2 of
/// `Docs/design-references/v6-2026-05-14/v6/v6-today.jsx`.
///
/// Layout (top → bottom, matching the JSX):
///   • Header: "TODAY'S INTAKE" overline + display title ("X kcal left" /
///     "On target") on the left, accent-soft "X% of goal" pill on the right.
///   • V6Rings hero (kcal / protein / fiber concentric) + V6RingLegend.
///   • Hairline divider + 3-column grid: carbs (col 1) / empty (col 2) / fat
///     (col 3), each rendered with `V6LegendItem` so the typography matches
///     the ring legend above pixel-for-pixel.
///
/// Owns nothing visual that isn't in the V6 spec — the surrounding card chrome
/// (`.card()`), tap target, and section header are the caller's responsibility,
/// same convention as `V6Rings` / `V6BodyTile` / `V6QuickLogRow`.
struct V6HeroIntakeCard: View {
    let payload: V6HeroIntakeCardPayload

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 8)

            V6Rings(
                rings: payload.rings,
                size: 180,
                stroke: 16,
                center: AnyView(
                    VStack(spacing: 2) {
                        Text(payload.kcalCenterValue, format: .number)
                            .font(.system(
                                size: payload.kcalCenterFontSize,
                                weight: .bold,
                                design: .rounded
                            ).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text("KCAL")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.textSecondary)
                    }
                )
            )
            .padding(.vertical, 12)

            V6RingLegend(rings: payload.rings)

            hairline
                .padding(.top, 14)
                .padding(.bottom, 12)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 0
            ) {
                V6LegendItem(ring: payload.carbsLegend)
                Color.clear
                V6LegendItem(ring: payload.fatLegend)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY'S INTAKE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.textTertiary)
                Text(payload.titleText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
            Text("\(payload.pctOfGoal)% of goal")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.accentSoft, in: Capsule())
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
    }
}

/// Pure value type — all formatting and color decisions baked in once by
/// `V6HeroIntakeCard.payload(...)` so the view is dumb and tier-1-testable
/// without standing up a SwiftUI host. Same factory-then-render discipline
/// as `V6BodyTilePayload` / `V6MealSlotPayload` / `V6CoachingNudgePayload`.
struct V6HeroIntakeCardPayload: Equatable {
    let titleText: String
    let pctOfGoal: Int
    let rings: [V6Ring]
    let carbsLegend: V6Ring
    let fatLegend: V6Ring
    let kcalCenterValue: Int
    /// Point size for the center kcal label. The view applies `.rounded` +
    /// `.bold` + `.monospacedDigit()` at render time. Stored as a raw
    /// `CGFloat` (not a SwiftUI `Font`) so tier-1 tests can pin the
    /// step-down logic — SwiftUI's `Font` reflects opaquely and would
    /// collapse 22pt / 26pt / 30pt to the same string under introspection.
    let kcalCenterFontSize: CGFloat

    static func == (lhs: V6HeroIntakeCardPayload, rhs: V6HeroIntakeCardPayload) -> Bool {
        lhs.titleText == rhs.titleText
            && lhs.pctOfGoal == rhs.pctOfGoal
            && lhs.kcalCenterValue == rhs.kcalCenterValue
            && lhs.kcalCenterFontSize == rhs.kcalCenterFontSize
            && lhs.rings.map(\.label) == rhs.rings.map(\.label)
            && lhs.carbsLegend.label == rhs.carbsLegend.label
            && lhs.fatLegend.label == rhs.fatLegend.label
    }
}

extension V6HeroIntakeCard {
    /// Builds the hero payload from raw eaten/target macro values.
    ///
    /// Raw doubles (not domain types) so the test can pin formatter behavior
    /// without standing up a `WeightGoal.MacroTargets` / `DailyNutrition`
    /// fixture. Same shape as `V6BodyTile.weightPayload(weightKg:weeklyRateKg:)`.
    ///
    /// NaN / infinite / negative inputs are clamped to 0 — matches V6Rings'
    /// finite-only policy so a corrupt nutrition row can't paint a phantom
    /// arc or crash a `Int(...)` truncation downstream.
    static func payload(
        kcalEaten: Double,
        kcalTarget: Double,
        proteinEatenG: Double,
        proteinTargetG: Double,
        fiberEatenG: Double,
        fiberTargetG: Double,
        carbsEatenG: Double,
        carbsTargetG: Double,
        fatEatenG: Double,
        fatTargetG: Double
    ) -> V6HeroIntakeCardPayload {
        let kEaten = sanitize(kcalEaten)
        let kTarget = sanitize(kcalTarget)
        let pEaten = sanitize(proteinEatenG)
        let pTarget = sanitize(proteinTargetG)
        let fibEaten = sanitize(fiberEatenG)
        let fibTarget = sanitize(fiberTargetG)
        let cEaten = sanitize(carbsEatenG)
        let cTarget = sanitize(carbsTargetG)
        let fatEaten = sanitize(fatEatenG)
        let fatTarget = sanitize(fatTargetG)

        let remaining = kTarget - kEaten
        let titleText: String
        if remaining > 0 {
            titleText = "\(Int(remaining.rounded()).formatted()) kcal left"
        } else {
            titleText = "On target"
        }

        let pctOfGoal: Int = kTarget > 0
            ? Int((kEaten / kTarget * 100).rounded())
            : 0

        let rings: [V6Ring] = [
            V6Ring(
                label: "kcal", unit: "",
                value: kEaten, target: kTarget,
                color: Theme.V6.ringMove,
                trackColor: Theme.V6.ringMoveBg.opacity(0.35)
            ),
            V6Ring(
                label: "protein", unit: "g",
                value: pEaten, target: pTarget,
                color: Theme.V6.ringEx,
                trackColor: Theme.V6.ringExBg.opacity(0.35)
            ),
            V6Ring(
                label: "fiber", unit: "g",
                value: fibEaten, target: fibTarget,
                color: Theme.V6.ringStand,
                trackColor: Theme.V6.ringStandBg.opacity(0.35)
            ),
        ]

        let carbsLegend = V6Ring(
            label: "carbs", unit: "g",
            value: cEaten, target: cTarget,
            color: Theme.V6.ringCarbs,
            trackColor: Theme.V6.ringCarbsBg
        )
        let fatLegend = V6Ring(
            label: "fat", unit: "g",
            value: fatEaten, target: fatTarget,
            color: Theme.V6.ringFat,
            trackColor: Theme.V6.ringFatBg
        )

        let kcalInt = Int(kEaten)
        // Step kcal display font down for 4+ digit days so a high-volume bulk
        // (4500+ kcal) doesn't overflow the inner-ring radius. Mirrors the
        // logic already proven in the predecessor v6RingsHero helper.
        let kcalCenterFontSize: CGFloat
        if kcalInt >= 10_000 {
            kcalCenterFontSize = 22
        } else if kcalInt >= 1_000 {
            kcalCenterFontSize = 26
        } else {
            kcalCenterFontSize = 30
        }

        return V6HeroIntakeCardPayload(
            titleText: titleText,
            pctOfGoal: pctOfGoal,
            rings: rings,
            carbsLegend: carbsLegend,
            fatLegend: fatLegend,
            kcalCenterValue: kcalInt,
            kcalCenterFontSize: kcalCenterFontSize
        )
    }

    private static func sanitize(_ x: Double) -> Double {
        x.isFinite ? max(0, x) : 0
    }
}

#if DEBUG
#Preview("V6HeroIntakeCard — under target") {
    V6HeroIntakeCard(
        payload: V6HeroIntakeCard.payload(
            kcalEaten: 1450, kcalTarget: 2000,
            proteinEatenG: 95, proteinTargetG: 150,
            fiberEatenG: 18, fiberTargetG: 30,
            carbsEatenG: 142, carbsTargetG: 220,
            fatEatenG: 48, fatTargetG: 70
        )
    )
    .padding()
    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    .padding()
    .background(Theme.background)
}

#Preview("V6HeroIntakeCard — over target (overshoot)") {
    V6HeroIntakeCard(
        payload: V6HeroIntakeCard.payload(
            kcalEaten: 2400, kcalTarget: 2000,
            proteinEatenG: 165, proteinTargetG: 150,
            fiberEatenG: 32, fiberTargetG: 30,
            carbsEatenG: 250, carbsTargetG: 220,
            fatEatenG: 78, fatTargetG: 70
        )
    )
    .padding()
    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    .padding()
    .background(Theme.background)
}
#endif
