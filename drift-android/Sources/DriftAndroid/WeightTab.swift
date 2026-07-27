import SwiftUI
import Observation
import SkipFuse
import DriftCore

// MARK: - Rows

struct WeightRow: Identifiable, Sendable {
    let id: Int64
    let date: String
    let display: String   // "82.4 kg"
}

struct WeightStats: Sendable {
    var current: String = "—"
    var trend: String = ""
    var change7d: String?
    var change30d: String?
}

// MARK: - Store

@MainActor @Observable public class WeightStore {
    /// Shared for the same reason as `TodayStore.shared` — see that comment.
    static let shared = WeightStore()

    var stats = WeightStats()
    var entries: [WeightRow] = []

    /// Loads once when `shared` is first touched — see FoodStore.init.
    init() { reload() }

    func reload() {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            let unit = Preferences.weightUnit
            let history = WeightServiceAPI.getHistory(days: 90).sorted { $0.date > $1.date }
            entries = history.compactMap { e in
                guard let id = e.id else { return nil }
                return WeightRow(id: id, date: e.date,
                                 display: Self.format(kg: e.weightKg, unit: unit))
            }
            var s = WeightStats()
            if let latest = history.first {
                s.current = Self.format(kg: latest.weightKg, unit: unit)
                s.change7d = Self.change(history: history, days: 7, unit: unit)
                s.change30d = Self.change(history: history, days: 30, unit: unit)
            }
            // The trend line needs a few days of data — next to a real current
            // value, "No weight data yet." reads as a bug, so suppress it.
            // describeTrend() ALSO returns that copy itself when the entries
            // span too few days, so filter the sentinel, not just the count.
            let trend = history.count >= 2 ? WeightServiceAPI.describeTrend() : ""
            s.trend = trend.hasPrefix("No weight data") ? "" : trend
            stats = s
        }
    }

    private static func format(kg: Double, unit: WeightUnit) -> String {
        let value = unit == .kg ? kg : kg * 2.20462
        return String(format: "%.1f %@", value, unit.displayName)
    }

    private static func change(history: [WeightEntry], days: Int, unit: WeightUnit) -> String? {
        guard let latest = history.first else { return nil }
        let cutoff = DateFormatters.dateOnly.string(
            from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        guard let past = history.last(where: { $0.date >= cutoff }), past.id != latest.id else { return nil }
        let deltaKg = latest.weightKg - past.weightKg
        let value = unit == .kg ? deltaKg : deltaKg * 2.20462
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value)) \(unit.displayName)"
    }

    func addWeight(_ text: String) {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned) else { return }
        // Read the unit at log time, never from a snapshot: a Settings change
        // between process start and now must decide how this value is stored (#1088).
        let unitName = Preferences.weightUnit.displayName
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            _ = WeightServiceAPI.logWeight(value: value, unit: unitName)
            reload()
            // The dashboard's WEIGHT card reads its own store — without this
            // it kept showing the pre-log value until relaunch (#1090 sweep).
            TodayStore.shared.reload()
        }
    }

    func delete(id: Int64) {
        Task {
            try? AppDatabase.shared.deleteWeightEntry(id: id)
            reload()
            TodayStore.shared.reload()
        }
    }
}

// MARK: - Weight tab

struct WeightTab: View {
    @State var store = WeightStore.shared
    @State var showingAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Stats header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CURRENT").sectionHeading()
                        Text(store.stats.current)
                            .font(Theme.rounded(size: Theme.FontSize.display1).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        if !store.stats.trend.isEmpty {
                            Text(store.stats.trend)
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        HStack(spacing: 12) {
                            if let change = store.stats.change7d {
                                changeChip("7d", change)
                            }
                            if let change = store.stats.change30d {
                                changeChip("30d", change)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    Button { showingAdd = true } label: {
                        Label("Log Weight", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    }.buttonStyle(.plain)

                    // History
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HISTORY").sectionHeading()
                        if store.entries.isEmpty {
                            Text("No weights yet — log your first above")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                        ForEach(store.entries) { row in
                            HStack {
                                Text(row.date).font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(row.display)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                Button { store.delete(id: row.id) } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Weight")
            .onAppear { store.reload() }
            .sheet(isPresented: $showingAdd) {
                // Current unit, evaluated when the sheet presents — not the
                // store's init-time snapshot (#1088).
                AddWeightSheet(unit: Preferences.weightUnit) { text in
                    store.addWeight(text)
                }
            }
        }
    }

    private func changeChip(_ label: String, _ change: String) -> some View {
        // Goal-aware: default goal is losing weight — down = green.
        let isDown = change.hasPrefix("-")
        return HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(change)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isDown ? Theme.deficit : Theme.surplus)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.pillBackground, in: Capsule())
    }
}

struct WeightInputField: View {
    @Binding var text: String
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 8) {
            TextField(unit == .kg ? "72.5" : "160.0", text: $text)
                .textFieldStyle(.roundedBorder)
                // Decimal pad, matching the iOS entry sheet (ios-16
                // ground truth) — was a full QWERTY (#1090 sweep).
                .keyboardType(.decimalPad)
                .font(.title2)
            Text(unit.displayName)
                .font(.headline).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct AddWeightSheet: View {
    let unit: WeightUnit
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Log Weight").font(Theme.fontTitle)
                WeightInputField(text: $text, unit: unit)
                Button {
                    // Validate in the action, not via .disabled — Fuse's
                    // .disabled reactivity on this button was unreliable
                    // (#1091). Save is always tappable; empty/invalid input
                    // is a silent no-op that leaves the sheet open.
                    let cleaned = text.replacingOccurrences(of: ",", with: ".")
                    guard Double(cleaned) != nil else { return }
                    onSave(text)
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
