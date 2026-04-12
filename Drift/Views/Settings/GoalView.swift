import SwiftUI
import Charts

struct GoalView: View {
    @Environment(\.dismiss) private var dismiss
    @State var goal: WeightGoal? = WeightGoal.load()
    @State var showingSetup = false
    @State var currentWeightKg: Double?
    @State var actualWeeklyRate: Double?
    @State var actualDailyDeficit: Double?
    @State var tdeeConfig = TDEEEstimator.loadConfig()
    @State var profileExpanded = false
    @State var showSaved = false
    @State var heightInFeet = false
    @State var weightText = ""
    @FocusState var weightFocused: Bool

    let ageRanges = ["18-24", "25-34", "35-44", "45-54", "55-64", "65+"]
    func ageFromRange(_ range: String) -> Int {
        switch range {
        case "18-24": return 21
        case "25-34": return 30
        case "35-44": return 40
        case "45-54": return 50
        case "55-64": return 60
        case "65+": return 70
        default: return 30
        }
    }
    func rangeFromAge(_ age: Int?) -> String {
        guard let age else { return "25-34" }
        switch age {
        case ..<25: return "18-24"
        case 25..<35: return "25-34"
        case 35..<45: return "35-44"
        case 45..<55: return "45-54"
        case 55..<65: return "55-64"
        default: return "65+"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Profile section
                profileCard

                if let goal {
                    GoalProgressCard(
                        goal: goal,
                        currentWeightKg: currentWeightKg ?? goal.startWeightKg,
                        trendWeightKg: WeightTrendService.shared.trend?.currentEMA
                    )

                    Button { showingSetup = true } label: {
                        Label("Update Goal", systemImage: "pencil.circle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Theme.accent)
                    macroTargetsCard(goal)
                    paceCard(goal)
                    deficitCard(goal)
                    projectionCard(goal)

                    Button {
                        WeightGoal.clear()
                        self.goal = nil
                    } label: {
                        Text("Clear Goal")
                            .font(.caption)
                            .foregroundStyle(Theme.surplus.opacity(0.7))
                    }
                    .padding(.top, 8)
                } else {
                    emptyState
                }

                if goal == nil {
                    Button { showingSetup = true } label: {
                        Label("Set Weight Goal", systemImage: "target")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Weight Goal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            GoalSetupView(existingGoal: goal) { newGoal in
                newGoal.save()
                goal = newGoal
            }
        }
        .onAppear {
            AIScreenTracker.shared.currentScreen = .goal
            goal = WeightGoal.load()
            loadCurrentData()
        }
    }

    // Profile card, form fields, and save logic in GoalView+Profile.swift

    // MARK: - Macro Targets

    private func macroTargetsCard(_ goal: WeightGoal) -> some View {
        let targets = goal.macroTargets(currentWeightKg: currentWeightKg)
        let pref = goal.dietPreference ?? .balanced
        let weight = currentWeightKg ?? goal.startWeightKg
        let explanation = goal.calorieTargetExplanation(currentWeightKg: currentWeightKg)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily Targets").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(pref.displayName).font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
            }

            if let t = targets {
                HStack(spacing: 8) {
                    targetPill("\(Int(t.calorieTarget))", label: "kcal", color: Theme.accent)
                    targetPill("\(Int(t.proteinG))g", label: "Protein", color: Theme.proteinRed)
                    targetPill("\(Int(t.carbsG))g", label: "Carbs", color: Theme.carbsGreen)
                    targetPill("\(Int(t.fatG))g", label: "Fat", color: Theme.fatYellow)
                }

                // Explain how calorie target was derived
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").font(.caption)
                    Text("\(explanation.source): \(explanation.detail)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

                let fatMin = WeightGoal.minimumFatG(bodyweightKg: weight, calorieTarget: t.calorieTarget)
                if t.fatG <= fatMin + 3 {
                    Text("Fat at minimum (\(Int(fatMin))g) for hormonal health")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Set a calorie target or log weight + food to see macro targets")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    private func targetPill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Pace

    private func paceCard(_ goal: WeightGoal) -> some View {
        let unit = Preferences.weightUnit
        let status = actualWeeklyRate.map { goal.isOnTrack(actualWeeklyRateKg: $0, currentWeightKg: currentWeightKg) } ?? .onTrack
        let statusColor: Color = (status == .behind || status == .wrongDirection) ? Theme.surplus : Theme.deficit

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pace").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(status.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text("Required")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(String(format: "%.2f", unit.convert(fromKg: goal.requiredWeeklyRate(currentWeightKg: currentWeightKg ?? goal.startWeightKg))))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text("\(unit.displayName)/wk")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()

                VStack(spacing: 3) {
                    Text("Actual")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let rate = actualWeeklyRate {
                        Text(String(format: "%.2f", unit.convert(fromKg: rate)))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(statusColor)
                    } else {
                        Text("--").font(.subheadline.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    Text("\(unit.displayName)/wk")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()
            }
        }
    }

    // MARK: - Deficit

    private func deficitCard(_ goal: WeightGoal) -> some View {
        let currentKg = currentWeightKg ?? goal.startWeightKg
        let losing = goal.isLosing(currentWeightKg: currentKg)
        let deficit = goal.requiredDailyDeficit(currentWeightKg: currentKg)

        // Goal-aware color: green when aligned with goal direction
        func goalColor(_ value: Double) -> Color {
            if losing {
                return value < 0 ? Theme.deficit : Theme.surplus
            } else {
                return value > 0 ? Theme.deficit : Theme.surplus
            }
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Daily Target").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text("Target").font(.caption2).foregroundStyle(.tertiary)
                    Text(String(format: "%+.0f", deficit))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(goalColor(deficit))
                    Text("kcal/day").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()

                VStack(spacing: 3) {
                    Text("Actual").font(.caption2).foregroundStyle(.tertiary)
                    if let deficit = actualDailyDeficit {
                        Text(String(format: "%+.0f", deficit))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(goalColor(deficit))
                    } else {
                        Text("--").font(.subheadline.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    Text("kcal/day").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()
            }
        }
    }

    // MARK: - Projection

    private func projectionCard(_ goal: WeightGoal) -> some View {
        let unit = Preferences.weightUnit

        let losing = goal.isLosing(currentWeightKg: currentWeightKg ?? goal.startWeightKg)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Projection").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            if let rate = actualWeeklyRate, let current = currentWeightKg, abs(rate) > 0.01 {
                let remaining = goal.remainingKg(currentWeightKg: current)
                // Check if moving in the right direction
                let movingRight = (losing && rate < 0) || (!losing && rate > 0)

                if movingRight {
                    let weeksToGoal = abs(remaining / rate)
                    let projectedDate = Calendar.current.date(byAdding: .day, value: Int(weeksToGoal * 7), to: Date())

                    HStack(spacing: 12) {
                        VStack(spacing: 3) {
                            Text("At current pace").font(.caption2).foregroundStyle(.tertiary)
                            if let date = projectedDate {
                                Text(DateFormatters.shortDisplay.string(from: date))
                                    .font(.subheadline.weight(.bold))
                            }
                            Text("\(Int(weeksToGoal)) weeks").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity).card()

                        VStack(spacing: 3) {
                            Text("Goal date").font(.caption2).foregroundStyle(.tertiary)
                            if let date = goal.targetDate {
                                Text(DateFormatters.shortDisplay.string(from: date))
                                    .font(.subheadline.weight(.bold))
                            }
                            if let weeks = goal.weeksRemaining {
                                Text("\(Int(weeks)) weeks").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity).card()
                    }

                    if let projected = projectedDate, let target = goal.targetDate {
                        let diff = Calendar.current.dateComponents([.day], from: target, to: projected).day ?? 0
                        if diff < -7 {
                            Text("On track to reach your goal \(abs(diff)) days early")
                                .font(.caption).foregroundStyle(Theme.deficit)
                        } else if diff > 7 {
                            Text("\(diff) days behind — adjust your \(losing ? "deficit" : "surplus") or extend timeline")
                                .font(.caption).foregroundStyle(Theme.surplus)
                        } else {
                            Text("Right on schedule")
                                .font(.caption).foregroundStyle(Theme.deficit)
                        }
                    }
                } else {
                    // Moving the WRONG direction
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            VStack(spacing: 3) {
                                Text("At current pace").font(.caption2).foregroundStyle(.tertiary)
                                Text("Wrong direction")
                                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.surplus)
                            }
                            .frame(maxWidth: .infinity).card()

                            VStack(spacing: 3) {
                                Text("Goal date").font(.caption2).foregroundStyle(.tertiary)
                                if let date = goal.targetDate {
                                    Text(DateFormatters.shortDisplay.string(from: date))
                                        .font(.subheadline.weight(.bold))
                                }
                                if let weeks = goal.weeksRemaining {
                                    Text("\(Int(weeks)) weeks").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity).card()
                        }

                        Text("Your weight trend is currently moving the other way. Follow your calorie target and this will adjust as your trend catches up.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Need more weight data to project")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.5))
            Text("No Goal Set").font(.headline)
            Text("Set a target weight and timeline to track your deficit and see if you're on pace.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.top, 40)
    }

    private func loadCurrentData() {
        let service = WeightTrendService.shared
        service.refresh()
        currentWeightKg = service.latestWeightKg ?? service.trendWeight
        actualWeeklyRate = service.weeklyRate
        actualDailyDeficit = service.dailyDeficit
        // Initialize weight text field
        if let kg = currentWeightKg {
            let unit = Preferences.weightUnit
            weightText = String(format: "%.1f", unit.convert(fromKg: kg))
        }
    }
}

