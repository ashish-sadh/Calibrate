import SwiftUI
import DriftCore

// Single-source (SharedUI): AI text meal logger — the Describe flow (#1101).
// Android's primary use: the Today-tab Describe chip and the food search's
// "log with AI" row present this sheet; iOS keeps its richer VoiceLogSheet
// (mic + dictation) for now, so only Android wires this in.
//
// It is ALSO Android's editable review surface for Drift Coach's food-logging
// turns (#1135) — the coach seeds `initialItems` with what it already resolved
// and the sheet opens straight in review, so "log 2 eggs" commits real diary
// rows instead of degrading to a message.
//
// Pipeline mirrors ExerciseVoiceLogSheet (the workout twin):
//   input (typed text) → NebiusMealLogger.parse (cloud, same brain as Drift
//   Coach) → editable review rows + MealTimePicker → quickAddBatch.
//   Offline rung: AIActionExecutor.parseMultiItemMeal resolves against the
//   local food DB — names + portions, no cloud macros.
//
// #1106 lesson: Fuse can keep the sheet's view identity across presentations,
// resurrecting a cancelled parse. `onAppear` resets to a fresh session every
// time before honoring `initialQuery`.
struct DescribeMealSheet: View {
    @Environment(\.dismiss) var dismiss
    /// Query handed from the search sheet's "log with AI" row — parsed
    /// immediately so the tap lands in the review, not an empty field.
    let initialQuery: String?
    /// Rows the caller has ALREADY resolved — Drift Coach hands its parsed food
    /// intents straight to the review, skipping input+parse entirely (#1135).
    /// Takes precedence over `initialQuery`.
    let initialItems: [PhotoLogItem]?
    /// Meal slot the caller detected ("log 2 eggs for breakfast"). Nil falls
    /// back to the time-of-day slot, matching the un-seeded flow.
    let initialMealType: MealType?
    let onLogged: () -> Void

    @State var foodLog = FoodLogViewModel()
    @State var phase: Phase = .input
    @State var draft = ""
    @State var items: [PhotoLogItem] = []
    @State var logTime = Date()
    @State var mealType: MealType = .snack

    enum Phase: Equatable {
        case input, parsing, reviewing
        case error(String)
    }

    init(initialQuery: String? = nil,
         initialItems: [PhotoLogItem]? = nil,
         initialMealType: MealType? = nil,
         onLogged: @escaping () -> Void = {}) {
        self.initialQuery = initialQuery
        self.initialItems = initialItems
        self.initialMealType = initialMealType
        self.onLogged = onLogged
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // In-content chrome (#1089 pattern) — sheet nav bar off.
                HStack {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                switch phase {
                case .input: inputView
                case .parsing: parsingView
                case .reviewing: reviewView
                case .error(let message): errorView(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .onAppear {
                // Fresh session every presentation (#1106) — then honor the
                // caller's seed. Reset FIRST or Fuse resurrects the last
                // presentation's rows.
                phase = .input
                items = []
                logTime = Date()
                if let seeded = initialItems, !seeded.isEmpty {
                    // Coach already resolved these — land straight in the review.
                    enterReview(seeded, mealType: initialMealType)
                } else if let q = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                    draft = q
                    Task { await parse(q) }
                }
            }
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(spacing: 22) {
            Spacer()

            Text("Describe your meal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("e.g. \u{201C}2 rotis, dal tadka and a bowl of curd\u{201D}")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            MealDraftField(draft: $draft)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                Task { await parse(draft) }
            } label: {
                Label("Continue", systemImage: sym("arrow.forward.circle.fill"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("describe-meal-submit")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Parsing

    private var parsingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Working out the macros…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(items.indices, id: \.self) { i in
                        reviewRow(items[i], index: i)
                    }
                    MealTimePicker(time: $logTime, mealType: $mealType)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Button {
                logAll()
            } label: {
                Text("Log \(items.count) item\(items.count == 1 ? "" : "s") as \(mealType.displayName)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func reviewRow(_ item: PhotoLogItem, index: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.reviewSummary)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                items.remove(at: index)
            } label: {
                Image(systemName: sym("xmark.circle.fill"))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: sym("exclamationmark.bubble"))
                .font(.title)
                .foregroundStyle(Theme.textTertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") { phase = .input }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
            Spacer()
        }
    }

    // MARK: - Parse (cloud → offline DB fallback)

    private func parse(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        FeatureUsage.record(TelemetryEvent.describeUsed)
        phase = .parsing
        let started = Date()

        // Top rung: the coach cloud model — full macros, Indian-portion aware.
        if let resp = await NebiusMealLogger.parse(trimmed), !resp.items.isEmpty {
            recordTurn(query: trimmed, items: resp.items, outcome: "success", started: started)
            enterReview(resp.items)
            return
        }

        // Offline rung: deterministic multi-item split + local food DB. Macros
        // come from the catalog row, scaled by the stated quantity.
        let intents = AIActionExecutor.parseMultiItemMeal(trimmed)
            ?? [FoodIntent(query: trimmed, servings: nil)]
        let resolved: [PhotoLogItem] = await resolveOffline(intents)
        if !resolved.isEmpty {
            recordTurn(query: trimmed, items: resolved, outcome: "fallback", started: started)
            enterReview(resolved)
            return
        }

        recordTurn(query: trimmed, items: [], outcome: "error", started: started)
        phase = .error("Couldn't work that out. Try simpler names (\u{201C}2 rotis and dal\u{201D}) — or find it in Search.")
    }

    /// Telemetry for the Describe surface. `outcome` distinguishes the cloud
    /// hit from the offline fallback, which is the whole point: a rising
    /// `fallback` rate means the cloud brain is missing dishes people eat.
    /// The "response" is the parsed item list, not prose — that IS the answer
    /// this surface produces.
    private func recordTurn(query: String, items: [PhotoLogItem], outcome: String, started: Date) {
        let summary = items
            .map(\.telemetrySummary)
            .joined(separator: "\n")
        TelemetryService.shared.aiTurn(
            surface: TelemetrySurface.describeMeal,
            query: query,
            response: summary.isEmpty ? nil : summary,
            outcome: outcome,
            latencyMS: (Date().timeIntervalSince(started) * 1000).rounded().safeInt)
    }

    private func enterReview(_ parsed: [PhotoLogItem], mealType slot: MealType? = nil) {
        items = parsed
        mealType = slot ?? foodLog.autoMealType
        logTime = Date()
        phase = .reviewing
    }

    /// Resolve offline intents against the local catalog off the main actor —
    /// searchFood is a SQLite hit per item (no sync DB work in Fuse bodies).
    private func resolveOffline(_ intents: [FoodIntent]) async -> [PhotoLogItem] {
        let queries = intents.map { (query: $0.query, servings: $0.servings ?? 1) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = queries.compactMap { q -> PhotoLogItem? in
                    guard let food = FoodService.searchFood(query: q.query).first else { return nil }
                    let n = max(q.servings, 0.1)
                    return PhotoLogItem(
                        name: food.name,
                        grams: food.servingSize * n,
                        calories: food.calories * n,
                        proteinG: food.proteinG * n,
                        carbsG: food.carbsG * n,
                        fatG: food.fatG * n,
                        fiberG: food.fiberG * n,
                        confidence: .medium)
                }
                continuation.resume(returning: rows)
            }
        }
    }

    // MARK: - Log

    private func logAll() {
        let loggedAt = DateFormatters.iso8601.string(from: foodLog.anchoredToSelectedDay(logTime))
        let batch = items.map { item in
            FoodLogViewModel.BatchFoodItem(
                name: item.name,
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                fiberG: item.fiberG,
                mealType: mealType,
                loggedAt: loggedAt,
                servingSizeG: item.grams,
                servings: 1)
        }
        foodLog.quickAddBatch(batch)
        onLogged()
        dismiss()
    }
}

/// The one TextField gets its own scope (Fuse binds only the first TextField
/// per ViewBuilder scope). Internal, not private — Skip cannot bridge
/// private views.
struct MealDraftField: View {
    @Binding var draft: String

    var body: some View {
        #if os(Android)
        TextField("2 rotis, dal tadka, bowl of curd", text: $draft)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .stroke(Theme.separator, lineWidth: 0.5)
            )
        #else
        TextField("2 rotis, dal tadka, bowl of curd", text: $draft)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
        #endif
    }
}
