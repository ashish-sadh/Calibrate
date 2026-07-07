import Foundation
import CoreGraphics
import Testing
@testable import DriftCore

/// Tier-0 for the #929 body-diagram port: the bundled model must load, every
/// catalog muscle must resolve to a drawable region (or a documented gap),
/// and the M/L/C/Z parser must honor the extraction contract.
struct BodyDiagramTests {

    // MARK: - Model loading

    @Test func allFourModelsLoad() {
        for gender in BodyDiagram.Gender.allCases {
            for side in BodyDiagram.Side.allCases {
                let model = BodyDiagram.model(gender: gender, side: side)
                #expect(model != nil, "\(gender.rawValue)/\(side.rawValue) missing")
                #expect(model?.outline.isEmpty == false, "\(gender.rawValue)/\(side.rawValue) has no silhouette — muscles would float")
                #expect((model?.muscles.count ?? 0) >= 14)
                #expect(model?.viewBox.width ?? 0 > 0)
            }
        }
    }

    @Test func regionsHaveSaneBounds() {
        // Every muscle path must fit inside its model's viewBox (the
        // extraction normalizes the source's per-view offsets — a path
        // outside the box means the offset math regressed).
        for (key, model) in BodyDiagram.models {
            let box = CGRect(origin: .zero, size: model.viewBox).insetBy(dx: -5, dy: -5)
            for (slug, paths) in model.muscles {
                for p in paths {
                    #expect(box.contains(p.boundingBox), "\(key)/\(slug) path escapes viewBox: \(p.boundingBox)")
                }
            }
        }
    }

    // MARK: - Drift slug coverage

    @Test func everyCatalogMuscleResolvesOrIsDocumented() {
        let catalogMuscles = ["abdominals", "abductors", "adductors", "biceps", "calves",
                              "chest", "forearms", "glutes", "hamstrings", "lats",
                              "lower back", "middle back", "neck", "quadriceps",
                              "shoulders", "traps", "triceps"]
        for muscle in catalogMuscles {
            let slugs = BodyDiagram.librarySlugs(forDriftMuscle: muscle)
            if muscle == "abductors" {
                #expect(slugs.isEmpty, "abductors has no region in the v3 source data — documented gap")
                continue
            }
            #expect(!slugs.isEmpty, "\(muscle) resolves to no library region")
            // The mapped region must exist on the muscle's preferred side.
            let side = BodyDiagram.preferredSide(forDriftMuscle: muscle)
            let model = BodyDiagram.model(gender: .male, side: side)
            for slug in slugs {
                #expect(model?.muscles[slug]?.isEmpty == false,
                        "\(muscle) → \(slug) has no paths on the \(side.rawValue) view")
            }
        }
    }

    @Test func latsAndMiddleBackShareUpperBack() {
        // Accepted v1 approximation — pin it so a future hand-split is deliberate.
        #expect(BodyDiagram.librarySlugs(forDriftMuscle: "lats") == ["upper-back"])
        #expect(BodyDiagram.librarySlugs(forDriftMuscle: "middle back") == ["upper-back"])
    }

    @Test func preferredSideMajorityVote() {
        #expect(BodyDiagram.preferredSide(primaryMuscles: ["lats", "glutes"]) == .back)
        #expect(BodyDiagram.preferredSide(primaryMuscles: ["chest"]) == .front)
        #expect(BodyDiagram.preferredSide(primaryMuscles: ["chest", "lats"]) == .front, "ties go front")
        #expect(BodyDiagram.preferredSide(primaryMuscles: []) == .front)
    }

    @Test func muscleInfoCoversAllSeventeen() {
        let catalogMuscles = ["abdominals", "abductors", "adductors", "biceps", "calves",
                              "chest", "forearms", "glutes", "hamstrings", "lats",
                              "lower back", "middle back", "neck", "quadriceps",
                              "shoulders", "traps", "triceps"]
        for m in catalogMuscles {
            #expect(MuscleInfo.info(for: m) != nil, "no education card for \(m)")
        }
    }

    // MARK: - Parser contract

    @Test func parserHandlesMLCZ() {
        let path = SVGPathParser.parse("M10 10L20 10C25 10 30 15 30 20Z")
        #expect(path != nil)
        #expect(path?.boundingBox.minX == 10)
        #expect(path?.boundingBox.maxX == 30)
    }

    @Test func parserRejectsUnexpectedCommands() {
        // The extraction contract guarantees no arcs/relatives reach Swift.
        #expect(SVGPathParser.parse("M0 0a5 5 0 0110 0") == nil)
        #expect(SVGPathParser.parse("q1 1 2 2") == nil)
        #expect(SVGPathParser.parse("") == nil)
    }

    @Test func parserHandlesNegativeAndDecimalCoordinates() {
        let path = SVGPathParser.parse("M-5.25 3.75L4.5 -2.25Z")
        #expect(path != nil)
        #expect(abs((path?.boundingBox.minX ?? 0) - -5.25) < 0.001)
    }
}
