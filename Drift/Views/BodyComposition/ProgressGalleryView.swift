import SwiftUI
import DriftCore

/// Progress hub — a photo timeline you can scrub per pose, dated check-in
/// cards, measurement trend charts, and a before/after compare. Follows what
/// the best physique-tracking apps do: watch yourself change over time, not
/// just store isolated snapshots.
struct ProgressGalleryView: View {
    @State private var entries: [ProgressEntry] = []
    @State private var weightByDate: [String: Double] = [:]
    @State private var showingAdd = false
    @State private var showingCompare = false
    @State private var showingCharts = false
    @State private var editingDate: String?
    @State private var timelinePose: ProgressPose = .front

    private var inInches: Bool { Preferences.weightUnit == .lbs }
    private var photoEntries: [ProgressEntry] { entries.filter(\.hasPhotos) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if entries.isEmpty {
                    emptyState
                } else {
                    actionRow
                    if photoEntries.count >= 2 { timelineSection }
                    ForEach(entries, id: \.date) { entry in
                        entryCard(entry)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Progress")
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editingDate = nil; showingAdd = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Add progress check-in")
            }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            AddProgressEntryView(existingDate: editingDate)
        }
        .sheet(isPresented: $showingCompare) {
            ProgressCompareView(entries: photoEntries)
        }
        .sheet(isPresented: $showingCharts) {
            ProgressChartsView(entries: entries, weightByDate: weightByDate)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.stand")
                .font(.system(size: Theme.FontSize.display3))
                .foregroundStyle(Theme.accent.opacity(0.5))
            Text("Track Your Progress")
                .font(.headline)
            Text("Add front, back, and side photos plus tape measurements. Everything stays on your device.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showingAdd = true } label: {
                Label("Add First Check-in", systemImage: "camera.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32).padding(.top, 60)
    }

    // MARK: - Action row (compare + trends)

    private var actionRow: some View {
        HStack(spacing: 8) {
            if photoEntries.count >= 2 {
                actionButton("Compare", icon: "rectangle.split.2x1") { showingCompare = true }
            }
            if entries.contains(where: { $0.measurement?.isEmpty == false }) || weightByDate.count >= 2 {
                actionButton("Trends", icon: "chart.xyaxis.line") { showingCharts = true }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
            .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo timeline scrubber

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIMELINE").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("Pose", selection: $timelinePose) {
                    ForEach(ProgressPose.allCases, id: \.self) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            let posed = photoEntries.compactMap { e -> (String, ProgressPhoto)? in
                e.photo(for: timelinePose).map { (e.date, $0) }
            }.reversed()   // oldest → newest, left to right
            if posed.isEmpty {
                Text("No \(timelinePose.shortName.lowercased()) photos yet.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(posed), id: \.0) { date, photo in
                            Button { editingDate = date; showingAdd = true } label: {
                                VStack(spacing: 4) {
                                    if let img = ProgressPhotoStore.load(photo.filename) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 110, height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Text(shortDate(date)).font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
    }

    // MARK: - Entry card

    private func entryCard(_ entry: ProgressEntry) -> some View {
        Button {
            editingDate = entry.date
            showingAdd = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(formatDate(entry.date)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let kg = weightByDate[entry.date] {
                        let shown = inInches ? kg * 2.20462 : kg
                        Text(String(format: "%.1f %@", shown, Preferences.weightUnit.displayName))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                if entry.hasPhotos {
                    HStack(spacing: 6) {
                        ForEach(ProgressPose.allCases, id: \.self) { pose in
                            poseThumb(entry.photo(for: pose), pose: pose)
                        }
                    }
                }
                if let m = entry.measurement, !m.isEmpty {
                    Text(measurementSummary(m))
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func poseThumb(_ photo: ProgressPhoto?, pose: ProgressPose) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Theme.cardBackgroundElevated)
            if let photo, let img = ProgressPhotoStore.load(photo.filename) {
                Image(uiImage: img).resizable().scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "camera").font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(pose.shortName).font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(height: 84)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func measurementSummary(_ m: BodyMeasurement) -> String {
        MeasurementSite.displayOrder.compactMap { site -> String? in
            guard let cm = m.value(for: site) else { return nil }
            return "\(site.displayName) \(formatCm(cm))"
        }.prefix(4).joined(separator: " · ")
    }

    private func formatCm(_ cm: Double) -> String {
        inInches ? String(format: "%.1f in", cm / 2.54) : String(format: "%.1f cm", cm)
    }

    private func formatDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return "\(months[m]) \(d), \(parts[0])"
    }

    private func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return "\(months[m]) \(d)"
    }

    private func reload() {
        // Sanitize: drop photo rows whose file is missing (e.g. a partial
        // restore) so the gallery never shows blank thumbnails or offers a
        // compare with no image.
        let raw = (try? AppDatabase.shared.fetchProgressEntries()) ?? []
        entries = raw.map { e in
            ProgressEntry(date: e.date,
                          photos: e.photos.filter { ProgressPhotoStore.fileExists($0.filename) },
                          measurement: e.measurement)
        }.filter { $0.hasPhotos || $0.measurement?.isEmpty == false }

        // Nearest logged weight per entry date (±14 days).
        let weights = (try? AppDatabase.shared.fetchWeightEntries()) ?? []
        weightByDate = [:]
        guard !weights.isEmpty else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        for entry in entries {
            guard let target = f.date(from: entry.date) else { continue }
            var best: (Double, TimeInterval)?
            for w in weights {
                guard let d = f.date(from: String(w.date.prefix(10))) else { continue }
                let gap = abs(d.timeIntervalSince(target))
                if gap <= 14 * 86_400, best == nil || gap < best!.1 { best = (w.weightKg, gap) }
            }
            if let best { weightByDate[entry.date] = best.0 }
        }
    }
}
