import SwiftUI
import DriftCore

/// Anatomical muscle-highlight views (#929) — renders the body model ported
/// from react-native-body-highlighter (MIT, © 2022 ELABBASSI Hicham; see
/// `BodyDiagram`). Replaces the old rectangles-and-ellipses body map.

// MARK: - Body renderer

/// One body view (front or back) with per-muscle fills, drawn in a single
/// Canvas — the model is ~80 paths per side; never make each path a view.
struct MuscleBodyView: View {
    var gender: BodyDiagram.Gender = .male
    let side: BodyDiagram.Side
    /// Library slugs → strong highlight.
    var primarySlugs: Set<String> = []
    /// Library slugs → soft highlight.
    var secondarySlugs: Set<String> = []
    /// Explicit per-slug colors (recovery map) — wins over primary/secondary.
    var slugColors: [String: Color] = [:]

    var body: some View {
        Canvas { ctx, size in
            guard let model = BodyDiagram.model(gender: gender, side: side) else { return }
            let scale = min(size.width / model.viewBox.width,
                            size.height / model.viewBox.height)
            let dx = (size.width - model.viewBox.width * scale) / 2
            let dy = (size.height - model.viewBox.height * scale) / 2
            ctx.translateBy(x: dx, y: dy)
            ctx.scaleBy(x: scale, y: scale)

            for (slug, paths) in model.muscles {
                let color = slugColors[slug]
                    ?? (primarySlugs.contains(slug) ? Theme.accent
                        : secondarySlugs.contains(slug) ? Theme.accent.opacity(0.35)
                        : Theme.textTertiary.opacity(0.28))
                for p in paths {
                    ctx.fill(Path(p), with: .color(color))
                }
            }
            for p in model.outline {
                ctx.stroke(Path(p), with: .color(Theme.textTertiary.opacity(0.45)),
                           lineWidth: 2 / scale)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)  // the host card provides the text
    }

    private var aspectRatio: CGFloat {
        guard let model = BodyDiagram.model(gender: gender, side: side),
              model.viewBox.height > 0 else { return 0.5 }
        return model.viewBox.width / model.viewBox.height
    }
}

// MARK: - Exercise muscle card

/// Front + back anatomical panels highlighting an exercise's worked muscles,
/// with a plain-English line about the top primary muscle (reference design:
/// diagram beside "Lats — pulls arms down & toward you").
struct MuscleHighlightCard: View {
    let primaryMuscles: [String]
    let secondaryMuscles: [String]

    private var primarySlugs: Set<String> {
        Set(primaryMuscles.flatMap(BodyDiagram.librarySlugs(forDriftMuscle:)))
    }
    private var secondarySlugs: Set<String> {
        Set(secondaryMuscles.flatMap(BodyDiagram.librarySlugs(forDriftMuscle:)))
            .subtracting(primarySlugs)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                panel(.front)
                panel(.back)
            }
            .frame(height: 190)

            if let lead = primaryMuscles.first, let info = MuscleInfo.info(for: lead) {
                VStack(spacing: 2) {
                    Text(info.displayName)
                        .font(.caption.weight(.bold))
                    Text(info.function)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func panel(_ side: BodyDiagram.Side) -> some View {
        VStack(spacing: 4) {
            MuscleBodyView(side: side,
                           primarySlugs: primarySlugs,
                           secondarySlugs: secondarySlugs)
            Text(side == .front ? "Front" : "Back")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if !primaryMuscles.isEmpty {
            parts.append("Works \(primaryMuscles.map(\.capitalized).joined(separator: ", "))")
        }
        if !secondaryMuscles.isEmpty {
            parts.append("also \(secondaryMuscles.map(\.capitalized).joined(separator: ", "))")
        }
        return parts.isEmpty ? "Muscle diagram" : parts.joined(separator: "; ")
    }
}

#Preview("Lats (rows)") {
    MuscleHighlightCard(primaryMuscles: ["lats"], secondaryMuscles: ["biceps", "middle back"])
        .padding()
        .background(Theme.background)
}

#Preview("Bench (chest)") {
    MuscleHighlightCard(primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"])
        .padding()
        .background(Theme.background)
}
