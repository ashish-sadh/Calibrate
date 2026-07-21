import Testing
@testable import DriftCore

@Suite struct ExercisePosesBoundaryTests {
    @Test(arguments: [
        "free-exercise-db/main/exercises/Deadlift/0.jpg",
        "https://cdn.example.test/free-exercise-db/main/exercises/Deadlift/1.webp?size=large",
        "prefix/free-exercise-db/main/exercises/Deadlift/frames/start.jpg",
    ])
    func extractsTheFirstDirectoryAfterTheDatasetMarker(_ imageURL: String) {
        #expect(ExercisePoses.assetBaseName(fromImageUrl: imageURL) == "Deadlift")
    }

    @Test func preservesTheCatalogDirectorySpelling() {
        #expect(ExercisePoses.assetBaseName(
            fromImageUrl: "free-exercise-db/main/exercises/Clean_%26_Jerk-Push_Press/0.jpg"
        ) == "Clean_%26_Jerk-Push_Press")
    }

    @Test(arguments: [
        "free-exercise-db/main/exercises/",
        "free-exercise-db/main/exercises/Front_Squat",
        "free-exercise-db/main/exercises//1.jpg",
    ])
    func requiresANonemptyDirectoryFollowedByASlash(_ imageURL: String) {
        #expect(ExercisePoses.assetBaseName(fromImageUrl: imageURL) == nil)
    }

    @Test func datasetMarkerMatchingIsCaseSensitive() {
        #expect(ExercisePoses.assetBaseName(
            fromImageUrl: "free-exercise-db/main/Exercises/Front_Squat/0.jpg"
        ) == nil)
    }
}
