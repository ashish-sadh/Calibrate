import SwiftUI
import DriftCore

/// V7 Phase 5 — unified Log-a-Meal sheet. Presented from the floating
/// "+" FAB and from the Dashboard quick-log chips (Snap / Voice /
/// Search / Recent). Matches reference mocks 16-19.
///
/// Layout:
///   - "Log a meal" title + subtitle
///   - 5-mode segmented picker (Recent / Search / Voice / Text / Snap)
///   - Mode-specific sub-view below
///
/// Replaces the V6/early-V7 stub that just wrapped `FoodTabView` in a
/// NavigationStack with a Done button.
/// V7: 5 modes (Recent / Search / Voice / Text / Snap). The Snap segment
/// auto-presents PhotoLogFlowView the moment it's selected and bounces
/// back to Recent on dismiss so the user isn't stranded on an empty
/// Snap segment. Single PhotoLog implementation, four entry points:
///   1. FAB → LogMealSheet → Snap segment (via this enum case)
///   2. Dashboard quick-log "Snap" chip → posts `.openLogMeal(mode: .snap)`
///   3. Food-tab top-right camera shortcut → posts `.openPhotoLog`
///      (skips the sheet step for the "I know I want camera" shortcut)
///   4. Drift Coach "snap a meal" voice/text command (TODO)
public enum LogMealMode: String, CaseIterable, Identifiable, Sendable {
    case recent, search, describe, snap
    public var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Recent"
        case .search: "Search"
        case .describe: "Describe"
        case .snap: "Snap"
        }
    }

    var icon: String {
        switch self {
        case .recent: "clock"
        case .search: "magnifyingglass"
        case .describe: "text.bubble"
        case .snap: "camera"
        }
    }
}

struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mode: LogMealMode
    @State private var foodLogVM = FoodLogViewModel()
    @State private var recentEntries: [RecentEntry] = []
    @State private var showingPhotoLog = false

    // Default mode changed 2026-05-24 — user feedback: "make Search
    // default not Recent". Most "Add Food" taps come from intent to
    // log something specific (typed query); Recent is for repeat
    // loggers and still one tap away in the segmented picker.
    init(initialMode: LogMealMode = .search) {
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
            // #966: .container only. Plain ignoresSafeArea() = .all absorbs the
            // KEYBOARD bottom inset here at the parent, so the Describe screen's
            // safeAreaInset Continue row could never rise above the keyboard no
            // matter what the child did. Scoping to .container keeps the
            // background under the status bar / home indicator while letting the
            // keyboard inset propagate to the child.
            .background(Theme.background.ignoresSafeArea(.container))
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
            // #1030: Recent must reflect foods ACTUALLY LOGGED (photo/AI/manual/custom
            // included), not just DB-catalog foods. fetchRecentEntryNames reads food_usage
            // directly — the same source FoodSearchView's recents use, so both surfaces match.
            .task { recentEntries = (try? AppDatabase.shared.fetchRecentEntryNames(limit: 30)) ?? [] }
            // V7: Snap-segment auto-triggers PhotoLog so the user
            // doesn't see two screens in sequence ("Snap your plate"
            // empty state, then the real PhotoLog). Bounces back to
            // Recent on dismiss so the user isn't stranded if they
            // cancel out of PhotoLog — the previous "stuck on Snap
            // segment" bug from commit 774c9bfc.
            .onAppear {
                if mode == .snap { showingPhotoLog = true }
            }
            .onChange(of: mode) { _, new in
                if new == .snap { showingPhotoLog = true }
            }
            .onChange(of: showingPhotoLog) { _, isShowing in
                if !isShowing && mode == .snap {
                    mode = .recent
                }
            }
            // A successful Snap log routes to the Food diary (PhotoLogFlowView
            // posts .navigateToTab) — this sheet must get out of the way so the
            // user actually SEES the diary instead of bouncing back to
            // "Log a meal" (field complaint 2026-07-07). Cancel/retake still
            // land on Recent via the onChange above.
            .onReceive(NotificationCenter.default.publisher(for: .photoLogCompleted)) { _ in
                dismiss()
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
        // #935: one Describe method — type or speak into the same input.
        case .describe: VoiceLogSheet()
        case .snap:
            // Brief placeholder while PhotoLogFlowView covers — the
            // .onAppear / .onChange handlers above flip showingPhotoLog
            // to true on this segment. If the cover happens to be
            // dismissing or hasn't shown yet, this passive card avoids
            // a black gap. Bounces back to Recent on PhotoLog dismiss.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Recent

    private var recentContent: some View {
        Group {
            if recentEntries.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "No recent foods yet",
                    subtitle: "Log a meal once and it'll appear here for one-tap re-logging."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentEntries) { entry in
                            recentRow(entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func recentRow(_ entry: RecentEntry) -> some View {
        Button {
            logEntry(entry)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(entry.macroSummary)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(Int(entry.calories))")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log-meal-recent-\(entry.name)")
    }

    private func logEntry(_ entry: RecentEntry) {
        // #1030: re-log exactly what was logged before — a DB food via its catalog row,
        // a recipe/manual/photo entry via its stored macros (mirrors FoodSearchView recents).
        if entry.isDBFood, let food = FoodService.findByName(entry.name) {
            foodLogVM.quickLogFood(food)
        } else {
            foodLogVM.quickAdd(
                name: entry.name,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                fiberG: entry.fiberG,
                mealType: defaultMealType(),
                servingSizeG: entry.servingSize,
                servings: 1
            )
        }
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
        // embedded: this sheet already provides the NavigationStack + Done; let
        // FoodSearchView drop its own so there's only one "Done".
        FoodSearchView(viewModel: foodLogVM, embedded: true)
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: Theme.FontSize.display2, weight: .light))
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
