import Testing
@testable import DriftCore

@Suite struct MeasurementSiteMetadataTests {
    @Test func displayOrderContainsEverySiteExactlyOnce() {
        #expect(MeasurementSite.displayOrder == [
            .neck, .shoulders, .chest,
            .leftBicep, .rightBicep,
            .leftForearm, .rightForearm,
            .waist, .hips,
            .leftThigh, .rightThigh,
            .leftCalf, .rightCalf,
        ])
        #expect(Set(MeasurementSite.displayOrder).count == MeasurementSite.allCases.count)
    }

    @Test func displayNamesAndGroupsCoverEverySite() {
        let expected: [(MeasurementSite, String, MeasurementSite.Group)] = [
            (.neck, "Neck", .upper),
            (.shoulders, "Shoulders", .upper),
            (.chest, "Chest", .upper),
            (.leftBicep, "Left Bicep", .upper),
            (.rightBicep, "Right Bicep", .upper),
            (.leftForearm, "Left Forearm", .upper),
            (.rightForearm, "Right Forearm", .upper),
            (.waist, "Waist", .core),
            (.hips, "Hips", .core),
            (.leftThigh, "Left Thigh", .lower),
            (.rightThigh, "Right Thigh", .lower),
            (.leftCalf, "Left Calf", .lower),
            (.rightCalf, "Right Calf", .lower),
        ]

        for (site, displayName, group) in expected {
            #expect(site.displayName == displayName)
            #expect(site.group == group)
        }
        #expect(expected.map(\.0) == MeasurementSite.displayOrder)
    }

    @Test func mirrorsAreSymmetricAndLimitedToLimbPairs() {
        let expectedPairs: [(MeasurementSite, MeasurementSite)] = [
            (.leftBicep, .rightBicep),
            (.leftForearm, .rightForearm),
            (.leftThigh, .rightThigh),
            (.leftCalf, .rightCalf),
        ]

        for (left, right) in expectedPairs {
            #expect(left.mirror == right)
            #expect(right.mirror == left)
            #expect(left.group == right.group)
        }

        let unpaired: [MeasurementSite] = [.neck, .shoulders, .chest, .waist, .hips]
        #expect(unpaired.allSatisfy { $0.mirror == nil })
    }

    @Test func guidanceAndHighlightsCoverEverySite() {
        for site in MeasurementSite.allCases {
            #expect(!site.tapePlacement.isEmpty)
            #expect(!site.highlightMuscles.isEmpty)
        }

        #expect(MeasurementSite.leftBicep.tapePlacement == MeasurementSite.rightBicep.tapePlacement)
        #expect(MeasurementSite.leftForearm.tapePlacement == MeasurementSite.rightForearm.tapePlacement)
        #expect(MeasurementSite.leftThigh.tapePlacement == MeasurementSite.rightThigh.tapePlacement)
        #expect(MeasurementSite.leftCalf.tapePlacement == MeasurementSite.rightCalf.tapePlacement)

        #expect(MeasurementSite.neck.highlightMuscles == ["neck"])
        #expect(MeasurementSite.shoulders.highlightMuscles == ["shoulders"])
        #expect(MeasurementSite.chest.highlightMuscles == ["chest"])
        #expect(MeasurementSite.leftBicep.highlightMuscles == ["biceps"])
        #expect(MeasurementSite.leftForearm.highlightMuscles == ["forearms"])
        #expect(MeasurementSite.waist.highlightMuscles == ["abdominals"])
        #expect(MeasurementSite.hips.highlightMuscles == ["glutes"])
        #expect(MeasurementSite.leftThigh.highlightMuscles == ["quadriceps"])
        #expect(MeasurementSite.leftCalf.highlightMuscles == ["calves"])
    }

    @Test func measuringTipsArePresentAndDistinct() {
        #expect(MeasurementSite.measuringTips.count == 4)
        #expect(MeasurementSite.measuringTips.allSatisfy { !$0.isEmpty })
        #expect(Set(MeasurementSite.measuringTips).count == MeasurementSite.measuringTips.count)
    }
}
