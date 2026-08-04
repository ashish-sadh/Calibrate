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
                // In-content chrome (#1089 pattern) — sheet nav bar off.
                HStack {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                switch phase {
                case .capture: captureView
                case .analyzing: analyzingView
                case .reviewing: reviewView
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

    private var captureView: some View {
        VStack(spacing: 22) {
            Spacer()

            Text("Snap your meal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Take a photo of your plate, or pick one from your gallery")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await capture(from: .camera) }
                } label: {
                    HStack(spacing: 10) {
                        CameraShape().stroke(Theme.textPrimary, lineWidth: 1.7).frame(width: 20, height: 20)
                        Text("Take Photo").font(.headline).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusControl)
                            .stroke(Theme.separator, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snap-meal-take-photo")

                Button {
                    Task { await capture(from: .library) }
                } label: {
                    HStack(spacing: 10) {
                        PhotoStackShape().stroke(Theme.textPrimary, lineWidth: 1.7).frame(width: 20, height: 20)
                        Text("Choose from Library").font(.headline).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusControl)
                            .stroke(Theme.separator, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snap-meal-choose-library")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Reading your plate…")
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
                Text("\(Int(item.calories)) cal · \(Int(item.grams))g · P \(Int(item.proteinG)) C \(Int(item.carbsG)) F \(Int(item.fatG))")
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
            Button("Try Again") {
                if let data = capturedImage {
                    Task { await analyze(data) }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
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
            phase = .error("Couldn't spot any food in that photo. Try a clearer shot of the plate.")
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
            .map { "\($0.name) · \(Int($0.calories))cal · \(Int($0.grams))g" }
            .joined(separator: "\n")
        TelemetryService.shared.aiTurn(
            surface: TelemetrySurface.snapMeal,
            query: nil,
            response: summary.isEmpty ? nil : summary,
            outcome: outcome,
            latencyMS: Int(Date().timeIntervalSince(started) * 1000))
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
