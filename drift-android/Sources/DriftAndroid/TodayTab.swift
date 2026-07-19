import SwiftUI
import Observation
import SkipFuse
import DriftCore

/// Dashboard-lite for the Today tab (#1061 tracks the full iOS Dashboard —
/// rings/donut, coaching cards, sleep/recovery need Health Connect first).
/// Cards jump to their tabs, matching iOS's cross-tab links.
@MainActor @Observable class TodayStore {
    var totals = TotalsRow()
    var currentWeight = "—"
    var weekWorkouts = 0
    var streak = 0

    func reload() {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            let t = FoodService.getDailyTotals()
            totals = TotalsRow(eaten: t.eaten, target: t.target, remaining: t.remaining,
                               proteinG: t.proteinG, carbsG: t.carbsG, fatG: t.fatG, fiberG: t.fiberG)
            let unit = Preferences.weightUnit
            if let latest = WeightServiceAPI.getHistory(days: 365).sorted(by: { $0.date > $1.date }).first {
                let value = unit == .kg ? latest.weightKg : latest.weightKg * 2.20462
                currentWeight = String(format: "%.1f %@", value, unit.displayName)
            }
            weekWorkouts = (try? WorkoutService.weeklyWorkoutCounts(weeks: 1))?.first?.count ?? 0
            streak = (try? WorkoutService.workoutStreak())?.current ?? 0
        }
    }
}

struct TodayTab: View {
    @Binding var selectedTab: PrimaryTab
    @State var store = TodayStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.deficit)
                        Text("All data stays on your device.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }

                    // Nutrition card → Food tab
                    Button { selectedTab = .food } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TODAY'S INTAKE").sectionHeading()
                                Spacer()
                                if store.totals.target > 0 {
                                    Text("\(store.totals.remaining) kcal left")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(store.totals.remaining >= 0 ? Theme.deficit : Theme.surplus)
                                }
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(store.totals.eaten)")
                                    .font(.system(size: Theme.FontSize.display1, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Theme.macroKcal)
                                Text("/ \(store.totals.target) kcal")
                                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }
                            HStack(spacing: 8) {
                                dot("\(store.totals.proteinG)g P", Theme.macroProtein)
                                dot("\(store.totals.carbsG)g C", Theme.macroCarbs)
                                dot("\(store.totals.fatG)g F", Theme.macroFat)
                                dot("\(store.totals.fiberG)g Fiber", Theme.macroFiber)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    .buttonStyle(.plain)

                    // Weight + Workout stat cards
                    HStack(spacing: 10) {
                        Button { selectedTab = .body } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                    Text("WEIGHT").sectionHeading()
                                }
                                Text(store.currentWeight)
                                    .font(Theme.fontStat)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }.buttonStyle(.plain)

                        Button { selectedTab = .workout } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.deficit).frame(width: 6, height: 6)
                                    Text("WORKOUTS").sectionHeading()
                                }
                                Text("\(store.weekWorkouts) this week")
                                    .font(Theme.fontStat)
                                    .foregroundStyle(Theme.textPrimary)
                                if store.streak > 0 {
                                    Text("\(store.streak)w streak")
                                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Today")
            .onAppear { store.reload() }
        }
    }

    private func dot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.pillBackground, in: Capsule())
    }
}
