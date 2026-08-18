import SwiftUI
import DriftCore

/// Android's Progress-photo timeline (#1121). Shows the check-in cards the
/// operator's iPhone shows — formatted date, the nearest weigh-in within ±14
/// days, the pose row, and the measurement summary — off the same
/// `fetchProgressEntries()` query iOS reads (#1186), reusing
/// `ProgressPhotoImage` so both platforms load the identical on-device JPEGs.
///
/// The toolbar "+" adds a photo through the `DriftPlatform.imagePicker` seam
/// (#1128) — v1 is deliberately front-pose/today with no measurements; full
/// parity with iOS's AddProgressEntryView (4 poses + measurements + weight)
/// is a tracked follow-up, not a silent gap. Camera capture stays out until
/// its own Activity-result seam lands (#1063).
struct ProgressGalleryAndroid: View {
    @State var entries: [Entry] = []
    @State var loaded = false
    @State var picking = false
    /// Viewer state (#1187). `viewerEntries` is the photo-bearing subset iOS
    /// hands the viewer (`ProgressGalleryView.swift:23,61`); both it and the
    /// weight map are computed in the same off-main pass as the cards.
    @State var viewerEntries: [ProgressEntry] = []
    @State var weightByDate: [String: Double] = [:]
    @State var viewerDate: String?
    @State var viewerPose: ProgressPose = .front

    struct Entry: Identifiable, Sendable {
        let id: String            // date
        let date: String          // "YYYY-MM-DD" — the ±14d weight match keys off this
        let dateDisplay: String   // "Jul 14, 2026" — formatted off-main
        let photos: [ProgressPhoto]
        let weightDisplay: String?
        let measurementLine: String?
    }

    /// Everything one `load()` pass produces. Bundled so the cards, the viewer's
    /// date list and the weight map all come off a single sanitized read.
    struct Payload: Sendable {
        let cards: [Entry]
        let viewerEntries: [ProgressEntry]
        let weightByDate: [String: Double]
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard !picking else { return }
                        Task { await addPhoto() }
                    } label: {
                        Image(systemName: sym("plus"))
                    }
                    .accessibilityLabel("Add a progress photo")
                }
            }
        }
        // The gallery's ONLY presentation modifier — stacking two on one view is
        // the Fuse trap this screen already ate (see WeightSheetRequest). The
        // builder is guarded because Fuse builds cover content eagerly.
        .fullScreenCover(isPresented: Binding(
            get: { viewerDate != nil },
            set: { if !$0 { viewerDate = nil } }
        )) {
            if let date = viewerDate {
                ProgressPhotoViewerAndroid(
                    entries: viewerEntries, weightByDate: weightByDate,
                    startDate: date, startPose: viewerPose,
                    // iOS routes this to AddProgressEntryView; the Android edit
                    // flow lands with #1166, so the viewer hides its pencil and
                    // this stays an unused seam rather than a dead tap.
                    onEdit: { _ in })
            }
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No progress photos yet")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            Text("Tap + to add a photo from your library. Photos taken on iPhone show up here after a restore.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    /// v1 capture (#1128 proof): library pick → front pose, today. 1440/q0.82
    /// matches iOS ProgressPhotoStore's persist settings. File write + DB
    /// insert run off-main; `load()` re-renders the gallery with the new card.
    private func addPhoto() async {
        picking = true
        defer { picking = false }
        guard let data = await DriftPlatform.imagePicker?.pickLibraryImage(maxLongEdge: 1440, quality: 0.82),
              !data.isEmpty else { return }
        logger.info("ProgressGalleryAndroid: picked \(data.count) bytes")
        // DateFormatters.todayString is the repo's pinned local-day formatter —
        // a bare DateFormatter() is UTC on Android and would file the photo
        // under the wrong day (android_foundation_utc_dateformatter).
        let today = DateFormatters.todayString
        let filename = "\(today)_\(ProgressPose.front.rawValue).jpg" // stable per (date,pose), mirrors ProgressPhotoStore
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                try? data.write(to: ProgressPhotoPaths.url(for: filename), options: .atomic)
                var rec = ProgressPhoto(date: today, pose: .front, filename: filename)
                _ = try? AppDatabase.shared.saveProgressPhoto(&rec)
                continuation.resume()
            }
        }
        await load()
    }

    private func entryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.dateDisplay)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let w = entry.weightDisplay {
                    Text(w).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            // A measurement-only check-in has no photos at all (iOS :207) —
            // don't leave an empty row's spacing behind it.
            if !entry.photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(entry.photos) { photo in
                        ProgressPhotoImage(filename: photo.filename)
                            .frame(width: 74, height: 98)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            // A thumbnail renders as content, not a Button, so
                            // without contentShape the tap lands nowhere at all
                            // (#1187 — the screen after the tap was pixel-identical).
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewerPose = photo.poseEnum ?? .front
                                viewerDate = entry.date
                            }
                            .accessibilityLabel("Open \(entry.dateDisplay) photo")
                    }
                }
            }
            if let line = entry.measurementLine {
                // Matches iOS :216-217. NOTE: a long line (4 sites in cm) clips
                // without the "…" iOS shows — Fuse marks .truncationMode
                // @available(*, unavailable), so there is no call-site fix.
                // Tracked app-wide as #1237.
                Text(line).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
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
        let inInches = unit == .lbs
        let payload: Payload = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // The same source iOS reload() reads (ProgressGalleryView:288):
                // a day's photos AND that day's measurement. Grouping raw photos
                // — what this used to do — dropped tape-only check-ins entirely.
                let raw = (try? AppDatabase.shared.fetchProgressEntries()) ?? []
                let weights = (try? AppDatabase.shared.fetchWeightEntries()) ?? []

                // Sanitize once — iOS :289-293. Photo rows whose file is missing
                // (a partial restore) are dropped so neither a card thumbnail nor
                // a compare pane can come up blank. fetchProgressEntries() is
                // documented newest-first; keep its order.
                let sanitized: [ProgressEntry] = raw.compactMap { entry -> ProgressEntry? in
                    let posed = entry.photos
                        .filter { ProgressPhotoPaths.fileExists($0.filename) }
                        .sorted { lhs, rhs in
                            (ProgressPose.allCases.firstIndex(of: lhs.poseEnum ?? .front) ?? 0)
                                < (ProgressPose.allCases.firstIndex(of: rhs.poseEnum ?? .front) ?? 0)
                        }
                    guard !posed.isEmpty || entry.measurement?.isEmpty == false else { return nil }
                    return ProgressEntry(date: entry.date, photos: posed, measurement: entry.measurement)
                }

                // iOS :295-309 — the viewer reads raw kg and formats per pose, so
                // the map is built once and the card's string derives from it.
                var weightMap: [String: Double] = [:]
                for entry in sanitized {
                    if let kg = Self.nearestWeightKg(for: entry.date, in: weights) {
                        weightMap[entry.date] = kg
                    }
                }

                let built = sanitized.map { entry -> Entry in
                    let weightDisplay = weightMap[entry.date].map { value -> String in
                        let shown = inInches ? value * 2.20462 : value
                        return String(format: "%.1f %@", shown, unit.displayName)
                    }
                    let line = entry.measurement.flatMap { m -> String? in
                        let summary = Self.measurementSummary(m, inInches: inInches)
                        return summary.isEmpty ? nil : summary
                    }
                    return Entry(id: entry.date, date: entry.date,
                                 dateDisplay: Self.formatDate(entry.date),
                                 photos: entry.photos,
                                 weightDisplay: weightDisplay,
                                 measurementLine: line)
                }
                continuation.resume(returning: Payload(
                    cards: built,
                    viewerEntries: sanitized.filter(\.hasPhotos),
                    weightByDate: weightMap))
            }
        }
        entries = payload.cards
        viewerEntries = payload.viewerEntries
        weightByDate = payload.weightByDate
        loaded = true
    }

    // MARK: - Display helpers
    //
    // Ports of iOS ProgressGalleryView.swift:255-273 and its ±14-day
    // nearest-weight loop (:295-309). `nonisolated static` — they run inside
    // the off-main load closure.

    /// Up to 4 sites in `MeasurementSite.displayOrder`, unit following the
    /// user's weight preference — iOS :255-264. (Was: chest only, always in
    /// inches, which hid every other site a user measured.)
    nonisolated static func measurementSummary(_ m: BodyMeasurement, inInches: Bool) -> String {
        MeasurementSite.displayOrder.compactMap { site -> String? in
            guard let cm = m.value(for: site) else { return nil }
            return "\(site.displayName) \(formatCm(cm, inInches: inInches))"
        }.prefix(4).joined(separator: " · ")
    }

    nonisolated static func formatCm(_ cm: Double, inInches: Bool) -> String {
        inInches ? String(format: "%.1f in", cm / 2.54) : String(format: "%.1f cm", cm)
    }

    /// "2026-07-14" → "Jul 14, 2026" — iOS :266-273. Pure string work, so no
    /// DateFormatter and no UTC hazard (android_foundation_utc_dateformatter).
    nonisolated static func formatDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return "\(months[m]) \(d), \(parts[0])"
    }

    /// The nearest weigh-in within ±14 days of a check-in, iOS :300-309. People
    /// rarely weigh in on the day they shoot photos, so an exact-date match —
    /// what this used to do — showed no weight on almost every card.
    nonisolated static func nearestWeightKg(for date: String, in weights: [WeightEntry]) -> Double? {
        guard let target = dayNumber(date) else { return nil }
        var best: (kg: Double, gap: Int)?
        for w in weights {
            guard let day = dayNumber(String(w.date.prefix(10))) else { continue }
            let gap = abs(day - target)
            if gap <= 14, best == nil || gap < best!.gap { best = (w.weightKg, gap) }
        }
        return best?.kg
    }

    /// Days since 1970-01-01 for a "YYYY-MM-DD" string (days-from-civil).
    /// iOS parses both sides with a DateFormatter; integer arithmetic gives the
    /// identical gap without paying a formatter parse per (check-in × weigh-in)
    /// and without the Android UTC default mattering at all.
    nonisolated static func dayNumber(_ dateStr: String) -> Int? {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                                       // [0, 399]
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1   // [0, 365]
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
