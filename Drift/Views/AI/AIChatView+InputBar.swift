import SwiftUI
import DriftCore
import PhotosUI

// MARK: - Input bar
//
// Photo thumbnail (when attached) + text field + camera/mic/send buttons. Mic
// button switches between toggleRecording and stop/send while recording. Camera
// only appears when remote backend is active (local backend has no vision).

extension AIChatView {

    var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(Theme.accent.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
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

                TextField(
                    vm.speechService.isRecording ? "Listening..." :
                        (vm.pendingPhotoData != nil ? "Describe the photo (optional)..." : "Ask anything..."),
                    text: $vm.inputText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline)
                    .lineLimit(1...(vm.speechService.isRecording ? 6 : 3)).focused($inputFocused)
                    .onSubmit { vm.sendMessage() }
                    .accessibilityIdentifier("ai-chat-input")
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

    @ViewBuilder
    private var recordingControls: some View {
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
    private var idleControls: some View {
        // Image — always available. Image turns route to the vision model
        // (Qwen2.5-VL); an explicit cloud touch-point when sent.
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

        // Voice replies toggle — the coach speaks its answers aloud when on,
        // pairing with the mic for a full talk-to-it experience. While speaking,
        // becomes a stop button.
        Button {
            if vm.voiceService.isSpeaking {
                vm.voiceService.stop()
            } else {
                vm.toggleVoiceOutput()
            }
        } label: {
            Image(systemName: vm.voiceService.isSpeaking ? "stop.circle.fill"
                    : (vm.voiceOutputEnabled ? "speaker.wave.2.fill" : "speaker.slash"))
                .font(.system(size: Theme.FontSize.large))
                .foregroundStyle(vm.voiceService.isSpeaking || vm.voiceOutputEnabled ? Theme.accent : .secondary)
        }
        .accessibilityLabel(vm.voiceService.isSpeaking ? "Stop speaking"
            : (vm.voiceOutputEnabled ? "Voice replies on" : "Voice replies off"))

        Button {
            startOrStopVoice()   // shared with the hero listening circle
        } label: {
            Image(systemName: "mic")
                .font(.system(size: Theme.FontSize.large))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityLabel("Voice input")
        .disabled(vm.isGenerating)

        let canSend = !vm.inputText.isEmpty || vm.pendingPhotoData != nil
        Button { vm.sendMessage() } label: {
            Image(systemName: "arrow.up.circle.fill").font(.title2)
                .foregroundStyle(canSend ? Theme.ink : Color.secondary.opacity(0.5))
        }
        .accessibilityLabel("Send message")
        .accessibilityIdentifier("ai-chat-send")
        .disabled(!canSend || vm.isGenerating)
    }
}
