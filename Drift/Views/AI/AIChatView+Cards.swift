import SwiftUI
import DriftCore

// MARK: - Confirmation cards rendered inside chat bubbles
//
// One method per card type; each is invoked from messageBubble in
// AIChatView+ChatBubble.swift. Keep these self-contained so adding a new card
// is a single function + a struct in AIChatViewModel + a hook in messageBubble.

extension AIChatView {

    // MARK: Proposed Meal Card (#518)

    func proposedMealCardView(_ card: AIChatViewModel.ProposedMealCardData, messageId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.caption).foregroundStyle(Theme.calorieBlue)
                Text("Detected meal")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(card.items.reduce(0) { $0 + $1.calories }) cal")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(Theme.separator)

            ForEach(card.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.caption.weight(.medium))
                        Text("\(item.grams)g · \(item.protein)P \(item.carbs)C \(item.fat)F")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(item.calories) cal")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.calorieBlue)
                }
            }

            HStack(spacing: 10) {
                Button {
                    vm.clearPendingProposal()
                    vm.inputText = "Change "
                    inputFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .medium))
                        Text("Edit")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    vm.confirmProposedMeal(card, messageId: messageId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text("Log all")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.calorieBlue))
                }
                .buttonStyle(.plain)
                .disabled(vm.isGenerating)
                .accessibilityLabel("Log all \(card.items.count) items")
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.calorieBlue.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: Remote Provider Badge (#533)

    struct RemoteProviderBadge: View {
        let provider: String
        @State private var showingPopover = false

        var body: some View {
            Button {
                showingPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 9))
                    Text("via \(provider)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPopover) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Processed by \(provider)", systemImage: "cloud.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Your API key, no Drift servers. Messages go directly to \(provider)'s API and are subject to their privacy policy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel("Handled by \(provider). Tap for privacy details.")
        }
    }

    // MARK: Nutrition Lookup Card

    func nutritionLookupCard(_ card: AIChatViewModel.NutritionLookupCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption).foregroundStyle(Theme.calorieBlue)
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("per \(card.servingSize)\(card.servingUnit)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach([
                    (value: card.servingCalories, label: "cal",     color: Theme.calorieBlue),
                    (value: card.servingProteinG, label: "protein",  color: Theme.proteinRed),
                    (value: card.servingCarbsG,   label: "carbs",    color: Theme.carbsGreen),
                    (value: card.servingFatG,      label: "fat",      color: Theme.fatYellow),
                ], id: \.label) { item in
                    VStack(spacing: 2) {
                        Text(item.label == "cal" ? "\(item.value)" : "\(item.value)g")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(item.color)
                        Text(item.label).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Text("per 100g:")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                Text("\(card.calories100g) cal · \(card.proteinG100g)g P · \(card.carbsG100g)g C · \(card.fatG100g)g F")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }

            Button {
                vm.inputText = "log \(card.name.lowercased())"
                Task { await vm.sendMessage() }
            } label: {
                Label("Log it", systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.calorieBlue)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.calorieBlue.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Food Confirmation Card

    func foodConfirmationCard(_ card: AIChatViewModel.FoodCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife")
                    .font(.caption).foregroundStyle(Theme.calorieBlue)
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Menu {
                    ForEach(MealType.allCases, id: \.self) { meal in
                        Button {
                            vm.foodSearchMealType = meal
                            vm.showingFoodSearch = true
                        } label: {
                            Label(meal.displayName, systemImage: meal.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: card.mealType.icon)
                        Text(card.mealType.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.accent.opacity(0.8))
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(card.calories)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.calorieBlue)
                    Text("cal").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.proteinG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.proteinRed)
                    Text("protein").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.carbsG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.carbsGreen)
                    Text("carbs").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.fatG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.fatYellow)
                    Text("fat").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.calorieBlue.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Weight Confirmation Card

    func weightConfirmationCard(_ card: AIChatViewModel.WeightCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", card.value)) \(card.unit)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if let trend = card.trend {
                    Text(trend)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Workout Confirmation Card

    func workoutConfirmationCard(_ card: AIChatViewModel.WorkoutCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.title3).foregroundStyle(Theme.accentSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.subheadline.weight(.bold))
                    HStack(spacing: 8) {
                        if let mins = card.durationMin {
                            Label("\(mins) min", systemImage: "clock")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let count = card.exerciseCount {
                            Label("\(count) exercises", systemImage: "list.bullet")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if card.confirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.title3)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Theme.accentSecondary.opacity(0.5)).font(.title3)
                }
            }

            if !card.muscleGroups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.muscleGroups, id: \.self) { group in
                        Label(group, systemImage: muscleIcon(group))
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accentSecondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.accentSecondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accentSecondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    func muscleIcon(_ group: String) -> String {
        switch group {
        case "Chest": "figure.arms.open"
        case "Back": "figure.walk"
        case "Shoulders": "figure.flexibility"
        case "Arms": "figure.boxing"
        case "Core": "figure.core.training"
        case "Legs": "figure.run"
        default: "figure.stand"
        }
    }

    // MARK: Navigation Confirmation Card

    func navigationConfirmationCard(_ card: AIChatViewModel.NavigationCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: card.icon)
                .font(.title3).foregroundStyle(Theme.accent)
            Text(card.destination)
                .font(.subheadline.weight(.bold))
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(Theme.accent.opacity(0.6)).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Supplement Confirmation Card

    func supplementConfirmationCard(_ card: AIChatViewModel.SupplementCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pills.fill")
                    .font(.caption).foregroundStyle(Theme.accent)
                if let action = card.action {
                    Text(action)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text("Supplements")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Text("\(card.taken)/\(card.total)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(card.taken == card.total ? .green : Theme.accent)
            }

            if !card.remaining.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle")
                        .font(.system(size: 6)).foregroundStyle(.tertiary)
                    Text("Need: \(card.remaining.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Text("All done for today")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Medication Confirmation Card

    func medicationConfirmationCard(_ card: AIChatViewModel.MedicationCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cross.vial.fill")
                .font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.subheadline.weight(.bold))
                if let dose = card.doseDisplay {
                    Text(dose)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Sleep & Recovery Card

    func sleepConfirmationCard(_ card: AIChatViewModel.SleepCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "moon.fill")
                    .font(.caption).foregroundStyle(.indigo)
                Text("Sleep & Recovery")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let readiness = card.readiness {
                    Text(readiness)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(readinessColor(readiness))
                }
            }

            HStack(spacing: 0) {
                if let hours = card.sleepHours {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", hours))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.indigo)
                        Text("hours").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let score = card.recoveryScore, score > 0 {
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(score >= 70 ? .green : score >= 40 ? .orange : .red)
                        Text("recovery").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let hrv = card.hrvMs, hrv > 0 {
                    VStack(spacing: 2) {
                        Text("\(hrv)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("HRV ms").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let rhr = card.restingHR, rhr > 0 {
                    VStack(spacing: 2) {
                        Text("\(rhr)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.proteinRed)
                        Text("RHR").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let rem = card.remHours, let deep = card.deepHours {
                HStack(spacing: 12) {
                    Label(String(format: "%.1fh REM", rem), systemImage: "brain.head.profile")
                        .font(.caption2).foregroundStyle(.secondary)
                    Label(String(format: "%.1fh deep", deep), systemImage: "bed.double.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 0.5)
        )
    }

    func readinessColor(_ readiness: String) -> Color {
        if readiness.contains("Good") { return .green }
        if readiness.contains("Moderate") { return .orange }
        if readiness.contains("Low") { return .red }
        return .secondary
    }

    // MARK: Glucose Confirmation Card

    func glucoseConfirmationCard(_ card: AIChatViewModel.GlucoseCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.caption).foregroundStyle(.orange)
                Text("Glucose")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(card.readingCount) readings")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(card.avgMgdl)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                    Text("avg mg/dL").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.minMgdl)–\(card.maxMgdl)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text("range").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.inZonePct)%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(card.inZonePct >= 70 ? .green : .orange)
                    Text("in zone").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.spikeCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(card.spikeCount == 0 ? .green : .red)
                    Text("spikes").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Biomarker Confirmation Card

    func biomarkerConfirmationCard(_ card: AIChatViewModel.BiomarkerCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "testtube.2")
                    .font(.caption).foregroundStyle(.cyan)
                Text("Biomarkers")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(card.optimalCount)/\(card.totalCount) optimal")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(card.outOfRange.isEmpty ? .green : .orange)
            }

            if card.outOfRange.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Text("All markers in optimal range")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.outOfRange.prefix(4), id: \.name) { marker in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(marker.status.contains("high") || marker.status.contains("High") ? .red : .orange)
                                .frame(width: 5, height: 5)
                            Text(marker.name)
                                .font(.caption2.weight(.medium))
                            Spacer()
                            Text(marker.value)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if card.outOfRange.count > 4 {
                        Text("+\(card.outOfRange.count - 4) more")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: Help Card

    func helpCardView(_ card: HelpCardData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(card.categories) { (cat: HelpCardData.Category) in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: cat.icon)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 18, alignment: .center)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cat.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(cat.examples, id: \.self) { example in
                            Button {
                                vm.inputText = example
                            } label: {
                                Text(example)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
    }
}
