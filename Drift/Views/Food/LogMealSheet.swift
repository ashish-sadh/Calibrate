import SwiftUI
import DriftCore

/// V7 Phase 5 — unified Log-a-Meal sheet. Presented from the floating
/// "+" FAB and from the Dashboard quick-log chips (Snap / Voice /
/// Search / Recent). Matches reference mocks 16-19.
///
/// Layout:
///   - "Log a meal" title + subtitle
///   - 4-mode segmented picker (Recent / Search / Voice / Snap)
///   - Mode-specific sub-view below
///
/// Replaces the V6/early-V7 stub that just wrapped `FoodTabView` in a
/// NavigationStack with a Done button.
public enum LogMealMode: String, CaseIterable, Identifiable, Sendable {
    case recent, search, voice, snap
    public var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Recent"
        case .search: "Search"
        case .voice: "Voice"
        case .snap: "Snap"
        }
    }

    var icon: String {
        switch self {
        case .recent: "clock"
        case .search: "magnifyingglass"
        case .voice: "mic"
        case .snap: "camera"
        }
    }
}

struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mode: LogMealMode
    @State private var foodLogVM = FoodLogViewModel()
    @State private var showingPhotoLog = false
    @State private var recentFoods: [Food] = []

    init(initialMode: LogMealMode = .recent) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Picker("Mode", selection: $mode) {
                    ForEach(LogMealMode.allCases) { m in
                        Label(m.label, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("log-meal-mode-picker")

                Divider().overlay(Theme.separator).padding(.top, 12)

                modeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        // V7 polish: user asked that finishing a log
                        // session (Done after Search/Voice/Recent
                        // adds) routes them to the Food Diary so they
                        // see what they just added in context.
                        // Posting `.navigateToTab` with the legacy
                        // food index = 2 — ContentView's binding shim
                        // maps that to `PrimaryTab.food`.
                        NotificationCenter.default.post(
                            name: .navigateToTab,
                            object: nil,
                            userInfo: ["tab": 2]
                        )
                        dismiss()
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showingPhotoLog) {
                PhotoLogFlowView(foodLog: foodLogVM)
            }
            .task { recentFoods = FoodService.fetchRecentFoods(limit: 30) }
            // V7 polish: Snap is a verb, not a screen. When the user
            // arrives at Snap mode (either via initialMode or by tapping
            // the segment), present the camera-driven PhotoLog flow
            // directly instead of an intermediate empty state.
            .onAppear {
                if mode == .snap { showingPhotoLog = true }
            }
            .onChange(of: mode) { _, new in
                if new == .snap { showingPhotoLog = true }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log a meal")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Tap a recent item or use a method below")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Mode dispatch

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .recent: recentContent
        case .search: searchContent
        case .voice: VoiceLogSheet()
        case .snap: snapContent
        }
    }

    // MARK: - Recent

    private var recentContent: some View {
        Group {
            if recentFoods.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "No recent foods yet",
                    subtitle: "Log a meal once and it'll appear here for one-tap re-logging."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentFoods) { food in
                            recentRow(food)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func recentRow(_ food: Food) -> some View {
        Button {
            logFood(food)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(formatServing(food)) · \(String(format: "%.0f", food.proteinG))g P")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(Int(food.calories))")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log-meal-recent-\(food.id ?? -1)")
    }

    private func logFood(_ food: Food) {
        foodLogVM.quickAdd(
            name: food.name,
            calories: food.calories,
            proteinG: food.proteinG,
            carbsG: food.carbsG,
            fatG: food.fatG,
            fiberG: food.fiberG,
            mealType: defaultMealType(),
            servingSizeG: food.servingSize,
            servings: 1
        )
        // After a Recent-tap log, route to the Food Diary so the user
        // sees the entry land in today's timeline. Same intent as the
        // Done-button navigate above.
        NotificationCenter.default.post(
            name: .navigateToTab,
            object: nil,
            userInfo: ["tab": 2]
        )
        dismiss()
    }

    private func formatServing(_ food: Food) -> String {
        // Food doesn't ship a one-liner servingDescription. Compose from
        // servingSize + servingUnit, falling back to "1 serving" when the
        // unit is empty (typical for ad-hoc entries).
        let unit = food.servingUnit.isEmpty ? "serving" : food.servingUnit
        let qty = food.servingSize.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(food.servingSize))
            : String(format: "%.1f", food.servingSize)
        return "\(qty) \(unit)"
    }

    private func defaultMealType() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    // MARK: - Search

    private var searchContent: some View {
        FoodSearchView(viewModel: foodLogVM)
    }

    // MARK: - Snap

    private var snapContent: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "camera")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text("Snap your plate")
                    .font(.headline.weight(.semibold))
                Text("AI will detect each item and suggest portions. Confirm before logging.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showingPhotoLog = true
                } label: {
                    Label("Open camera", systemImage: "camera.fill")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .accessibilityIdentifier("log-meal-snap-open-camera")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.separator, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .padding(.horizontal, 16)
            Spacer()
        }
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

#Preview {
    LogMealSheet()
}
