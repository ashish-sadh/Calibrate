import Foundation
import Speech
import AVFoundation

/// On-device speech recognition. Committed + Live text model:
/// committedText = locked-in text from finished segments (never lost)
/// liveText = raw output from current segment (updates constantly)
/// Display = committedText + liveText (always grows, never flashes)
@Observable
final class SpeechRecognitionService: @unchecked Sendable {
    static let shared = SpeechRecognitionService()

    enum RecordingState: Equatable, Sendable {
        case idle, recording
        case unavailable(String)
    }

    @MainActor private(set) var recordingState: RecordingState = .idle
    @MainActor private(set) var transcript = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioQueue = DispatchQueue(label: "com.drift.speech", qos: .userInitiated)
    private var silenceTimer: DispatchWorkItem?
    private var onDoneCallback: (@MainActor (String) -> Void)?

    private var committedText = ""  // Locked-in text from completed segments
    private static let maxChars = 500
    private static let silenceTimeout: TimeInterval = 30.0

    private init() {}

    @MainActor var isRecording: Bool { recordingState == .recording }
    @MainActor var isAvailable: Bool { speechRecognizer?.isAvailable ?? false }

    @MainActor
    func toggleRecording(
        onTranscript: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor (String) -> Void
    ) {
        if isRecording { gracefulStop() }
        else { startRecording(onTranscript: onTranscript, onDone: onDone) }
    }

    @MainActor
    func startRecording(
        onTranscript: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor (String) -> Void
    ) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            recordingState = .unavailable("Speech recognition not available")
            return
        }
        onDoneCallback = onDone
        committedText = ""
        recordingState = .recording
        transcript = ""

        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            ensureMicAndStart(recognizer: recognizer, onTranscript: onTranscript)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] s in
                DispatchQueue.main.async {
                    if s == .authorized {
                        self?.ensureMicAndStart(recognizer: recognizer, onTranscript: onTranscript)
                    } else {
                        self?.recordingState = .unavailable("Speech recognition denied.")
                    }
                }
            }
        case .denied, .restricted:
            recordingState = .unavailable("Enable in Settings → Privacy → Speech Recognition.")
        @unknown default: break
        }
    }

    /// Request microphone permission on main before touching `AVAudioEngine`.
    /// Skipping this path lets iOS surface the mic prompt as a side effect of
    /// `AVAudioSession.setActive(true)`, which leaves the session mid-
    /// negotiation while `installTap`/`engine.start` run — that mismatch can
    /// throw an uncatchable `NSInternalInconsistencyException` and crash the
    /// app on first voice tap. #272.
    @MainActor
    private func ensureMicAndStart(
        recognizer: SFSpeechRecognizer,
        onTranscript: @escaping @MainActor (String) -> Void
    ) {
        nonisolated(unsafe) let capturedRec = recognizer
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.recordingState == .recording else { return }
                if granted {
                    self.setupEngine(recognizer: capturedRec, onTranscript: onTranscript)
                } else {
                    self.recordingState = .unavailable("Enable microphone in Settings → Privacy → Microphone.")
                }
            }
        }
    }

    /// Stop and send
    @MainActor
    func gracefulStop() {
        silenceTimer?.cancel(); silenceTimer = nil
        let text = transcript.trimmingCharacters(in: .whitespaces)
        // Set idle BEFORE cleanup so any stale recognition callbacks are rejected
        recordingState = .idle
        let cb = onDoneCallback; onDoneCallback = nil
        cleanup()
        if !text.isEmpty { cb?(text) }
    }

    /// Stop for editing — keeps text in inputField, doesn't send.
    /// Sets idle BEFORE cleanup to prevent stale callbacks from overwriting user edits.
    @MainActor
    func forceStop() {
        silenceTimer?.cancel(); silenceTimer = nil
        onDoneCallback = nil
        recordingState = .idle
        cleanup()
    }

    @MainActor
    private func autoSend(text: String) {
        silenceTimer?.cancel(); silenceTimer = nil
        recordingState = .idle
        let cb = onDoneCallback; onDoneCallback = nil
        cleanup()
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { cb?(text) }
    }

    private func cleanup() {
        let engine = audioEngine
        let req = currentRequest
        let task = recognitionTask
        audioEngine = nil; currentRequest = nil; recognitionTask = nil
        audioQueue.async {
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
            req?.endAudio()
            task?.cancel()
        }
    }

    // MARK: - Engine Setup

    private func setupEngine(
        recognizer: SFSpeechRecognizer,
        onTranscript: @escaping @MainActor (String) -> Void
    ) {
        let supportsOnDevice = recognizer.supportsOnDeviceRecognition

        audioQueue.async { [weak self] in
            guard let self else { return }

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                DispatchQueue.main.async { self.recordingState = .unavailable("Microphone unavailable") }
                return
            }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                DispatchQueue.main.async { self.recordingState = .unavailable("Microphone unavailable") }
                return
            }

            // Audio tap writes to currentRequest (survives segment restarts)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.currentRequest?.append(buffer)
            }
            engine.prepare()

            do { try engine.start() } catch {
                inputNode.removeTap(onBus: 0)
                DispatchQueue.main.async { self.recordingState = .unavailable("Could not start audio engine") }
                return
            }

            nonisolated(unsafe) let e = engine
            nonisolated(unsafe) let r = recognizer
            DispatchQueue.main.async {
                // Guard: user may have called forceStop/gracefulStop while audio engine was starting
                // on audioQueue. In that case, stop the engine we just started — don't leak it.
                guard self.recordingState == .recording else {
                    self.audioQueue.async { e.stop(); e.inputNode.removeTap(onBus: 0) }
                    return
                }
                self.audioEngine = e
                self.startSegment(recognizer: r, supportsOnDevice: supportsOnDevice, onTranscript: onTranscript)
            }
        }
    }

    // MARK: - Recognition Segment

    @MainActor
    private func startSegment(
        recognizer: SFSpeechRecognizer,
        supportsOnDevice: Bool,
        onTranscript: @escaping @MainActor (String) -> Void,
        retryCount: Int = 0
    ) {
        guard recordingState == .recording else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if supportsOnDevice { request.requiresOnDeviceRecognition = true }
        currentRequest = request

        nonisolated(unsafe) let unsafeRec = recognizer
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.recordingState == .recording else { return }

                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    // Combine committed (locked) + live (current segment)
                    let full = self.committedText.isEmpty ? text : self.committedText + " " + text
                    self.transcript = full
                    onTranscript(full)

                    // Reset silence timer (30s of no new results → auto-send)
                    self.silenceTimer?.cancel()
                    let captured = full
                    let timer = DispatchWorkItem { [weak self] in
                        self?.autoSend(text: captured)
                    }
                    self.silenceTimer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.silenceTimeout, execute: timer)

                    // Auto-stop at 500 chars
                    if full.count > Self.maxChars {
                        self.gracefulStop()
                        return
                    }
                }

                let isFinal = result?.isFinal ?? false
                if isFinal {
                    // Pause detected — commit current text, restart segment
                    // Display stays because committedText is updated BEFORE liveText resets
                    let segmentText = result?.bestTranscription.formattedString ?? ""
                    if !segmentText.isEmpty {
                        self.committedText = self.committedText.isEmpty ? segmentText : self.committedText + " " + segmentText
                    }
                    // Display still shows committedText (no flash)
                    onTranscript(self.committedText)
                    // Cancel old task before restarting — prevents stale callback firing startSegment again
                    self.recognitionTask?.cancel()
                    self.recognitionTask = nil
                    self.startSegment(recognizer: unsafeRec, supportsOnDevice: supportsOnDevice, onTranscript: onTranscript)
                } else if let error {
                    let desc = error.localizedDescription
                    self.recognitionTask?.cancel()
                    self.recognitionTask = nil

                    // Commit whatever was transcribed in this segment before restarting.
                    // Without this, speech before a recognizer timeout (error 203) is lost
                    // when the new segment starts from committedText only — the partial
                    // transcription of the timed-out segment is discarded.
                    if let segText = result?.bestTranscription.formattedString, !segText.isEmpty {
                        self.committedText = self.committedText.isEmpty ? segText : self.committedText + " " + segText
                        self.transcript = self.committedText
                        onTranscript(self.committedText)
                    }

                    // Error 203 (kAFAssistantErrorDomain) = no speech / recognizer timed out — normal pause.
                    let nsError = error as NSError
                    let isNormalPause = nsError.code == 203 || desc.contains("no speech")
                    if isNormalPause || retryCount < 3 {
                        self.startSegment(recognizer: unsafeRec, supportsOnDevice: supportsOnDevice,
                                          onTranscript: onTranscript, retryCount: isNormalPause ? 0 : retryCount + 1)
                    } else {
                        self.autoSend(text: self.transcript)
                    }
                }
            }
        }
    }
}
