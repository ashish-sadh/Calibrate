import SwiftUI
import DriftCore

/// Progress hub — a timeline of photo + measurement check-ins, an add button,
/// and a compare entry point. Follows the shape of the best physique-tracking
/// apps: dated entries with a 4-pose thumbnail strip and the headline
/// measurement, tap into an entry, or compare any two dates side by side.
struct ProgressGalleryView: View {
    @State private var entries: [ProgressEntry] = []
    @State private var showingAdd = false
    @State private var showingCompare = false
    @State private var editingDate: String?

    private var inInches: Bool { Preferences.weightUnit == .lbs }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if entries.isEmpty {
                    emptyState
                } else {
                    if entries.filter(\.hasPhotos).count >= 2 {
                        compareButton
                    }
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
            ProgressCompareView(entries: entries.filter(\.hasPhotos))
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

    // MARK: - Compare CTA

    private var compareButton: some View {
        Button { showingCompare = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                Text("Compare check-ins").font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
            .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
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
                    if let m = entry.measurement, let waist = m.value(for: .waist) {
                        Text("Waist \(formatCm(waist))")
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
        if inInches {
            return String(format: "%.1f in", cm / 2.54)
        }
        return String(format: "%.1f cm", cm)
    }

    private func formatDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return "\(months[m]) \(d), \(parts[0])"
    }

    private func reload() {
        entries = (try? AppDatabase.shared.fetchProgressEntries()) ?? []
    }
}
