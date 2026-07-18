import Foundation
import Observation
import SkipFuse
import DriftCore

/// A row the UI can render — same-module value type so it's Sendable across
/// the background-DB → MainActor hop (DriftCore's Food is not).
struct FoodRow: Identifiable, Sendable {
    let name: String
    let detail: String
    var id: String { name }
}

/// P1 spike: proves DriftCore + GRDB + the bundled food seed work on Android.
/// Opens the real AppDatabase (which migrates + seeds Indian foods from the
/// package resources) and searches it. All DB work stays off the main thread —
/// the first touch of AppDatabase.shared runs migrations + the food seed,
/// which ANRs the app if done in init on the UI thread.
@MainActor @Observable public class ViewModel {
    var query = "dosa"
    var results: [FoodRow] = []
    var status = "opening database…"

    init() {
        search()
    }

    func search() {
        let q = query
        status = "searching…"
        Task {
            let rows = await Self.runSearch(q)
            self.results = rows
            self.status = "\(rows.count) foods for “\(q)”"
        }
    }

    private static func runSearch(_ query: String) async -> [FoodRow] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                CoreResourcesBootstrap.install()
                let foods = (try? AppDatabase.shared.searchFoods(query: query, limit: 30)) ?? []
                let rows = foods.map { food in
                    FoodRow(
                        name: food.name,
                        detail: "\(Int(food.calories)) kcal · P \(Int(food.proteinG))g · C \(Int(food.carbsG))g · F \(Int(food.fatG))g"
                    )
                }
                continuation.resume(returning: rows)
            }
        }
    }
}
