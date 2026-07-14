import SwiftUI
import DriftCore

/// Side-by-side before/after comparison of two check-ins — the payoff feature
/// of progress tracking. Pick two dates, flip through the four poses, and read
/// the measurement deltas below.
struct ProgressCompareView: View {
    let entries: [ProgressEntry]   // only entries with photos, newest first

    @Environment(\.dismiss) private var dismiss
    @State private var beforeIndex = 0
    @State private var afterIndex = 0
    @State private var pose: ProgressPose = .front

    private var inInches: Bool { Preferences.weightUnit == .lbs }

    init(entries: [ProgressEntry]) {
        self.entries = entries
        // Default: oldest as "before", newest as "after".
        _beforeIndex = State(initialValue: max(0, entries.count - 1))
        _afterIndex = State(initialValue: 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    posePicker
                    photoPair
                    datePickers
                    if let deltas = measurementDeltas, !deltas.isEmpty {
                        deltaTable(deltas)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var posePicker: some View {
        Picker("Pose", selection: $pose) {
            ForEach(ProgressPose.allCases, id: \.self) { Text($0.shortName).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var photoPair: some View {
        HStack(spacing: 8) {
            photoColumn(entry: entries[safe: beforeIndex], label: "Before")
            photoColumn(entry: entries[safe: afterIndex], label: "After")
        }
    }

    private func photoColumn(entry: ProgressEntry?, label: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackgroundElevated)
                if let entry, let photo = entry.photo(for: pose), let img = ProgressPhotoStore.load(photo.filename) {
                    Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "camera").foregroundStyle(Theme.textTertiary)
                        Text("No \(pose.shortName.lowercased()) shot").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            if let entry { Text(shortDate(entry.date)).font(.caption2).foregroundStyle(Theme.textTertiary) }
        }
    }

    private var datePickers: some View {
        HStack(spacing: 8) {
            dateMenu(binding: $beforeIndex, label: "Before")
            dateMenu(binding: $afterIndex, label: "After")
        }
    }

    private func dateMenu(binding: Binding<Int>, label: String) -> some View {
        Menu {
            ForEach(entries.indices, id: \.self) { i in
                Button(shortDate(entries[i].date)) { binding.wrappedValue = i }
            }
        } label: {
            HStack {
                Text(entries[safe: binding.wrappedValue].map { shortDate($0.date) } ?? "—")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.separator, lineWidth: 0.5))
        }
    }

    // MARK: - Measurement deltas

    private var measurementDeltas: [BodyMeasurementAnalysis.SiteDelta]? {
        guard let before = entries[safe: beforeIndex]?.measurement,
              let after = entries[safe: afterIndex]?.measurement else { return nil }
        return BodyMeasurementAnalysis.deltas(from: before, to: after)
    }

    private func deltaTable(_ deltas: [BodyMeasurementAnalysis.SiteDelta]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEASUREMENT CHANGE").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            ForEach(deltas, id: \.site) { d in
                HStack {
                    Text(d.site.displayName).font(.subheadline)
                    Spacer()
                    Text(fmtVal(d.previousCm)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(fmtVal(d.currentCm)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text(fmtChange(d.changeCm))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(d.changeCm == 0 ? Theme.textTertiary : (d.changeCm < 0 ? Theme.deficit : Theme.stepsOrange))
                        .frame(width: 56, alignment: .trailing)
                }
                if d.site != deltas.last?.site { Divider().overlay(Theme.separator.opacity(0.5)) }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
    }

    // MARK: - Helpers

    private func fmtVal(_ cm: Double) -> String {
        String(format: "%.1f", inInches ? cm / 2.54 : cm)
    }
    private func fmtChange(_ cm: Double) -> String {
        let v = inInches ? cm / 2.54 : cm
        if abs(v) < 0.05 { return "—" }
        return "\(v < 0 ? "−" : "+")\(String(format: "%.1f", abs(v)))"
    }
    private func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return "\(months[m]) \(d)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
