import Testing
@testable import DriftCore

@Suite struct ProgressEntryTests {
    private func photo(_ pose: ProgressPose, filename: String) -> ProgressPhoto {
        ProgressPhoto(
            date: "2026-07-21",
            pose: pose,
            filename: filename,
            createdAt: "2026-07-21T12:00:00Z"
        )
    }

    @Test func emptyEntryHasNoPhotosOrPoseMatches() {
        let entry = ProgressEntry(date: "2026-07-21", photos: [], measurement: nil)

        #expect(!entry.hasPhotos)
        for pose in ProgressPose.allCases {
            #expect(entry.photo(for: pose) == nil)
        }
    }

    @Test func photoForPoseSelectsTheExactMatch() {
        let entry = ProgressEntry(
            date: "2026-07-21",
            photos: [
                photo(.right, filename: "right.jpg"),
                photo(.front, filename: "front.jpg"),
                photo(.back, filename: "back.jpg"),
            ],
            measurement: nil
        )

        #expect(entry.hasPhotos)
        #expect(entry.photo(for: .front)?.filename == "front.jpg")
        #expect(entry.photo(for: .back)?.filename == "back.jpg")
        #expect(entry.photo(for: .right)?.filename == "right.jpg")
        #expect(entry.photo(for: .left) == nil)
    }

    @Test func duplicatePoseReturnsTheFirstPhoto() {
        let entry = ProgressEntry(
            date: "2026-07-21",
            photos: [
                photo(.front, filename: "first.jpg"),
                photo(.front, filename: "second.jpg"),
            ],
            measurement: nil
        )

        #expect(entry.photo(for: .front)?.filename == "first.jpg")
    }

    @Test func invalidStoredPoseStillCountsAsAPhotoButDoesNotMatch() {
        var invalidPhoto = photo(.front, filename: "legacy.jpg")
        invalidPhoto.pose = "three-quarter"
        let entry = ProgressEntry(
            date: "2026-07-21",
            photos: [invalidPhoto],
            measurement: nil
        )

        #expect(entry.hasPhotos)
        for pose in ProgressPose.allCases {
            #expect(entry.photo(for: pose) == nil)
        }
    }
}
