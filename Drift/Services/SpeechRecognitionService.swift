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

    func toggleRecording(onTranscript: @escaping @MainActor (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(onTranscript: onTranscript)
        }
    }

    func startRecording(onTranscript: @escaping @MainActor (String) -> Void) {
        print("🎤 [Voice] startRecording called")
        guard let recognizer = speechRecognizer else {
            print("🎤 [Voice] ERROR: speechRecognizer is nil")
            recordingState = .unavailable("Speech recognition not available")
            return
        }
        print("🎤 [Voice] recognizer.isAvailable = \(recognizer.isAvailable)")
        guard recognizer.isAvailable else {
            recordingState = .unavailable("Speech recognition not available on this device")
            return
        }

        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        print("🎤 [Voice] Current auth status: \(currentStatus.rawValue)")

        switch currentStatus {
        case .authorized:
            print("🎤 [Voice] Already authorized — calling beginRecording")
            beginRecording(onTranscript: onTranscript)
        case .notDetermined:
            print("🎤 [Voice] Not determined — requesting authorization...")
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                print("🎤 [Voice] Authorization callback: \(status.rawValue)")
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized {
                        self.beginRecording(onTranscript: onTranscript)
                    } else {
                        self.recordingState = .unavailable("Speech recognition denied. Enable in Settings → Privacy.")
                    }
                }
            }
        case .denied, .restricted:
            print("🎤 [Voice] DENIED or RESTRICTED")
            recordingState = .unavailable("Speech recognition denied. Enable in Settings → Privacy.")
        @unknown default:
            recordingState = .idle
        }
    }

    func stopRecording() {
        print("🎤 [Voice] stopRecording called")
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
        print("🎤 [Voice] beginRecording called")
        stopRecording()
        transcript = ""

        guard let recognizer = speechRecognizer else {
            recordingState = .unavailable("Speech recognizer unavailable")
            return
        }

        // Audio session setup — do this synchronously, it's fast enough
        let audioSession = AVAudioSession.sharedInstance()
        do {
            print("🎤 [Voice] Setting audio session category...")
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            print("🎤 [Voice] Setting audio session active...")
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("🎤 [Voice] Audio session ready")
        } catch {
            print("🎤 [Voice] ERROR audio session: \(error)")
            recordingState = .unavailable("Microphone unavailable: \(error.localizedDescription)")
            return
        }

        // Use SFSpeechRecognizer's built-in audio recording instead of AVAudioEngine.
        // AVAudioEngine.prepare() crashes when llama.cpp's global exception handler
        // intercepts the ObjC exception from audio graph initialization.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Use AVAudioEngine carefully — access inputNode FIRST to trigger implicit graph creation
        print("🎤 [Voice] Creating engine...")
        let engine = AVAudioEngine()

        // Access inputNode first — this initializes the audio graph
        let inputNode = engine.inputNode
        print("🎤 [Voice] Got inputNode")

        // Get format BEFORE prepare
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("🎤 [Voice] Format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")

        guard recordingFormat.sampleRate > 0 else {
            print("🎤 [Voice] ERROR: invalid format")
            recordingState = .unavailable("Microphone unavailable")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        print("🎤 [Voice] Tap installed")

        // prepare() after tap is installed — graph now has both input and output
        engine.prepare()
        print("🎤 [Voice] Engine prepared")

        do {
            try engine.start()
            print("🎤 [Voice] Engine started")
        } catch {
            print("🎤 [Voice] ERROR engine start: \(error)")
            inputNode.removeTap(onBus: 0)
            recordingState = .unavailable("Could not start audio engine")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    onTranscript(self.transcript)
                    print("🎤 [Voice] Transcript: \(self.transcript)")
                }
                if error != nil || (result?.isFinal ?? false) {
                    print("🎤 [Voice] Recognition ended (error: \(error?.localizedDescription ?? "none"), final: \(result?.isFinal ?? false))")
                    self.stopRecording()
                }
            }
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.recordingState = .recording
        print("🎤 [Voice] Recording started successfully!")
    }
}
