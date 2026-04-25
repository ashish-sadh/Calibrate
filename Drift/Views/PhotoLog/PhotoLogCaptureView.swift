import SwiftUI
import DriftCore
import PhotosUI
import UIKit

/// Entry-point sheet for the Photo Log beta. Shows a privacy banner, a
/// cost estimate, and two buttons — Camera and Library. A confirmed
/// capture advances to `PhotoLogReviewView`. Cancel unwinds without any
/// network calls. #224 / #267.
struct PhotoLogCaptureView: View {
    let onCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var libraryLoadError: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                privacyBanner
                costBanner
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Snap a meal to log it")
                .font(.headline)
            Text("Photo Log uses cloud AI to identify what's on your plate.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var privacyBanner: some View {
        Label {
            Text("This single photo is sent to \(Preferences.photoLogProvider.displayName). Your key, your data — Drift never sees either.")
                .font(.caption2).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "cloud").foregroundStyle(Theme.accent)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var costBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard")
                .font(.caption).foregroundStyle(.tertiary)
            // Provider-aware — previously hardcoded "~2¢ per photo" which was
            // accurate for Anthropic Sonnet but misleading for OpenAI mini
            // (~30× cheaper) and wrong for Gemini Flash (free tier).
            Text(Preferences.photoLogProvider.pricingLine)
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private var captureButtons: some View {
        VStack(spacing: 10) {
            Button {
                showingCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            Button {
                showingLibrary = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
