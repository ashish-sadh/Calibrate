import SwiftUI
import DriftCore

/// Anatomical muscle-highlight views (#929) — renders the body model ported
/// from react-native-body-highlighter (MIT, © 2022 ELABBASSI Hicham; see
/// `BodyDiagram`). Single-source for iOS and Android (#1064): SkipUI has no
/// `Canvas`, so the model's ~80 regions per side are merged into one SwiftUI
/// `Path` per fill color (≤ a handful of shape views) — never one view per
/// region.

// MARK: - Body renderer

/// One body view (front or back) with per-muscle fills.
struct MuscleBodyView: View {
    /// Defaults to the profile-derived figure so every call site (recovery
    /// map, exercise diagrams) shows the user's own body type.
    var gender: BodyDiagram.Gender = BodyDiagram.userGender
    let side: BodyDiagram.Side
    /// Library slugs → strong highlight.
    var primarySlugs: Set<String> = []
    /// Library slugs → soft highlight.
    var secondarySlugs: Set<String> = []
    /// Explicit per-slug colors (recovery map) — wins over primary/secondary.
    var slugColors: [String: Color] = [:]
    /// Stable signature for `slugColors` — `Color` has no cross-platform
    /// introspection, so any caller passing explicit colors must also pass a
    /// string that changes whenever those colors would. Inert on iOS; on
    /// Android it keys the built-path cache below.
    var colorSignature: String = ""
    /// Android-only container box: SkipUI's GeometryReader invalidates on
    /// global POSITION (onGloballyPositionedInRoot), so every scroll frame
    /// recomposes its content across the JNI bridge (#1074). The figure only
    /// needs a size — callers that know their box pass it here and Android
    /// skips GeometryReader entirely (the fill math aspect-fits and centers
    /// inside the box exactly like the GeometryReader path). Inert on iOS.
    var fitBox: CGSize? = nil

    var body: some View {
        #if os(Android)
        // drawingGroup → Compose CompositingStrategy.Offscreen: the figure
        // rasterizes ONCE into a cached layer texture. Without it, swiftshader
        // (and the Pixel 2's GPU) re-rasterizes ~640 antialiased vector paths
        // on every scroll frame — measured 45-115ms/frame of pure raster time
        // on the workout tab (#1074).
        if let box = fitBox {
            figure(in: box)
                .frame(width: box.width, height: box.height)
                .drawingGroup()
                .accessibilityHidden(true)
        } else {
            GeometryReader { geo in
                figure(in: geo.size)
            }
            .drawingGroup()
            .aspectRatio(aspectRatio, contentMode: .fit)
            .accessibilityHidden(true)
        }
        #else
        GeometryReader { geo in
            figure(in: geo.size)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)  // the host card provides the text
        #endif
    }

    #if os(Android)
    // Built-path cache (#1074): constructing a figure's merged Paths crosses
    // the JNI bridge ~20k times (one hop per path command). Rebuilding on
    // every body evaluation froze the workout tab for 20+ seconds per scroll
    // (Choreographer: 1275 skipped frames). Each distinct figure builds once
    // per process and is reused; the app renders only a handful of them.
    struct BuiltLayer: Identifiable {
        let id: String
        let color: Color
        let path: Path
    }
    struct BuiltFigure {
        let layers: [BuiltLayer]
        let outline: Path
    }
    static var figureCache: [String: BuiltFigure] = [:]
    static let figureCacheLock = NSLock()

    @ViewBuilder
    private func figure(in size: CGSize) -> some View {
        if let built = builtFigure(in: size) {
            ZStack {
                ForEach(built.layers) { layer in
                    layer.path.fill(layer.color)
                }
                built.outline.stroke(Theme.textTertiary.opacity(0.45), lineWidth: 2)
            }
        }
    }

    private func builtFigure(in size: CGSize) -> BuiltFigure? {
        guard let model = BodyDiagram.model(gender: gender, side: side),
              model.viewBoxWidth > 0, model.viewBoxHeight > 0,
              size.width > 0, size.height > 0 else { return nil }
        let key = "\(gender.rawValue)|\(side.rawValue)|\(Int(size.width))x\(Int(size.height))"
            + "|p:\(primarySlugs.sorted().joined(separator: ","))"
            + "|s:\(secondarySlugs.sorted().joined(separator: ","))"
            + "|c:\(colorSignature)"
        Self.figureCacheLock.lock()
        defer { Self.figureCacheLock.unlock() }
        if let cached = Self.figureCache[key] { return cached }
        let vw = CGFloat(model.viewBoxWidth)
        let vh = CGFloat(model.viewBoxHeight)
        let scale = min(size.width / vw, size.height / vh)
        let dx = (size.width - vw * scale) / 2
        let dy = (size.height - vh * scale) / 2
        let layers = fillLayers(model).map { layer in
            BuiltLayer(id: layer.key, color: layer.color,
                       path: Self.path(layer.paths, scale: scale, dx: dx, dy: dy))
        }
        let built = BuiltFigure(
            layers: layers,
            outline: Self.path(model.outline, scale: scale, dx: dx, dy: dy))
        if Self.figureCache.count > 64 { Self.figureCache.removeAll() }
        Self.figureCache[key] = built
        return built
    }
    #else
    @ViewBuilder
    private func figure(in size: CGSize) -> some View {
        if let model = BodyDiagram.model(gender: gender, side: side),
           model.viewBoxWidth > 0, model.viewBoxHeight > 0,
           size.width > 0, size.height > 0 {
            let vw = CGFloat(model.viewBoxWidth)
            let vh = CGFloat(model.viewBoxHeight)
            let scale = min(size.width / vw, size.height / vh)
            let dx = (size.width - vw * scale) / 2
            let dy = (size.height - vh * scale) / 2
            ZStack {
                ForEach(fillLayers(model), id: \.key) { layer in
                    Self.path(layer.paths, scale: scale, dx: dx, dy: dy)
                        .fill(layer.color)
                }
                Self.path(model.outline, scale: scale, dx: dx, dy: dy)
                    .stroke(Theme.textTertiary.opacity(0.45), lineWidth: 2)
            }
        }
    }
    #endif

    private struct FillLayer {
        let key: String
        let color: Color
        let paths: [SVGPath]
    }

    /// Groups the model's regions by resolved fill color. Regions are
    /// anatomically disjoint, so merging them into one path per color is
    /// visually identical to per-region fills.
    private func fillLayers(_ model: BodyDiagram.Model) -> [FillLayer] {
        var neutral: [SVGPath] = [], primary: [SVGPath] = [], secondary: [SVGPath] = []
        var explicit: [FillLayer] = []
        for (slug, paths) in model.muscles.sorted(by: { $0.key < $1.key }) {
            if let color = slugColors[slug] {
                explicit.append(FillLayer(key: "slug-\(slug)", color: color, paths: paths))
            } else if primarySlugs.contains(slug) {
                primary += paths
            } else if secondarySlugs.contains(slug) {
                secondary += paths
            } else {
                neutral += paths
            }
        }
        var layers = [FillLayer(key: "neutral", color: Theme.textTertiary.opacity(0.28), paths: neutral)]
        if !secondary.isEmpty {
            layers.append(FillLayer(key: "secondary", color: Theme.accent.opacity(0.35), paths: secondary))
        }
        if !primary.isEmpty {
            layers.append(FillLayer(key: "primary", color: Theme.accent, paths: primary))
        }
        layers += explicit
        return layers.filter { !$0.paths.isEmpty }
    }

    private static func path(_ svgPaths: [SVGPath], scale: CGFloat, dx: CGFloat, dy: CGFloat) -> Path {
        var p = Path()
        for sp in svgPaths {
            for cmd in sp.commands {
                switch cmd {
                case .move(let x, let y):
                    p.move(to: CGPoint(x: CGFloat(x) * scale + dx, y: CGFloat(y) * scale + dy))
                case .line(let x, let y):
                    p.addLine(to: CGPoint(x: CGFloat(x) * scale + dx, y: CGFloat(y) * scale + dy))
                case .curve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                    p.addCurve(to: CGPoint(x: CGFloat(x) * scale + dx, y: CGFloat(y) * scale + dy),
                               control1: CGPoint(x: CGFloat(c1x) * scale + dx, y: CGFloat(c1y) * scale + dy),
                               control2: CGPoint(x: CGFloat(c2x) * scale + dx, y: CGFloat(c2y) * scale + dy))
                case .close:
                    p.closeSubpath()
                }
            }
        }
        return p
    }

    private var aspectRatio: CGFloat {
        guard let model = BodyDiagram.model(gender: gender, side: side),
              model.viewBoxHeight > 0 else { return 0.5 }
        return CGFloat(model.viewBoxWidth / model.viewBoxHeight)
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
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        #if !os(Android)
        // SkipUI declares accessibilityElement(children:) unavailable.
        .accessibilityElement(children: .ignore)
        #endif
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private func panel(_ side: BodyDiagram.Side) -> some View {
        VStack(spacing: 4) {
            // Explicit width ≈ natural fit at the 190pt row — see the same
            // note in BodyMapView (Compose treats the figure as greedy).
            MuscleBodyView(side: side,
                           primarySlugs: primarySlugs,
                           secondarySlugs: secondarySlugs,
                           fitBox: CGSize(width: 88, height: 168))
                .frame(width: 88)
            Text(side == .front ? "Front" : "Back")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
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
