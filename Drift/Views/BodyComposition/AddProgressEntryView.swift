import SwiftUI
import PhotosUI
import DriftCore

/// Capture/edit one progress check-in: up to four pose photos (front / back /
/// left / right) and a set of tape measurements. Photos and measurements are
/// both optional — you can log just photos, just numbers, or both.
struct AddProgressEntryView: View {
    /// When set, edit that day's existing entry; otherwise a new one for today.
    let existingDate: String?

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var photos: [ProgressPose: UIImage] = [:]
    @State private var existingFilenames: [ProgressPose: String] = [:]
    @State private var measurements: [MeasurementSite: String] = [:]
    @State private var notes = ""

    // Capture routing
    @State private var capturePose: ProgressPose?
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var libraryPose: ProgressPose?

    private var inInches: Bool { Preferences.weightUnit == .lbs }
    private var unitLabel: String { inInches ? "in" : "cm" }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if existingDate == nil {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .padding(.horizontal, 4)
                    }
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
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { image in
                    if let pose = capturePose { photos[pose] = image }
                }
            }
            .photosPicker(isPresented: Binding(get: { libraryPose != nil }, set: { if !$0 { libraryPose = nil } }),
                          selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item, let pose = libraryPose else { return }
                Task { await loadLibrary(item, pose: pose) }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var hasAnything: Bool {
        !photos.isEmpty || !existingFilenames.isEmpty || measurements.values.contains { !$0.isEmpty }
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
        }
    }

    private func poseTile(_ pose: ProgressPose) -> some View {
        let img = photos[pose] ?? existingFilenames[pose].flatMap { ProgressPhotoStore.load($0) }
        return Menu {
            Button { capturePose = pose; requestCamera() } label: { Label("Take Photo", systemImage: "camera") }
            Button { libraryPose = pose } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
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
            Text("MEASUREMENTS (\(unitLabel.uppercased()))")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
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
    }

    private func measurementRow(_ site: MeasurementSite) -> some View {
        HStack {
            Text(site.displayName).font(.subheadline)
            Spacer()
            TextField("—", text: Binding(
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

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { showingCamera = true; return }
        showingCamera = true
    }

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

    // MARK: - Load / save

    private func loadExisting() {
        guard let existingDate else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        if let d = f.date(from: existingDate) { date = d }
        for photo in (try? AppDatabase.shared.fetchProgressPhotos(forDate: existingDate)) ?? [] {
            if let pose = photo.poseEnum { existingFilenames[pose] = photo.filename }
        }
        if let m = try? AppDatabase.shared.fetchBodyMeasurement(forDate: existingDate) {
            for site in MeasurementSite.allCases {
                if let cm = m.value(for: site) {
                    let shown = inInches ? cm / 2.54 : cm
                    measurements[site] = String(format: "%.1f", shown)
                }
            }
            notes = m.notes ?? ""
        }
    }

    private func save() {
        let ds = dateString
        // Photos: write newly-captured ones to disk, keep existing untouched.
        for (pose, image) in photos {
            if let filename = ProgressPhotoStore.save(image, date: ds, pose: pose) {
                var record = ProgressPhoto(date: ds, pose: pose, filename: filename)
                if let replaced = try? AppDatabase.shared.saveProgressPhoto(&record),
                   replaced != filename {
                    ProgressPhotoStore.delete(replaced)
                }
            }
        }
        // Removed existing photos (had a filename, now cleared).
        if let existingDate {
            for photo in (try? AppDatabase.shared.fetchProgressPhotos(forDate: existingDate)) ?? [] {
                if let pose = photo.poseEnum, existingFilenames[pose] == nil, photos[pose] == nil {
                    if let removed = try? AppDatabase.shared.deleteProgressPhoto(id: photo.id ?? -1) {
                        ProgressPhotoStore.delete(removed)
                    }
                }
            }
        }
        // Measurements → cm.
        var cmMap: [String: Double] = [:]
        for (site, text) in measurements {
            let normalized = text.replacingOccurrences(of: ",", with: ".")
            guard let shown = Double(normalized), shown > 0 else { continue }
            cmMap[site.rawValue] = inInches ? shown * 2.54 : shown
        }
        if !cmMap.isEmpty || !notes.isEmpty {
            var m = BodyMeasurement(date: ds, measurementsCm: cmMap, notes: notes.isEmpty ? nil : notes)
            try? AppDatabase.shared.saveBodyMeasurement(&m)
        } else if existingDate != nil {
            try? AppDatabase.shared.deleteBodyMeasurement(forDate: ds)
        }
        dismiss()
    }

    private func deleteEntry() {
        guard let existingDate else { return }
        let removed = (try? AppDatabase.shared.deleteProgressPhotos(forDate: existingDate)) ?? []
        ProgressPhotoStore.delete(removed)
        try? AppDatabase.shared.deleteBodyMeasurement(forDate: existingDate)
        dismiss()
    }
}
