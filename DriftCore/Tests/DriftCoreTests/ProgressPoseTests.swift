import Testing
@testable import DriftCore

/// Tier 0 — deterministic labels and measurement overlays for progress-photo poses.
@Suite struct ProgressPoseTests {
    @Test func casesHaveStableRawValueOrder() {
        #expect(ProgressPose.allCases == [.front, .back, .left, .right])
        #expect(ProgressPose.allCases.map(\.rawValue) == ["front", "back", "left", "right"])
    }

    @Test func displayAndShortNamesMatchEachPose() {
        let expected: [(ProgressPose, String, String)] = [
            (.front, "Front", "Front"),
            (.back, "Back", "Back"),
            (.left, "Left Side", "Left"),
            (.right, "Right Side", "Right"),
        ]

        for (pose, displayName, shortName) in expected {
            #expect(pose.displayName == displayName)
            #expect(pose.shortName == shortName)
        }
    }

    @Test func relevantSitesMatchVisibleMeasurementsForEachPose() {
        #expect(ProgressPose.front.relevantSites == [.shoulders, .chest, .waist, .hips])
        #expect(ProgressPose.back.relevantSites == [.shoulders, .waist, .hips])
        #expect(ProgressPose.left.relevantSites == [
            .leftBicep, .leftForearm, .waist, .leftThigh, .leftCalf,
        ])
        #expect(ProgressPose.right.relevantSites == [
            .rightBicep, .rightForearm, .waist, .rightThigh, .rightCalf,
        ])
    }

    @Test func sidePosesUseOnlyTheirOwnPairedLimbSites() {
        let leftSites = Set(ProgressPose.left.relevantSites)
        let rightSites = Set(ProgressPose.right.relevantSites)

        #expect(leftSites.contains(.waist))
        #expect(rightSites.contains(.waist))
        #expect(leftSites.intersection(rightSites) == [.waist])
        #expect(!leftSites.contains(.rightBicep))
        #expect(!leftSites.contains(.rightForearm))
        #expect(!leftSites.contains(.rightThigh))
        #expect(!leftSites.contains(.rightCalf))
        #expect(!rightSites.contains(.leftBicep))
        #expect(!rightSites.contains(.leftForearm))
        #expect(!rightSites.contains(.leftThigh))
        #expect(!rightSites.contains(.leftCalf))
    }
}
