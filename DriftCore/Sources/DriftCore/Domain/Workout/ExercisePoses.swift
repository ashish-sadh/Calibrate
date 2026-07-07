import Foundation

/// Maps a catalog exercise to its bundled start/end pose photos (#929).
///
/// The pose pack (Drift/ExercisePoses, bundle subdirectory "ExercisePoses")
/// is ingested from free-exercise-db (Unlicense/public domain) by
/// `scripts/ingest-exercise-poses.sh`. Every covered catalog entry's
/// `imageUrl` already points into that dataset, so the asset base name is
/// derived from the URL — no name matching, no network:
///   .../free-exercise-db/main/exercises/Front_Squat/0.jpg → "Front_Squat"
/// Bundled files are "<base>-0.heic" (start pose) and "<base>-1.heic" (end).
public enum ExercisePoses {

    /// The asset directory name inside free-exercise-db, or nil when the
    /// exercise has no imageUrl into the dataset (custom exercises, the
    /// few unmatched entries) — callers fall back to the muscle diagram.
    public static func assetBaseName(fromImageUrl imageUrl: String?) -> String? {
        guard let imageUrl,
              let range = imageUrl.range(of: "free-exercise-db/main/exercises/") else { return nil }
        let tail = imageUrl[range.upperBound...]
        guard let slash = tail.firstIndex(of: "/") else { return nil }
        let dir = tail[..<slash]
        return dir.isEmpty ? nil : String(dir)
    }
}
