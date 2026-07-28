import SwiftUI
import DriftCore
#if canImport(PhotosUI)
import PhotosUI
#endif

// MARK: - Input bar
//
// Photo thumbnail (when attached) + text field + camera/mic/send buttons. Mic
// button switches between toggleRecording and stop/send while recording. Camera
// only appears when remote backend is active (local backend has no vision).
//
// Android v1 (#1066): photo attach + mic are gated off (they land with the
// media/voice work in #1125/#1126) — the bar is a plain text field + send.

extension AIChatView {

    var inputBar: some View {
        HStack(spacing: 8) {
            #if os(Android)
            // Material has no sparkle glyph — draw it (see Symbols.swift). #1066
            SparkleShape().fill(Theme.accent.opacity(0.6)).frame(width: 13, height: 13)
            #else
            Image(systemName: "sparkles")
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(Theme.accent.opacity(0.6))
            #endif

            VStack(alignment: .leading, spacing: 6) {
                #if DRIFT_IOS_APP
                if let jpeg = vm.pendingPhotoData, let uiImage = UIImage(data: jpeg) {
                    HStack(spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable().scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            vm.pendingPhotoData = nil
                            photoPickerItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: Theme.FontSize.base))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove photo")
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
                #endif

                #if os(Android)
                // SkipUI has no TextField(axis:) initializer and no ClosedRange
                // lineLimit — a plain single-line field (the shipped ChatView
                // input bar uses the same shape). #1066
                TextField("Ask anything...", text: $vm.inputText)
                    .textFieldStyle(.plain).font(.subheadline)
                    .focused($inputFocused)
                    .onSubmit { vm.sendMessage() }
                    .accessibilityIdentifier("ai-chat-input")
                #else
                TextField(
                    vm.speechService.isRecording ? "Listening..." :
                        (vm.pendingPhotoData != nil ? "Describe the photo (optional)..." : "Ask anything..."),
                    text: $vm.inputText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline)
                    .lineLimit(1...(vm.speechService.isRecording ? 6 : 3)).focused($inputFocused)
                    .onSubmit { vm.sendMessage() }
                    .accessibilityIdentifier("ai-chat-input")
                #endif
            }
            .animation(.easeInOut(duration: 0.2), value: vm.pendingPhotoData != nil)

            if vm.speechService.isRecording {
                recordingControls
            } else {
                idleControls
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        // 2026-05-19: was Color.white.opacity(0.05) (invisible on the new
        // light card bg) — flipped to Theme.pillBackground so the input
        // field actually reads as a tappable rounded surface.
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(vm.speechService.isRecording ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
                )
        )
        .animation(.easeInOut(duration: 0.3), value: vm.speechService.isRecording)
        .padding(.horizontal, 8).padding(.bottom, 4)
    }

    // Not `private` — Skip Fuse can't bridge private members of a shared view.
    // Never rendered on Android (isRecording is always false via the voice
    // shim), but it must still compile there.
    @ViewBuilder
    var recordingControls: some View {
        Button {
            vm.speechService.forceStop()
        } label: {
            Image(systemName: "stop.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.surplus)
        }
        .accessibilityLabel("Stop recording")

        Button {
            vm.speechService.gracefulStop()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Send message")
    }

    @ViewBuilder
    var idleControls: some View {
        // UIKit/PhotosUI + the speech shim are iOS-app-only; DRIFT_IOS_APP keeps
        // them out of the Skip Android AND Darwin bridging passes. Photo attach +
        // mic land with #1125 / #1126; Android v1 is a text-only Coach.
        #if DRIFT_IOS_APP
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            Image(systemName: vm.pendingPhotoData != nil ? "camera.fill" : "camera")
                .font(.system(size: Theme.FontSize.large))
                .foregroundStyle(vm.pendingPhotoData != nil ? Theme.accent : .secondary)
        }
        .disabled(vm.isGenerating)
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    vm.pendingPhotoData = data
                }
                photoPickerItem = nil
            }
        }
        .accessibilityLabel("Attach photo")

        // Voice-replies toggle lives in the coach header now (one visible
        // mute switch, always on screen — it used to vanish behind the
        // recording controls mid-dictation, which is how #937 recurred).

        Button {
            startOrStopVoice()   // shared with the hero listening circle
        } label: {
            Image(systemName: "mic")
                .font(.system(size: Theme.FontSize.large))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityLabel("Voice input")
        .disabled(vm.isGenerating)
        #endif

        let canSend = !vm.inputText.isEmpty || vm.pendingPhotoData != nil
        Button { vm.sendMessage() } label: {
            Image(systemName: sym("arrow.up.circle.fill")).font(.title2)
                .foregroundStyle(canSend ? Theme.ink : Color.secondary.opacity(0.5))
        }
        .accessibilityLabel("Send message")
        .accessibilityIdentifier("ai-chat-send")
        .disabled(!canSend || vm.isGenerating)
    }
}
