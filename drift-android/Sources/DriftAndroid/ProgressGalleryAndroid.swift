import SwiftUI
import DriftCore

/// Android's Progress-photo timeline (#1121). Read-only for now: it shows the
/// check-in cards the operator's iPhone shows — date, weight, the 4-up pose
/// row, and the headline measurement — reusing `ProgressPhotoImage` so both
/// platforms load the identical on-device JPEGs.
///
/// CAPTURE is deliberately out of scope here: iOS's AddProgressEntryView is
/// built on PhotosPicker + the camera, which need an Android permission +
/// Activity-result seam (tracked with the rest of capture logging, #1063).
/// Until that lands, photos taken on iPhone appear here after a restore, and
/// the empty state says so rather than offering a dead "+".
struct ProgressGalleryAndroid: View {
    @State var entries: [Entry] = []
    @State var loaded = false

    struct Entry: Identifiable, Sendable {
        let id: String            // date
        let date: String
        let photos: [ProgressPhoto]
        let weightDisplay: String?
        let measurementLine: String?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2).foregroundStyle(Theme.deficit)
                        Text("Photos never leave your device — not uploaded, not analyzed in the cloud.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }

                    if entries.isEmpty && loaded {
                        emptyState
                    }

                    ForEach(entries) { entry in
                        entryCard(entry)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Progress")
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No progress photos yet")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            Text("Capture arrives with photo logging on Android. Photos taken on iPhone show up here after a restore.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func entryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.date).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let w = entry.weightDisplay {
                    Text(w).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(entry.photos) { photo in
                    ProgressPhotoImage(filename: photo.filename)
                        .frame(width: 74, height: 98)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
            }
            if let line = entry.measurementLine {
                Text(line).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// DB + file-existence checks off the main actor — the gallery can hold a
    /// year of check-ins and `fileExists` is a syscall per photo.
    private func load() async {
        await CoreResourcesBootstrap.warmUpDatabase()
        let unit = Preferences.weightUnit
        let rows: [Entry] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let photos = (try? AppDatabase.shared.fetchProgressPhotos()) ?? []
                let measurements = (try? AppDatabase.shared.fetchBodyMeasurements()) ?? []
                let weights = WeightServiceAPI.getHistory(days: 3650)

                let byDate = Dictionary(grouping: photos.filter { ProgressPhotoPaths.fileExists($0.filename) },
                                        by: { $0.date })
                let built = byDate.keys.sorted(by: >).map { date -> Entry in
                    let posed = byDate[date]?.sorted { lhs, rhs in
                        (ProgressPose.allCases.firstIndex(of: lhs.poseEnum ?? .front) ?? 0)
                            < (ProgressPose.allCases.firstIndex(of: rhs.poseEnum ?? .front) ?? 0)
                    } ?? []
                    let kg = weights.first { $0.date == date }?.weightKg
                    let weightDisplay = kg.map { value -> String in
                        let shown = unit == .kg ? value : value * 2.20462
                        return String(format: "%.1f %@", shown, unit.displayName)
                    }
                    let measurement = measurements.first { $0.date == date }
                    return Entry(id: date, date: date, photos: posed,
                                 weightDisplay: weightDisplay,
                                 measurementLine: measurement.flatMap(Self.headlineMeasurement))
                }
                continuation.resume(returning: built)
            }
        }
        entries = rows
        loaded = true
    }

    /// One line, matching what iOS surfaces under the thumbnails ("Chest 33.6 in").
    /// Measurements are stored in cm keyed by `MeasurementSite.rawValue`.
    /// `nonisolated` — this runs inside the off-main load closure.
    nonisolated private static func headlineMeasurement(_ m: BodyMeasurement) -> String? {
        guard let chestCm = m.measurementsCm[MeasurementSite.chest.rawValue] else { return nil }
        return String(format: "Chest %.1f in", chestCm / 2.54)
    }
}
