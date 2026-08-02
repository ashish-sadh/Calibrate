import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the #929 body-diagram port: the bundled model must load, every
/// catalog muscle must resolve to a drawable region (or a documented gap),
/// and the M/L/C/Z parser must honor the extraction contract. Since #1064
/// the model is platform-neutral (command lists, no CoreGraphics) so the
/// same figures render on iOS and Android.
struct BodyDiagramTests {

    // MARK: - Model loading

    @Test func allFourModelsLoad() {
        for gender in BodyDiagram.Gender.allCases {
            for side in BodyDiagram.Side.allCases {
                let model = BodyDiagram.model(gender: gender, side: side)
                #expect(model != nil, "\(gender.rawValue)/\(side.rawValue) missing")
                #expect(model?.outline.isEmpty == false, "\(gender.rawValue)/\(side.rawValue) has no silhouette — muscles would float")
                #expect((model?.muscles.count ?? 0) >= 14)
                #expect(model?.viewBoxWidth ?? 0 > 0)
            }
        }
    }

    @Test func regionsHaveSaneBounds() {
        // Every muscle path must fit inside its model's viewBox (the
        // extraction normalizes the source's per-view offsets — a path
        // outside the box means the offset math regressed).
        for (key, model) in BodyDiagram.models {
            for (slug, paths) in model.muscles {
                for p in paths {
                    let b = p.bounds
                    let contained = b.minX >= -5 && b.minY >= -5
                        && b.maxX <= model.viewBoxWidth + 5
                        && b.maxY <= model.viewBoxHeight + 5
                    #expect(contained, "\(key)/\(slug) path escapes viewBox: \(b)")
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
            // `abductors` was a documented empty gap until 2026-08-02. It isn't
            // one: the abductors ARE glute medius/minimus, which live in the
            // gluteal region — anatomically right, not a fallback. Every
            // catalog muscle now resolves.
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
        #expect(path?.bounds.minX == 10)
        #expect(path?.bounds.maxX == 30)
        #expect(path?.commands == [
            .move(x: 10, y: 10),
            .line(x: 20, y: 10),
            .curve(c1x: 25, c1y: 10, c2x: 30, c2y: 15, x: 30, y: 20),
            .close,
        ])
    }

    @Test func parserRejectsUnexpectedCommands() {
        // The extraction contract guarantees no arcs/relatives reach Swift.
        #expect(SVGPathParser.parse("M0 0a5 5 0 0110 0") == nil)
        #expect(SVGPathParser.parse("q1 1 2 2") == nil)
        #expect(SVGPathParser.parse("") == nil)
        #expect(SVGPathParser.parse("Z") == nil, "a path with no drawable points is not a path")
    }

    @Test func parserHandlesNegativeAndDecimalCoordinates() {
        let path = SVGPathParser.parse("M-5.25 3.75L4.5 -2.25Z")
        #expect(path != nil)
        #expect(abs((path?.bounds.minX ?? 0) - -5.25) < 0.001)
    }

    @Test func boundsIncludeCurveControlPoints() {
        // Same semantics as CGPath.boundingBox, which the viewBox containment
        // guard was originally written against: control points count.
        let path = SVGPathParser.parse("M0 0C50 100 60 -10 10 10")
        #expect(path?.bounds.maxX == 60)
        #expect(path?.bounds.maxY == 100)
        #expect(path?.bounds.minY == -10)
    }
}

// MARK: - Profile-derived figure (2026-07-09 inclusivity)

// Serialized: reads/writes the real drift_tdee_config UserDefaults key.
@Suite(.serialized) struct UserGenderFigureTests {
    @MainActor private func withConfigSex(_ sex: TDEEEstimator.Sex?, _ body: () -> Void) {
        let key = "drift_tdee_config"
        let snapshot = UserDefaults.standard.data(forKey: key)
        defer { UserDefaults.standard.set(snapshot, forKey: key) }
        var config = TDEEEstimator.loadConfig()
        config.sex = sex
        TDEEEstimator.saveConfig(config)
        body()
    }

    @Test @MainActor func femaleProfileGetsFemaleFigure() {
        withConfigSex(.female) { #expect(BodyDiagram.userGender == .female) }
    }

    @Test @MainActor func maleProfileGetsMaleFigure() {
        withConfigSex(.male) { #expect(BodyDiagram.userGender == .male) }
    }

    @Test @MainActor func unsetSexDefaultsToMaleFigure() {
        withConfigSex(nil) { #expect(BodyDiagram.userGender == .male) }
    }

    // The female models must highlight every real muscle the male ones do —
    // a slug regression here would silently un-highlight muscles for women.
    @Test func femaleModelsCoverEveryMappedMuscleSlug() {
        let driftMuscles = ["abdominals", "adductors", "biceps", "calves", "chest",
                            "forearms", "glutes", "hamstrings", "lats", "lower back",
                            "middle back", "neck", "quadriceps", "shoulders", "traps", "triceps"]
        let femaleSlugs = Set(BodyDiagram.model(gender: .female, side: .front)?.muscles.keys.map { $0 } ?? [])
            .union(BodyDiagram.model(gender: .female, side: .back)?.muscles.keys.map { $0 } ?? [])
        for m in driftMuscles {
            for slug in BodyDiagram.librarySlugs(forDriftMuscle: m) {
                #expect(femaleSlugs.contains(slug), "female models missing slug '\(slug)' for \(m)")
            }
        }
    }
}
