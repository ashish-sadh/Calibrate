import SwiftUI
import PhotosUI
import DriftCore

/// Capture/edit one progress check-in: up to four pose photos (front / back /
/// left / right) and a set of tape measurements. Photos and measurements are
/// both optional. Two conveniences (operator 2026-07-14):
///  - Weight is pulled from the nearest weight log and shown read-only (weight
///    has its own tracking; no need to re-enter it here).
///  - Measurement fields ghost-fill from the most recent earlier check-in —
///    since most sites don't change week to week, you only edit what moved;
///    untouched ghosts carry forward on save.
struct AddProgressEntryView: View {
    /// When set, edit that day's existing entry; otherwise a new one for today.
    let existingDate: String?

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var photos: [ProgressPose: UIImage] = [:]
    @State private var existingFilenames: [ProgressPose: String] = [:]
    @State private var measurements: [MeasurementSite: String] = [:]
    /// Exact text shown at load per site — so an untouched field re-saves its
    /// ORIGINAL cm value rather than a re-rounded conversion (no drift).
    @State private var loadedText: [MeasurementSite: String] = [:]
    @State private var loadedCm: [MeasurementSite: Double] = [:]
    /// Carried-forward values from the previous check-in, shown as ghost
    /// placeholders; adopted on save when a field is left blank.
    @State private var ghostCm: [MeasurementSite: Double] = [:]
    @State private var notes = ""
    @State private var nearestWeightKg: Double?
    @State private var loadedForDate: String?
    /// True when the loaded date already had a measurement row — suppresses
    /// ghost carry-forward so editing a partial entry never fabricates values
    /// for sites that date never measured.
    @State private var dateHadMeasurement = false

    // Capture routing. The camera lives in ONE `.fullScreenCover(item:)` keyed
    // by the pose so the view carries a single presentation modifier — stacking
    // multiple covers/pickers on one view breaks selection delivery. The photos
    // picker lives on its own nested view (photosSection). The camera itself
    // carries the timer control (Off / 3s / 5s / 10s), so there's one "Take
    // Photo" entry, not a confusing camera-vs-timer split.
    @State private var cameraPose: CameraTarget?
    @State private var showingLibrary = false
    @State private var libraryPose: ProgressPose?
    @State private var libraryItem: PhotosPickerItem?

    struct CameraTarget: Identifiable { let pose: ProgressPose; var id: String { pose.rawValue } }

    /// Entry unit for the measurement fields. Starts from the weight-unit
    /// preference but is flippable in-form ("take whatever" — someone on the
    /// lbs/in preference may know their waist in cm). The parser additionally
    /// honors explicit suffixes ("86cm") regardless of this toggle.
    @State private var entryInInches: Bool = Preferences.weightUnit == .lbs
    /// Site whose how-to-measure guide sheet is showing ("i" on each row).
    @State private var infoSite: MeasurementSite?
    private var inInches: Bool { entryInInches }
    private var unitLabel: String { inInches ? "in" : "cm" }

    /// Flip the form's unit, converting whatever is already typed/loaded so
    /// values keep their meaning (loadedText converts identically, preserving
    /// the untouched-field original-cm guarantee).
    private func toggleEntryUnit() {
        let old = entryInInches
        entryInInches.toggle()
        func convert(_ text: String) -> String {
            guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 else { return text }
            let cm = old ? v * 2.54 : v
            return String(format: "%.1f", entryInInches ? cm / 2.54 : cm)
        }
        for site in MeasurementSite.allCases {
            if let t = measurements[site], !t.isEmpty { measurements[site] = convert(t) }
            if let lt = loadedText[site] { loadedText[site] = convert(lt) }
        }
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if existingDate == nil {
                        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                            .padding(.horizontal, 4)
                    }
                    weightRow
                    photosSection
                    measurementsSection
                    notesSection
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(existingDate == nil ? "New Check-in" : "Edit Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!hasAnything)
                }
                if existingDate != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { deleteEntry() } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete check-in")
                    }
                }
            }
            .fullScreenCover(item: $cameraPose) { target in
                TimerCameraView { image in photos[target.pose] = image }
            }
            .onChange(of: date) { _, _ in loadForCurrentDate() }
            .onAppear(perform: loadForCurrentDate)
        }
    }

    private var hasAnything: Bool {
        // NOTE: ghostCm is intentionally excluded — carried-forward placeholders
        // are not "something the user added", so an untouched new check-in
        // stays un-saveable (no phantom duplicate of the previous entry).
        !photos.isEmpty || !existingFilenames.isEmpty
            || measurements.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            || !notes.isEmpty
    }

    // MARK: - Weight (read-only, auto-pulled)

    @ViewBuilder
    private var weightRow: some View {
        if let kg = nearestWeightKg {
            let shown = Preferences.weightUnit == .lbs ? kg * 2.20462 : kg
            HStack(spacing: 8) {
                Image(systemName: "scalemass").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Text("Weight").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%.1f %@", shown, Preferences.weightUnit.displayName))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHOTOS").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ProgressPose.allCases, id: \.self) { pose in
                    poseTile(pose)
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: Theme.FontSize.micro))
                    .foregroundStyle(Theme.deficit)
                Text("Stored only on this iPhone — never uploaded.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        // Picker lives here (not on the root) so the view carrying the camera
        // cover and the view carrying the picker are different — one
        // presentation modifier each.
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item, let pose = libraryPose else { return }
            Task { await loadLibrary(item, pose: pose) }
        }
    }

    private func poseTile(_ pose: ProgressPose) -> some View {
        let img = photos[pose] ?? existingFilenames[pose].flatMap { ProgressPhotoStore.load($0) }
        return Menu {
            Button { cameraPose = CameraTarget(pose: pose) } label: { Label("Take Photo", systemImage: "camera") }
            Button {
                libraryPose = pose
                // Defer to the next runloop so the Menu finishes dismissing
                // before the picker presents (Menu-dismissal races sheet
                // presentation otherwise).
                DispatchQueue.main.async { showingLibrary = true }
            } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
            if img != nil {
                Button(role: .destructive) { removePhoto(pose) } label: { Label("Remove", systemImage: "trash") }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackgroundElevated)
                if let img {
                    Image(uiImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack { Spacer(); Text(pose.displayName).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white)
                        .padding(6) }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera").font(.title3).foregroundStyle(Theme.textTertiary)
                        Text(pose.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator, lineWidth: 0.5))
        }
    }

    // MARK: - Measurements

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MEASUREMENTS")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                if !ghostCm.isEmpty {
                    Text("· carried from last check-in")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Picker("Unit", selection: Binding(
                    get: { entryInInches },
                    set: { if $0 != entryInInches { toggleEntryUnit() } })) {
                    Text("cm").tag(false)
                    Text("in").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            ForEach(MeasurementSite.Group.allCases, id: \.self) { group in
                let sites = MeasurementSite.displayOrder.filter { $0.group == group }
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.rawValue).font(.caption2.weight(.medium)).foregroundStyle(Theme.textTertiary)
                    ForEach(sites, id: \.self) { site in
                        measurementRow(site)
                    }
                }
            }
        }
        // Own presentation host — the camera fullScreenCover and photosPicker
        // live on OTHER views; stacking presentation modifiers on one view
        // silently breaks delivery (the PhotosPicker field bug).
        .sheet(item: $infoSite) { site in
            MeasurementGuideSheet(site: site)
        }
    }

    private func measurementRow(_ site: MeasurementSite) -> some View {
        let ghost = ghostCm[site].map { String(format: "%.1f", inInches ? $0 / 2.54 : $0) }
        return HStack {
            Text(site.displayName).font(.subheadline)
            Button { infoSite = site } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How to measure \(site.displayName)")
            Spacer()
            TextField(ghost ?? "—", text: Binding(
                get: { measurements[site] ?? "" },
                set: { measurements[site] = $0 }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
            Text(unitLabel).font(.caption).foregroundStyle(Theme.textTertiary).frame(width: 22, alignment: .leading)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(1...3)
                .padding(10)
                .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Capture helpers

    private func loadLibrary(_ item: PhotosPickerItem, pose: ProgressPose) async {
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            await MainActor.run { photos[pose] = image }
        }
        await MainActor.run { libraryPose = nil; libraryItem = nil }
    }

    private func removePhoto(_ pose: ProgressPose) {
        photos[pose] = nil
        existingFilenames[pose] = nil
    }

    // MARK: - Load

    /// Load whatever exists for the currently-selected date, plus ghosts from
    /// the nearest earlier check-in and the nearest weight. Re-runs when the
    /// date picker changes so picking a date that already has data EDITS it
    /// instead of silently overwriting it on save (data-loss bug fix).
    private func loadForCurrentDate() {
        let ds = existingDate ?? dateString
        guard loadedForDate != ds else { return }
        loadedForDate = ds

        if let existingDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: existingDate) { date = d }
        }

        // Reset editable state for the new date.
        photos = [:]; existingFilenames = [:]; measurements = [:]
        loadedText = [:]; loadedCm = [:]; ghostCm = [:]; notes = ""

        for photo in (try? AppDatabase.shared.fetchProgressPhotos(forDate: ds)) ?? [] {
            if let pose = photo.poseEnum, ProgressPhotoStore.fileExists(photo.filename) {
                existingFilenames[pose] = photo.filename
            }
        }
        dateHadMeasurement = false
        if let m = try? AppDatabase.shared.fetchBodyMeasurement(forDate: ds), !m.isEmpty {
            dateHadMeasurement = true
            for site in MeasurementSite.allCases {
                if let cm = m.value(for: site) {
                    let text = String(format: "%.1f", inInches ? cm / 2.54 : cm)
                    measurements[site] = text
                    loadedText[site] = text
                    loadedCm[site] = cm
                }
            }
            notes = m.notes ?? ""
        }
        // Ghost-fill from the most recent measurement STRICTLY BEFORE this date —
        // ONLY for a net-new date. Editing an existing entry must never inherit
        // values for sites that date never measured.
        if !dateHadMeasurement,
           let prev = ((try? AppDatabase.shared.fetchBodyMeasurements()) ?? [])
            .first(where: { $0.date < ds }) {
            for site in MeasurementSite.allCases {
                if let cm = prev.value(for: site) { ghostCm[site] = cm }
            }
        }
        nearestWeightKg = nearestWeight(to: ds)
    }

    /// Nearest logged weight to `ds` within ±14 days (same-day wins).
    private func nearestWeight(to ds: String) -> Double? {
        let entries = (try? AppDatabase.shared.fetchWeightEntries()) ?? []
        guard !entries.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let target = f.date(from: ds) else { return nil }
        var best: (WeightEntry, TimeInterval)?
        for e in entries {
            guard let d = f.date(from: String(e.date.prefix(10))) else { continue }
            let gap = abs(d.timeIntervalSince(target))
            if gap <= 14 * 86_400, best == nil || gap < best!.1 { best = (e, gap) }
        }
        return best?.0.weightKg
    }

    // MARK: - Save

    private func save() {
        let ds = existingDate ?? dateString
        // Photos: write newly-captured ones to disk, keep existing untouched.
        for (pose, image) in photos {
            if let filename = ProgressPhotoStore.save(image, date: ds, pose: pose) {
                var record = ProgressPhoto(date: ds, pose: pose, filename: filename)
                if let replaced = try? AppDatabase.shared.saveProgressPhoto(&record), replaced != filename {
                    ProgressPhotoStore.delete(replaced)
                }
            }
        }
        // Removed existing photos (had a filename, now cleared).
        for photo in (try? AppDatabase.shared.fetchProgressPhotos(forDate: ds)) ?? [] {
            if let pose = photo.poseEnum, existingFilenames[pose] == nil, photos[pose] == nil {
                if let removed = try? AppDatabase.shared.deleteProgressPhoto(id: photo.id ?? -1) {
                    ProgressPhotoStore.delete(removed)
                }
            }
        }
        // Measurements → cm via the pure, tested resolver (drift-avoidance +
        // safe ghost adoption live in DriftCore's BodyMeasurementAnalysis).
        let fields = Dictionary(uniqueKeysWithValues: MeasurementSite.allCases.map { site in
            (site, BodyMeasurementAnalysis.FieldInput(
                enteredText: measurements[site] ?? "",
                loadedText: loadedText[site],
                loadedCm: loadedCm[site],
                ghostCm: ghostCm[site]))
        })
        let cmMap = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: inInches)
        if !cmMap.isEmpty || !notes.isEmpty {
            var m = BodyMeasurement(date: ds, measurementsCm: cmMap, notes: notes.isEmpty ? nil : notes)
            try? AppDatabase.shared.saveBodyMeasurement(&m)
        } else {
            try? AppDatabase.shared.deleteBodyMeasurement(forDate: ds)
        }
        dismiss()
    }

    private func deleteEntry() {
        let ds = existingDate ?? dateString
        let removed = (try? AppDatabase.shared.deleteProgressPhotos(forDate: ds)) ?? []
        ProgressPhotoStore.delete(removed)
        try? AppDatabase.shared.deleteBodyMeasurement(forDate: ds)
        dismiss()
    }
}

// MARK: - How-to-measure guide ("i" on each measurement row)

/// Compact per-site measuring guide: the app's own body figure with the
/// site's region highlighted (consistent visuals, fully offline — no licensed
/// stock imagery exists for this) + the tape placement sentence + the
/// universal consistency tips.
private struct MeasurementGuideSheet: View {
    let site: MeasurementSite
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("How to measure · \(site.displayName)")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("Close")
            }

            HStack(alignment: .center, spacing: 16) {
                MuscleBodyView(side: figureSide, primarySlugs: highlightSlugs)
                    .frame(height: 170)
                Text(site.tapePlacement)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(Theme.separator)

            VStack(alignment: .leading, spacing: 6) {
                Text("For readings you can trust week to week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(MeasurementSite.measuringTips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.caption).foregroundStyle(Theme.textTertiary)
                        Text(tip).font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var highlightSlugs: Set<String> {
        Set(site.highlightMuscles.flatMap { BodyDiagram.librarySlugs(forDriftMuscle: $0) })
    }

    private var figureSide: BodyDiagram.Side {
        BodyDiagram.preferredSide(primaryMuscles: site.highlightMuscles)
    }
}
