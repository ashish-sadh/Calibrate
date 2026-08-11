import SwiftUI
import DriftCore

// Android-only (not SharedUI): the Snap capture→analyze→review→log flow
// (#1111), the photo sibling of DescribeMealSheet (#1101, text). iOS keeps
// its own mature PhotoLogFlowView/PhotoLogReviewView (UIKit-bound, richer);
// this is Android's equivalent on the shared DriftCore vision pipeline,
// reusing DescribeMealSheet's review-row style verbatim (two similar rows,
// not yet a third — no shared component extracted).
//
// Two capture buttons rather than an embedded camera preview: SkipUI has no
// proven native-camera-preview-in-Compose-from-Swift interop, and the
// ActivityResult contracts (TakePicture / PickVisualMedia) deliver the same
// outcome with zero new surface risk. "Take Photo" = CameraCaptureService
// (#1111, new); "Choose from Library" = DriftPlatform.imagePicker (#1128,
// already shipped, reused as-is).
struct SnapMealSheet: View {
    @Environment(\.dismiss) var dismiss
    let onLogged: () -> Void

    @State var foodLog = FoodLogViewModel()
    @State var phase: Phase = .capture
    @State var capturedImage: Data?
    @State var items: [PhotoLogItem] = []
    @State var logTime = Date()
    @State var mealType: MealType = .snack

    enum Phase: Equatable {
        case capture, analyzing, reviewing
        /// The cloud looked and found no food. iOS keeps this separate from
        /// `.error` (`PhotoLogFlowView.emptyView` vs `errorView`) and so do we:
        /// nothing went wrong, so it gets a neutral glyph and "take another"
        /// rather than a red warning triangle and "try again". #1195
        case empty
        case error(String)
    }

    private enum CaptureSource {
        case camera, library
    }

    init(onLogged: @escaping () -> Void = {}) {
        self.onLogged = onLogged
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // In-content chrome (#1089 pattern) — sheet nav bar off. iOS
                // gets its "Photo Log" title + Cancel from a real inline nav
                // bar; SkipUI's costs an ~80dp dead band inside a sheet, so
                // the same two elements are drawn as content. The pill behind
                // Cancel is the chrome iOS 26 paints for toolbar text buttons
                // (same treatment as TemplatePreviewSheet / ActiveWorkoutView).
                ZStack {
                    Text("Photo Log")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    HStack {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Theme.pillBackground, in: Capsule())
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                switch phase {
                case .capture: captureView
                case .analyzing: analyzingView
                case .reviewing: reviewView
                case .empty: emptyView
                case .error(let message): errorView(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .onAppear {
                // Fresh session every presentation — the same #1106 lesson
                // DescribeMealSheet already learned: Fuse can keep the
                // sheet's view identity across presentations, which would
                // otherwise resurrect a stale capture or cancelled parse.
                phase = .capture
                items = []
                capturedImage = nil
                logTime = Date()
            }
        }
    }

    // MARK: - Capture

    /// Line-for-line port of iOS `PhotoLogCaptureView.body` (#1111): header
    /// block top-anchored, cloud banner under it, then the capture buttons
    /// floated between two Spacers. The prior Android layout centred the
    /// title and pinned the buttons to the bottom, which read as a different
    /// app (gap sweep, 2026-08-04).
    private var captureView: some View {
        VStack(spacing: 16) {
            header
            cloudBanner
            Spacer()
            captureButtons
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var header: some View {
        VStack(spacing: 6) {
            // 58pt frame ≈ iOS's 44pt `.light` SF `camera`, which draws ~50pt
            // wide (SF Symbols run ~1.15× their point size); CameraShape fills
            // 20 of its 24 design units, so 58 × 20/24 ≈ 48pt.
            CameraShape()
                .stroke(Theme.textSecondary, lineWidth: 1.7)
                .frame(width: 58, height: 58)
            Text("Snap a meal to log it")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Photo Log uses cloud AI to identify what's on your plate.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// iOS's `infoBanner` in its has-a-key form. Android has no key UI at all
    /// (directive 0-AI-FOCUS) so the BYOK half is dropped, but the banner
    /// itself stays: Drift's privacy tenet is that every cloud touchpoint is
    /// surfaced explicitly, and this is the one screen that ships a photo off
    /// the device. Copy is Android-true rather than iOS-verbatim because the
    /// iOS string names the user's own provider and its per-photo price,
    /// neither of which exists here.
    private var cloudBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            // iOS draws SF `cloud` here. skip-ui's Material map has no cloud,
            // globe or wifi glyph at all, and the operator's standing rule is
            // closest-mapped-icon over a hand-drawn Path (2026-07-28), so
            // sym() sends this to info.circle: neutral, truthful for an info
            // banner, and it can't be misread as a security claim the way a
            // padlock could.
            Image(systemName: sym("cloud"))
                .foregroundStyle(Theme.textTertiary)
            Text("Photo is sent to Drift's cloud AI to identify what's on your plate. Nothing else leaves your phone.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        .accessibilityIdentifier("photo-log-privacy-banner")
    }

    /// iOS: Take Photo is `.borderedProminent`/`.tint(Theme.ink)` (black
    /// capsule, white label); Library + barcode are `.bordered`/
    /// `.tint(Theme.textPrimary)` (gray capsules). Android had both as white
    /// rounded cards — the shape and the fill were both wrong.
    ///
    /// 7pt vertical padding, not 12: an iOS `.bordered` button measures ~34pt
    /// tall on the reference screenshot, and Compose's own text line box is
    /// already ~21dp, so 12 gave a 45dp slab that read visibly chunkier than
    /// iPhone. Barcode is the missing third button — seam filed as #1206.
    private var captureButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await capture(from: .camera) }
            } label: {
                HStack(spacing: 8) {
                    CameraShape().stroke(.white, lineWidth: 1.7).frame(width: 20, height: 20)
                    Text("Take Photo").font(.body.weight(.medium)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("snap-meal-take-photo")

            Button {
                Task { await capture(from: .library) }
            } label: {
                HStack(spacing: 8) {
                    PhotoStackShape().stroke(Theme.textPrimary, lineWidth: 1.7).frame(width: 20, height: 20)
                    Text("Choose from Library").font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.pillBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("snap-meal-choose-library")
        }
    }

    // MARK: - Analyzing

    /// Ported from iOS `PhotoLogFlowView.analyzingView` — same copy, same
    /// 1.4× accent spinner. Android previously showed a bare spinner and
    /// "Reading your plate…", with no sense of how long the wait is.
    private var analyzingView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().scaleEffect(1.4).tint(Theme.accent)
            Text("Analyzing your meal…")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("One photo → one call. Usually 3–6 seconds.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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

    // MARK: - Empty

    /// Ported from iOS `PhotoLogFlowView.emptyView` — same copy, same neutral
    /// tertiary glyph, same single "Take another" action. The cloud answered;
    /// it just didn't see food. Re-sending the identical bytes ("Try Again")
    /// would only spend a second call to get the same answer, so this state
    /// deliberately offers ONLY a retake, exactly as iOS does.
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            // questionmark.circle → info.circle on Android (see Symbols.swift).
            // Explicitly NOT the warning triangle: nothing failed here.
            Image(systemName: sym("questionmark.circle"))
                .font(.largeTitle)
                .foregroundStyle(Theme.textTertiary)
            Text("We couldn't spot any food in that photo.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Try one with the meal centered and in good light.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Take another") {
                capturedImage = nil
                phase = .capture
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Error

    /// iOS `PhotoLogFlowView.errorView`: the triangle IS the right glyph here
    /// (something genuinely failed) and iOS draws it in `Theme.surplus`, not
    /// tertiary — the colour is what separates "this broke" from the neutral
    /// empty state above. Android keeps the extra Retake affordance because
    /// re-sending the same bytes is the likelier fix for a transport blip.
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: sym("exclamationmark.bubble"))
                .font(.largeTitle)
                .foregroundStyle(Theme.surplus)
            Text(message)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                if let data = capturedImage {
                    Task { await analyze(data) }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 8)
            Button("Retake Photo") {
                capturedImage = nil
                phase = .capture
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Capture → analyze

    private func capture(from source: CaptureSource) async {
        let data: Data?
        switch source {
        case .camera:
            data = await CameraCaptureService().captureImage(maxLongEdge: 1024, quality: 0.7)
        case .library:
            data = await DriftPlatform.imagePicker?.pickLibraryImage(maxLongEdge: 1024, quality: 0.7)
        }
        // Cancel (permission denial, picker dismiss, capture failure) — stay
        // on the capture screen so the user can just try the other button.
        guard let data, !data.isEmpty else { return }
        capturedImage = data
        await analyze(data)
    }

    private func analyze(_ data: Data) async {
        FeatureUsage.record(TelemetryEvent.snapUsed)
        phase = .analyzing
        let started = Date()

        // No on-device vision fallback for photos (unlike Describe's text
        // path) — 0-AI-LADDER still holds: honest error, never a silent
        // local guess.
        guard let resp = await NebiusMealPhotoLogger.parse(imageData: data, visionModelID: AppConfig.coachVisionModelID) else {
            // nil = network/cloud failure, distinct from a valid "no food
            // visible" response — only THIS case is a connectivity claim.
            recordTurn(items: [], outcome: "error", started: started)
            phase = .error("Couldn't reach the cloud — check your connection and try again.")
            return
        }
        guard !resp.items.isEmpty else {
            recordTurn(items: [], outcome: "empty", started: started)
            phase = .empty
            return
        }

        recordTurn(items: resp.items, outcome: "success", started: started)
        items = resp.items
        mealType = foodLog.autoMealType
        logTime = Date()
        phase = .reviewing
    }

    /// Telemetry for the Snap surface — mirrors Describe's `recordTurn`, `query`
    /// is nil (there is no text query for a photo turn). A rising error rate
    /// here means the vision round-trip itself is unreliable, not a routing gap.
    private func recordTurn(items: [PhotoLogItem], outcome: String, started: Date) {
        let summary = items
            .map(\.telemetrySummary)
            .joined(separator: "\n")
        TelemetryService.shared.aiTurn(
            surface: TelemetrySurface.snapMeal,
            query: nil,
            response: summary.isEmpty ? nil : summary,
            outcome: outcome,
            latencyMS: (Date().timeIntervalSince(started) * 1000).rounded().safeInt)
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
