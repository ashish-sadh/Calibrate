import Testing
import Foundation
@testable import Drift
@testable import DriftCore

/// Every pose reference must resolve to BOTH bundled HEIC frames — a typo'd
/// or orphaned dir silently degrades to the muscle diagram (PoseCrossfadeView
/// returns nil), which reads as "no demo" and nobody notices. Tier 1 (needs
/// the app bundle's ExercisePoses folder reference).
struct ExercisePoseAssetTests {

    private func bothFramesBundled(_ dir: String) -> Bool {
        Bundle.main.url(forResource: "\(dir)-0", withExtension: "heic", subdirectory: "ExercisePoses") != nil &&
        Bundle.main.url(forResource: "\(dir)-1", withExtension: "heic", subdirectory: "ExercisePoses") != nil
    }

    @Test func everyCatalogImageUrlHasBundledPoses() {
        let all = ExerciseDatabase.all
        #expect(!all.isEmpty)
        for e in all {
            guard let dir = ExercisePoses.assetBaseName(fromImageUrl: e.imageUrl) else { continue }
            #expect(bothFramesBundled(dir), "\(e.name): pose dir '\(dir)' missing from bundle")
        }
    }

    @Test func everyRegistryFedDirHasBundledPoses() {
        for c in DefaultTemplates.customExercises {
            guard let dir = c.fedDir else { continue }
            #expect(bothFramesBundled(dir), "\(c.name): fedDir '\(dir)' missing from bundle")
        }
    }
}
