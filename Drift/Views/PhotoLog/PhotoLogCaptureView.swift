import SwiftUI
import DriftCore
import PhotosUI
import UIKit
import AVFoundation

/// Entry-point sheet for the Photo Log beta. Shows a privacy banner, a
/// cost estimate, and two buttons — Camera and Library. A confirmed
/// capture advances to `PhotoLogReviewView`. Cancel unwinds without any
/// network calls. #224 / #267.
struct PhotoLogCaptureView: View {
    /// Shared food-log VM — barcode scanning logs straight into it so the
    /// entry lands in the same place a photo-logged meal would. #224 / #267.
    let foodLog: FoodLogViewModel
    let onCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingBarcode = false
    @State private var showingCameraDeniedAlert = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var libraryLoadError: String? = nil
    @State private var showingSettings = false

    private var hasKey: Bool {
        CloudVisionProvider.allCases.contains { CloudVisionKey.has(provider: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                infoBanner
                Spacer()
                captureButtons
                if let libraryLoadError {
                    Text(libraryLoadError)
                        .font(.caption)
                        .foregroundStyle(Theme.surplus)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.background)
            .navigationTitle("Photo Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    PhotoLogSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
                    }
            .sheet(isPresented: $showingBarcode) {
                // Barcode scanning needs NO API key (OpenFoodFacts is free),
                // so it's the working fallback for users who haven't set up
                // BYOK — and logs into the same shared VM as a photo log.
                BarcodeLookupView(viewModel: foodLog)
            }
            .fullScreenCover(isPresented: $showingCamera) {
                // CameraView calls its own `dismiss()` internally to close the
                // fullScreenCover — do NOT call `dismiss()` here, which would
                // resolve to PhotoLogCaptureView's environment dismiss (the
                // outer sheet) and kill the flow mid-analysis. #310.
                CameraView { image in
                    onCaptured(image)
                }
            }
            .photosPicker(isPresented: $showingLibrary, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task { await handleLibraryPick(item) }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        // V7 polish (mobile review): coral camera icon retired —
        // user said the page had "too many colors and doesn't look
        // clean." Switched to a neutral outline glyph matching the
        // dashed-border camera card from the V7 reference mocks 16.
        VStack(spacing: 6) {
            Image(systemName: "camera")
                .font(.system(size: Theme.FontSize.display3, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("Snap a meal to log it")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Photo Log uses cloud AI to identify what's on your plate.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// Single adaptive info line — replaces the old three-banner stack
    /// (BYOK tip + privacy + cost) that made this screen look busy. When no
    /// key is configured it's a tappable prompt to set one up; when a key is
    /// present it states where the photo goes and what it roughly costs.
    /// Barcode scanning below works regardless, so this only speaks to the
    /// AI-photo path.
    @ViewBuilder
    private var infoBanner: some View {
        Button {
            if !hasKey { showingSettings = true }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "cloud").foregroundStyle(Theme.textTertiary)
                if hasKey {
                    Text("Photo sent to \(Preferences.photoLogProvider.displayName) · \(Preferences.photoLogProvider.pricingLine). Your key, your data.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                } else {
                    (Text("Photo scanning needs your own AI key (Claude, OpenAI, or Gemini). ")
                        .foregroundStyle(Theme.textSecondary)
                     + Text("Tap to set one up →")
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold))
                        .font(.caption2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        }
        .buttonStyle(.plain)
        .disabled(hasKey)
        .accessibilityIdentifier("photo-log-privacy-banner")
    }

    private var captureButtons: some View {
        // V7 polish: Take Photo flipped from coral.borderedProminent →
        // ink.borderedProminent (V7 primary-CTA convention, matches
        // the FAB-era black filled buttons elsewhere in the app).
        // Choose from Library is the secondary path — `.tint(.secondary)`
        // gives a charcoal label instead of the default system blue
        // that was making this screen look like it had three different
        // primary colors (coral + blue + gray).
        VStack(spacing: 10) {
            Button {
                requestCameraAccess()
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            .alert("Camera access needed", isPresented: $showingCameraDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Drift needs camera access to scan and recognize meals. Enable it in Settings → Drift → Camera.")
            }

            Button {
                showingLibrary = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.textPrimary)

            // Barcode is a co-equal scan path — and the ONLY one that works
            // without a BYOK key. Surfacing it here means users without a
            // configured provider still have a fast, free way to log
            // packaged food instead of a dead-end.
            Button {
                showingBarcode = true
            } label: {
                Label("Scan a barcode", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.textPrimary)
            .accessibilityIdentifier("photo-log-scan-barcode")
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            // #943 audit: @Sendable — TCC calls back off-main; an
            // inferred-@MainActor literal asserts at closure entry.
            AVCaptureDevice.requestAccess(for: .video) { @Sendable granted in
                Task { @MainActor in
                    if granted { showingCamera = true }
                    else { showingCameraDeniedAlert = true }
                }
            }
        case .denied, .restricted:
            showingCameraDeniedAlert = true
        @unknown default:
            showingCameraDeniedAlert = true
        }
    }

    // MARK: - Library handler

    /// Load the picked PhotosPicker item as UIImage. Runs the transfer on a
    /// background task so the UI doesn't stall on large iCloud downloads.
    ///
    /// Do NOT call `dismiss()` after `onCaptured` — the coordinator swaps
    /// this view out when state becomes `.analyzing`. Calling `dismiss()`
    /// here would dismiss the outer PhotoLogFlowView sheet (wrong scope),
    /// cancel the analysis task via `.onDisappear`, and leave the user
    /// staring at the food tab with no indication anything happened. #310.
    private func handleLibraryPick(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                libraryLoadError = "Couldn't load that photo. Try another."
                return
            }
            libraryLoadError = nil
            onCaptured(image)
        } catch {
            libraryLoadError = "Couldn't load photo: \(error.localizedDescription)"
        }
    }
}
