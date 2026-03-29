import SwiftUI

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Calorie Balance Card
                    calorieBalanceCard

                    // Weight Trend Card
                    weightTrendCard

                    // Macro Summary
                    macroSummaryCard

                    // Health Data (from Apple Health)
                    if viewModel.isHealthKitAvailable {
                        healthDataCard
                    } else {
                        healthKitPromptCard
                    }

                    // Supplements Status
                    if viewModel.supplementsTotal > 0 {
                        supplementStatusCard
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .task {
                await viewModel.loadToday()
            }
            .refreshable {
                await viewModel.loadToday()
            }
        }
    }

    // MARK: - Cards

    private var calorieBalanceCard: some View {
        VStack(spacing: 12) {
            Text("Today's Energy Balance")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                VStack {
                    Text("\(Int(viewModel.todayNutrition.calories))")
                        .font(.title.bold().monospacedDigit())
                    Text("Consumed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("-")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack {
                    Text("\(Int(viewModel.caloriesBurned))")
                        .font(.title.bold().monospacedDigit())
                    Text("Burned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("=")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack {
                    Text("\(Int(viewModel.calorieBalance))")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(viewModel.calorieBalance < 0 ? .green : .red)
                    Text(viewModel.calorieBalance < 0 ? "Deficit" : "Surplus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var weightTrendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Trend")
                .font(.subheadline.bold())

            if let weight = viewModel.currentWeight {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(String(format: "%.1f", Preferences.weightUnit.convert(fromKg: weight))) \(Preferences.weightUnit.displayName)")
                            .font(.title2.bold().monospacedDigit())
                        Text("Current (smoothed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let rate = viewModel.weeklyRate {
                        VStack(alignment: .trailing) {
                            Text("\(rate >= 0 ? "+" : "")\(String(format: "%.2f", Preferences.weightUnit.convert(fromKg: rate)))")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(rate < 0 ? .green : rate > 0 ? .red : .primary)
                            Text("\(Preferences.weightUnit.displayName)/week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let deficit = viewModel.dailyDeficit {
                    Text("\(Int(deficit) >= 0 ? "+" : "")\(Int(deficit)) kcal/day from weight trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Log weight to see trends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var macroSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Macros")
                .font(.subheadline.bold())

            HStack(spacing: 16) {
                macroItem("Protein", value: viewModel.todayNutrition.proteinG, color: .red)
                macroItem("Carbs", value: viewModel.todayNutrition.carbsG, color: .green)
                macroItem("Fat", value: viewModel.todayNutrition.fatG, color: .yellow)
                macroItem("Fiber", value: viewModel.todayNutrition.fiberG, color: .brown)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func macroItem(_ name: String, value: Double, color: Color) -> some View {
        VStack {
            Text("\(Int(value))g")
                .font(.headline.monospacedDigit())
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var healthDataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From Apple Health")
                .font(.subheadline.bold())

            HStack(spacing: 16) {
                healthItem(icon: "flame.fill", value: "\(Int(viewModel.activeCalories))", label: "Active cal", color: .orange)
                healthItem(icon: "bed.double.fill", value: String(format: "%.1fh", viewModel.sleepHours), label: "Sleep", color: .indigo)
                healthItem(icon: "figure.walk", value: "\(Int(viewModel.steps))", label: "Steps", color: .teal)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func healthItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var healthKitPromptCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.clipboard")
                .font(.largeTitle)
                .foregroundStyle(.red.opacity(0.6))
            Text("Connect Apple Health")
                .font(.subheadline.bold())
            Text("Grant access to see calories burned, sleep, and steps.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Grant Access") {
                Task {
                    try? await HealthKitService.shared.requestAuthorization()
                    await viewModel.loadToday()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var supplementStatusCard: some View {
        HStack {
            Image(systemName: "pill")
                .foregroundStyle(.mint)
            Text("Supplements")
                .font(.subheadline.bold())
            Spacer()
            Text("\(viewModel.supplementsTaken)/\(viewModel.supplementsTotal) taken")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
