import SwiftUI
import DriftCore

/// The "GIF" that isn't a GIF (#929): a ~0.9s ease-in-out crossfade between
/// an exercise's start and end pose photos. Reads as a demo animation at the
/// cost of two decoded bitmaps — zero per-frame decode, no video player, no
/// network (the HEIC pack ships in-bundle from free-exercise-db, public
/// domain). Returns nil when the exercise has no pose assets so callers
/// fall back to the muscle diagram — never a broken frame.
struct PoseCrossfadeView: View {
    private let start: UIImage
    private let end: UIImage
    @State private var showingEnd = false

    /// Fails (nil) unless BOTH poses are bundled — a single still would
    /// "animate" into nothing.
    init?(imageUrl: String?) {
        guard let base = ExercisePoses.assetBaseName(fromImageUrl: imageUrl),
              let startURL = Bundle.main.url(forResource: "\(base)-0", withExtension: "heic", subdirectory: "ExercisePoses"),
              let endURL = Bundle.main.url(forResource: "\(base)-1", withExtension: "heic", subdirectory: "ExercisePoses"),
              let s = UIImage(contentsOfFile: startURL.path),
              let e = UIImage(contentsOfFile: endURL.path) else { return nil }
        start = s
        end = e
    }

    var body: some View {
        ZStack {
            Image(uiImage: start)
                .resizable().scaledToFit()
            Image(uiImage: end)
                .resizable().scaledToFit()
                .opacity(showingEnd ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                showingEnd = true
            }
        }
        .accessibilityLabel("Exercise demonstration: start and end position")
    }
}
