import SwiftUI
import DriftCore
#if canImport(UIKit)
import UIKit
#endif

// Platform gates in this file: `#if canImport(UIKit)` = the iOS app target
// (sync UIImage decode, exactly the pre-#1064 behavior). The `#else` branch
// (AsyncImage) serves BOTH the Android target and skipstone's macOS host
// pass, which compiles SharedUICopy without UIKit. `#if os(Android)` only
// wraps the Bundle.module lookup, which exists solely in the Skip module.

// MARK: - Pose asset lookup

/// Locates a bundled pose photo ("<base>-0/-1.heic", #929). iOS ships
/// Drift/ExercisePoses as an "ExercisePoses/" subdirectory of the app bundle;
/// Android mirrors the identical pack into this module's resources
/// (scripts/android-sync-core-resources.sh), where Bundle.module returns a
/// jar: URL that SkipUI's AsyncImage (Coil) knows how to load.
func poseAssetURL(base: String, pose: Int) -> URL? {
    #if os(Android)
    return Bundle.module.url(forResource: "\(base)-\(pose)", withExtension: "heic",
                             subdirectory: "ExercisePoses")
        ?? Bundle.module.url(forResource: "ExercisePoses/\(base)-\(pose)", withExtension: "heic")
    #else
    return Bundle.main.url(forResource: "\(base)-\(pose)", withExtension: "heic",
                           subdirectory: "ExercisePoses")
    #endif
}

// MARK: - Exercise Thumbnail

struct ExerciseThumbnail: View {
    let info: ExerciseDatabase.ExerciseInfo?
    let size: CGFloat

    // #929: the remote imageUrl AsyncImage is gone — it fetched from the
    // network at render time (privacy + scroll jank). Rows now show the
    // BUNDLED start-pose photo (on-disk HEIC, ~6KB — no network, no jank);
    // glyph fallback for the few exercises without one. The old all-coral
    // glyph tiles read as a wall of identical pink squares (design pass
    // 2026-07-09).
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let pose = poseImage {
                Image(uiImage: pose)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color.white)
            } else {
                fallback
                    .frame(width: size, height: size)
            }
            #else
            if let url = poseURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white
                }
                .frame(width: size, height: size)
                .background(Color.white)
            } else {
                fallback
                    .frame(width: size, height: size)
            }
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18)
            .strokeBorder(Theme.separator, lineWidth: 0.5))
    }

    private var poseURL: URL? {
        guard let base = ExercisePoses.assetBaseName(fromImageUrl: info?.imageUrl) else { return nil }
        return poseAssetURL(base: base, pose: 0)
    }

    #if canImport(UIKit)
    private var poseImage: UIImage? {
        guard let url = poseURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    #endif

    private var fallback: some View {
        Image(systemName: sym(bodyPartIcon(info?.bodyPart ?? "")))
            .font(.system(size: size * 0.38))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cardBackgroundElevated)
    }
}

// MARK: - Pose Crossfade

/// The "GIF" that isn't a GIF (#929): a ~0.9s ease-in-out crossfade between
/// an exercise's start and end pose photos. Reads as a demo animation at the
/// cost of two decoded bitmaps — zero per-frame decode, no video player, no
/// network (the HEIC pack ships in-bundle from free-exercise-db, public
/// domain). Returns nil when the exercise has no pose assets so callers
/// fall back to the muscle diagram — never a broken frame.
struct PoseCrossfadeView: View {
    #if canImport(UIKit)
    let start: UIImage
    let end: UIImage
    #else
    let startURL: URL
    let endURL: URL
    #endif
    @State var showingEnd = false

    /// Fails (nil) unless BOTH poses are bundled — a single still would
    /// "animate" into nothing.
    init?(imageUrl: String?) {
        guard let base = ExercisePoses.assetBaseName(fromImageUrl: imageUrl),
              let startURL = poseAssetURL(base: base, pose: 0),
              let endURL = poseAssetURL(base: base, pose: 1) else { return nil }
        #if canImport(UIKit)
        guard let s = UIImage(contentsOfFile: startURL.path),
              let e = UIImage(contentsOfFile: endURL.path) else { return nil }
        start = s
        end = e
        #else
        self.startURL = startURL
        self.endURL = endURL
        #endif
    }

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            Image(uiImage: start)
                .resizable().scaledToFit()
            Image(uiImage: end)
                .resizable().scaledToFit()
                .opacity(showingEnd ? 1 : 0)
            #else
            AsyncImage(url: startURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.white
            }
            AsyncImage(url: endURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .opacity(showingEnd ? 1 : 0)
            #endif
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                showingEnd = true
            }
        }
        .accessibilityLabel("Exercise demonstration: start and end position")
    }
}

// MARK: - Exercise chips (browser + picker rows)

func muscleChip(_ bodyPart: String) -> some View {
    HStack(spacing: 2) {
        Image(systemName: sym(muscleIcon(bodyPart))).font(.system(size: 8))
        Text(bodyPart).font(.system(size: Theme.FontSize.nano))
    }
    .padding(.horizontal, 6).padding(.vertical, 2)
    // Quiet gray — 100 coral chips per screen fought the new photo
    // thumbnails (design pass 2026-07-10); coral stays CTA-only.
    .background(Theme.pillBackground, in: Capsule())
    .foregroundStyle(Theme.accent)
}

func equipmentChip(_ equipment: String) -> some View {
    HStack(spacing: 2) {
        equipmentGlyph(equipment, tint: Theme.textSecondary)
        Text(equipment.capitalized).font(.system(size: Theme.FontSize.nano))
    }
    .padding(.horizontal, 6).padding(.vertical, 2)
    .background(Color.secondary.opacity(0.1), in: Capsule())
    .foregroundStyle(Theme.textSecondary)
}

func bodyPartIcon(_ bodyPart: String) -> String {
    switch bodyPart.lowercased() {
    case "chest": return "figure.strengthtraining.traditional"
    case "back": return "figure.rowing"
    case "legs": return "figure.run"
    case "shoulders": return "figure.boxing"
    case "arms": return "figure.cooldown"
    case "core": return "figure.core.training"
    default: return "figure.mixed.cardio"
    }
}

func muscleIcon(_ bodyPart: String) -> String {
    bodyPartIcon(bodyPart)
}

/// Equipment chip glyph. Barbell/dumbbell can't go through `sym()` on Android:
/// skip-ui maps `dumbbell` to `list.bullet`, so a barbell exercise rendered a
/// BULLET LIST — a different object, the failure directive 0a forbids. Those
/// two draw `DumbbellShape` (DumbbellGlyph.swift) instead; everything else
/// keeps its mapped Material glyph.
@ViewBuilder func equipmentGlyph(_ equipment: String, tint: Color) -> some View {
    #if os(Android)
    let name = equipmentIcon(equipment)
    if name == "dumbbell" || name == "dumbbell.fill" {
        DumbbellShape().fill(tint).frame(width: 8, height: 8)
    } else {
        Image(systemName: sym(name)).font(.system(size: 8))
    }
    #else
    Image(systemName: sym(equipmentIcon(equipment))).font(.system(size: 8))
    #endif
}

func equipmentIcon(_ equipment: String) -> String {
    switch equipment.lowercased() {
    case "barbell", "e-z curl bar": return "dumbbell.fill"
    case "dumbbell": return "dumbbell"
    case "cable": return "link"
    case "machine": return "gearshape"
    case "body only": return "figure.stand"
    case "kettlebells": return "circle.fill"
    case "bands": return "arrow.left.and.right"
    case "exercise ball", "medicine ball": return "circle.dotted"
    default: return "wrench.and.screwdriver"
    }
}
