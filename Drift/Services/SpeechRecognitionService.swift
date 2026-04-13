import Foundation
import Speech
import AVFoundation

/// On-device speech recognition service. Privacy-first: requiresOnDeviceRecognition = true.
/// Feeds recognized text directly into the chat input — reuses existing AI pipeline.
@MainActor
@Observable
final class SpeechRecognitionService {
    static let shared = SpeechRecognitionService()

    enum RecordingState: Equatable {
        case idle
        case recording
        case unavailable(String)
    }

    private(set) var recordingState: RecordingState = .idle
    private(set) var transcript = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private init() {}

    var isRecording: Bool { recordingState == .recording }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    /// Toggle recording on/off. Transcript streams into the provided binding.
    func toggleRecording(onTranscript: @escaping @MainActor (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(onTranscript: onTranscript)
        }
    }

    func startRecording(onTranscript: @escaping @MainActor (String) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            recordingState = .unavailable("Speech recognition not available on this device")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecording(onTranscript: onTranscript)
                case .denied, .restricted:
                    self.recordingState = .unavailable("Speech recognition denied. Enable in Settings → Privacy.")
                case .notDetermined:
                    self.recordingState = .idle
                @unknown default:
                    self.recordingState = .idle
                }
            }
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        if recordingState == .recording {
            recordingState = .idle
        }
    }

    // MARK: - Private

    private func beginRecording(onTranscript: @escaping @MainActor (String) -> Void) {
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            recordingState = .unavailable("Microphone unavailable")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Prepare engine BEFORE querying format — inputNode.outputFormat can return
        // an invalid format (sample rate 0) if the engine isn't prepared yet,
        // which crashes installTap on real devices.
        engine.prepare()

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 else {
            recordingState = .unavailable("Microphone unavailable")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            recordingState = .unavailable("Could not start audio engine")
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    onTranscript(self.transcript)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.transcript = ""
        self.recordingState = .recording
    }
}
