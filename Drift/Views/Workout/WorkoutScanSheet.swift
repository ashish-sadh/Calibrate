import SwiftUI
import PhotosUI
import PDFKit
import DriftCore

/// Scan-primary workout entry: snap a photo, pick a screenshot, or upload a PDF
/// of any workout page and the Nebius vision model figures out whether it's a
/// reusable program (→ template) or dated performance logs (→ logged sessions)
/// — or both, on one page. An optional note field travels WITH the scan as
/// extra context for the model ("weights are in kg", "only the right column").
/// Replaces the old "Log by Voice or Text" card on iOS (the model, not the
/// user, decides template-vs-log).
struct WorkoutScanSheet: View {
    /// Called after anything is saved so the parent can refresh + show history.
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case chooser
        case processing
        case review(ScannedWorkoutResult)
        case empty          // read something, but no workout on the page
        case failed(String) // cloud off / unreachable / decode failure
    }

    @State private var stage: Stage = .chooser
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingPDFImporter = false
    @State private var libraryItem: PhotosPickerItem?
    /// Optional user note sent WITH the image as extra context for the model
    /// ("weights are in kg", "this is my Tuesday push day", "only log the
    /// bottom column") — not a standalone text-logging path.
    @State private var contextText = ""

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .chooser:   chooser
                case .processing: processing
                case .empty:     message(icon: "doc.text.magnifyingglass",
                                          title: "No workout found",
                                          detail: "Couldn't spot a workout on that page. Try a clearer, straighter photo of the sets and reps.")
                case .failed(let why): message(icon: "exclamationmark.triangle",
                                               title: "Couldn't read that", detail: why)
                case .review(let result):
                    WorkoutScanReviewView(result: result, onSaved: { onSaved(); dismiss() })
                }
            }
            .background(Theme.background)
            .navigationTitle("Scan a Workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { image in handle(image: image) }
            }
            .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        handle(image: image)
                    }
                }
            }
            .fileImporter(isPresented: $showingPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result { handle(pdfURL: url) }
            }
            // A scan runs 35-105s in the foreground; the default 30s auto-lock
            // suspends the app mid-request and iOS tears the connection down,
            // surfacing as a bogus "couldn't reach the cloud" (field bug,
            // build 359). Keep the screen awake only while reading.
            .onChange(of: stage) { _, newStage in
                UIApplication.shared.isIdleTimerDisabled = (newStage == .processing)
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 52)).foregroundStyle(Theme.accent.opacity(0.6))
                    Text("Scan any workout")
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Photograph a page, pick a screenshot, or upload a PDF — a printed plan, a coach's spreadsheet, or your handwritten gym log. Drift reads it and builds a template or logs the session for you.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 10) {
                    Button { showingCamera = true } label: {
                        Label("Take Photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    Button { showingLibrary = true } label: {
                        Label("Choose Screenshot or Photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Theme.accent)

                    Button { showingPDFImporter = true } label: {
                        Label("Upload PDF", systemImage: "doc.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Theme.accent)
                }

                // Optional context that rides along with the scan — hints the
                // model can't see in pixels (units, which column, what day).
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add a note (optional)")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    TextField("e.g. weights are in kg · only log the right column",
                              text: $contextText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    Text("Sent with your scan to help Drift read it right.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 4)

                Text("Handled on Drift's private cloud — the image isn't stored.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    private var processing: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Reading your workout…").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Text("Takes a minute or two — keep Drift open.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(Theme.textTertiary)
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button("Try Again") { stage = .chooser }
                .buttonStyle(.bordered).tint(Theme.accent).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Input handling

    private func handle(image: UIImage) {
        stage = .processing
        Task { await parse(imageData: Self.jpegForUpload(image)) }
    }

    private func handle(pdfURL: URL) {
        stage = .processing
        Task {
            guard let image = Self.renderFirstPage(of: pdfURL) else {
                stage = .failed("That PDF couldn't be opened. Try a screenshot of it instead.")
                return
            }
            await parse(imageData: Self.jpegForUpload(image))
        }
    }

    @MainActor
    private func parse(imageData: Data?) async {
        guard let imageData else {
            stage = .failed("That image couldn't be prepared for upload.")
            return
        }
        guard CoachCloud.isConfigured else {
            stage = .failed("The AI cloud isn't set up on this device yet.")
            return
        }
        let note = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = await NebiusWorkoutPhotoParser.parse(
            imageData: imageData, visionModelID: AppConfig.coachVisionModelID,
            userNote: note.isEmpty ? nil : note) else {
            // Distinguish "the call never made it" from "the reply didn't parse"
            // — the field bug on build 358 was a truncated reply mislabelled as
            // a connection failure, which sends the user chasing their Wi-Fi.
            // The error detail is in the copy on purpose: two rounds of field
            // debugging burned on an unlabelled failure (builds 358/359).
            if let err = LocalAIService.shared.lastRemoteError {
                stage = .failed("Couldn't reach the AI cloud (\(Self.describe(err))). Keep Drift open and on-screen while it reads, then try again.")
            } else {
                stage = .failed("Drift got a reply but couldn't make sense of it. Try a straighter, closer photo — or add a note describing the page.")
            }
            return
        }
        stage = result.isEmpty ? .empty : .review(result)
    }

    /// Short diagnostic tag for the failure copy — "network" alone is not
    /// actionable and cost two field-debug rounds.
    private static func describe(_ err: RemoteBackendError) -> String {
        switch err {
        case .auth: return "key rejected"
        case .rateLimited: return "rate limited"
        case .quotaExceeded: return "quota exceeded"
        case .transient(let status): return status == 0 ? "connection dropped or timed out" : "HTTP \(status)"
        case .malformed: return "bad reply"
        }
    }

    // MARK: - Image / PDF preprocessing

    /// Downscale (long edge 2048 px — small margin handwriting was unreadable
    /// to the VL model at 1536 in the 2026-07-22 live test) and JPEG-encode.
    /// Bigger than PhotoLogService's 1024 food rule on purpose; still ~750KB.
    static func jpegForUpload(_ image: UIImage, maxLongEdge: CGFloat = 2048, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// Render the first PDF page to an image at ~2× for crisp text.
    static func renderFirstPage(of url: URL) -> UIImage? {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let target = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: target))
            ctx.cgContext.translateBy(x: 0, y: target.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
