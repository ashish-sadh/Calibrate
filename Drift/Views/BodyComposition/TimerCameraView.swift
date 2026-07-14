import SwiftUI
import AVFoundation
import UIKit

/// Hands-free self-timer camera for progress photos (operator 2026-07-14:
/// "open with a timer selection to help self click"). Front camera by default
/// so you can frame yourself, a 3/5/10s countdown, then an auto-capture. A
/// flip button switches to the rear camera for full-body mirror shots.
struct TimerCameraView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cam = TimerCameraController()
    @State private var seconds = 0          // 0 = Off (instant capture)
    @State private var countdown: Int?
    @State private var cancelled = false
    @State private var permissionDenied = false

    private let options = [0, 3, 5, 10]      // 0 shown as "Off"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: cam.session).ignoresSafeArea()

            if permissionDenied {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash").font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Camera access needed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Enable it in Settings → Drift → Camera.")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered).tint(.white)
                }
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .transition(.scale.combined(with: .opacity))
                    .id(countdown)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3.weight(.semibold))
                            .foregroundStyle(.white).padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    Button { cam.flip() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white).padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
                .padding()
                Spacer()
                if !permissionDenied { controls }
            }
        }
        .onAppear {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            permissionDenied = (status == .denied || status == .restricted)
            cam.configure(); cam.start()
        }
        .onDisappear { cancelled = true; cam.stop() }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if countdown == nil {
                Picker("Timer", selection: $seconds) {
                    ForEach(options, id: \.self) { Text($0 == 0 ? "Off" : "\($0)s").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Button { shutter() } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                    // Solid inner disc for instant shutter; timer glyph when armed.
                    if seconds == 0 {
                        Circle().fill(.white).frame(width: 60, height: 60)
                    } else {
                        Image(systemName: countdown == nil ? "timer" : "hourglass")
                            .font(.title2).foregroundStyle(.white)
                    }
                }
            }
            .disabled(countdown != nil)
            .accessibilityLabel(seconds == 0 ? "Take photo" : "Start \(seconds) second timer")
        }
        .padding(.bottom, 40)
    }

    /// Instant capture when the timer is Off, otherwise start the countdown.
    private func shutter() {
        if seconds == 0 {
            cam.capture { image in
                if let image { onCapture(image) }
                dismiss()
            }
        } else {
            countdown = seconds
            tick()
        }
    }

    private func tick() {
        guard !cancelled, let c = countdown else { return }   // stop if dismissed mid-countdown
        if c <= 0 {
            cam.capture { image in
                if let image { onCapture(image) }
                dismiss()
            }
            return
        }
        // Vibrate on the last three ticks for an eyes-free cue.
        if c <= 3 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.easeOut(duration: 0.25)) { countdown = (countdown ?? 1) - 1 }
            tick()
        }
    }
}

/// AVFoundation session wrapper — front camera, single-photo capture.
@MainActor
private final class TimerCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var position: AVCaptureDevice.Position = .front
    private var captureHandler: ((UIImage?) -> Void)?
    private var configured = false
    /// Set at capture time so the nonisolated delegate callback knows whether to
    /// mirror without reading main-actor state.
    nonisolated(unsafe) private var lastCaptureFront = true

    func configure() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        setInput(for: position)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    private func setInput(for position: AVCaptureDevice.Position) {
        for input in session.inputs { session.removeInput(input) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }

    func flip() {
        position = position == .front ? .back : .front
        session.beginConfiguration()
        setInput(for: position)
        session.commitConfiguration()
    }

    // Session start/stop are blocking; run them off the main thread on a
    // dedicated serial queue (standard AVFoundation pattern).
    private let sessionQueue = DispatchQueue(label: "com.drift.progress.camera")

    func start() {
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture(_ completion: @escaping (UIImage?) -> Void) {
        // No live video connection (simulator, or no camera for the requested
        // position) → capturePhoto would throw NSInvalidArgumentException.
        guard output.connection(with: .video)?.isActive == true else { completion(nil); return }
        captureHandler = completion
        lastCaptureFront = position == .front
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        let isFront = lastCaptureFront
        Task { @MainActor in
            guard let data, var image = UIImage(data: data) else { captureHandler?(nil); return }
            // Mirror the front-camera shot so it matches what the user saw.
            if isFront, let cg = image.cgImage {
                image = UIImage(cgImage: cg, scale: image.scale, orientation: .upMirrored)
            }
            captureHandler?(image)
            captureHandler = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
