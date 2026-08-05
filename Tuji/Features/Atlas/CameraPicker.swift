// Full-screen camera for the 自制圖鑑 quick-add flow (D.10 step 1).
//
// This was a thin wrapper over `UIImagePickerController`, and its own comment
// argued that a full AVFoundation pipeline "would be overkill for snap one frame
// and hand back JPEG data". That was true while the only requirement was the
// frame. It stopped being true when the redesign made *stock chrome* the thing
// being removed: `UIImagePickerController` is a whole Apple-designed screen —
// its shutter, its controls, its type — and it was the single largest piece of
// borrowed interface left in the app.
//
// Kept from the old wrapper: the interface (`onCapture` / `onCancel` /
// `isAvailable`), the 0.88 JPEG re-encode (which also strips EXIF), and the fact
// that callers never touch `UIImage`.
//
// ⚠️ The simulator has no camera, so **none of this can be verified there** —
// `isAvailable` is false and the caller falls back to 從相簿選. It needs a run on
// a device before anyone trusts it.

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraPicker: View {
    /// Delivered the re-encoded JPEG once the user takes a shot.
    let onCapture: (Data) -> Void
    /// Cancel tap, a failed encode, or "use the library instead".
    let onCancel: () -> Void

    /// False on the Simulator and any device without a usable camera — callers
    /// fall back to the photo-library path.
    static var isAvailable: Bool {
        !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty
    }

    @State private var session = CameraSession()
    @State private var capturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if self.session.failure == nil {
                CameraPreview(session: self.session.session)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    TujiNavBar(leading: .close, onLeading: self.onCancel)
                    Spacer(minLength: 0)
                }
                Spacer()
                if let failure = self.session.failure {
                    self.failed(failure)
                    Spacer()
                } else {
                    self.controls
                }
            }
        }
        .task { await self.session.start() }
        .onDisappear { self.session.stop() }
    }

    /// 72×72 square shutter with a 3pt ink inner frame — the same square the
    /// rest of the app is built from, at the one moment the user is aiming.
    /// A round shutter is every camera app's signature, including the one this
    /// screen replaced.
    private var controls: some View {
        HStack {
            // 相簿 sits bottom-left, where the system camera puts its roll: the
            // position is muscle memory, the chrome is not. Cancelling returns
            // to the source chooser, which is where 從相簿選 lives.
            Button(action: self.onCancel) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tujiPaper)
                    .frame(width: 56, height: 56)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("從相簿選"))

            Spacer()

            Button(action: self.shoot) {
                Rectangle()
                    .fill(.tujiPaper)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Rectangle()
                            .stroke(.tujiInk, lineWidth: Border.bw3)
                            .padding(Border.bw3 + 2)
                    )
                    .opacity(self.capturing ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(self.capturing)
            .accessibilityLabel(Text("拍照"))

            Spacer()

            Button { self.session.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tujiPaper)
                    .frame(width: 56, height: 56)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("切換鏡頭"))
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s5)
    }

    /// A camera that cannot start is not a state to sit in — the flow has a
    /// working second source, so say what happened and offer it.
    private func failed(_ message: String) -> some View {
        TujiErrorState(title: "無法使用相機", message: message) {
            BBtn(title: "從相簿選", action: self.onCancel)
        }
        .padding(.horizontal, Space.s4)
    }

    private func shoot() {
        guard !self.capturing else { return }
        self.capturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let data = await self.session.capture()
            self.capturing = false
            guard let data else {
                self.onCancel()
                return
            }
            self.onCapture(data)
        }
    }
}

/// Owns the capture session. Split from the view so the view stays a layout: it
/// starts, flips, captures, and reports why it could not.
@MainActor
@Observable
private final class CameraSession {
    let session = AVCaptureSession()
    /// Already resolved: `TujiErrorState.message` takes a `String` because its
    /// usual source is a server error description.
    private(set) var failure: String?

    private let output = AVCapturePhotoOutput()
    private var position: AVCaptureDevice.Position = .back
    private var configured = false
    /// `capturePhoto` does not retain its delegate.
    private var pending: PhotoDelegate?

    func start() async {
        guard !self.configured else {
            self.resume()
            return
        }
        // Ask first: configuring a session without permission yields a black
        // preview and no error, which reads as a broken app rather than as a
        // prompt the user declined.
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            self.failure = tujiLocalized("請到「設定」開啟相機權限，或改從相簿選一張照片。")
            return
        }
        guard self.configure() else {
            self.failure = tujiLocalized("這台裝置的相機無法啟動，可以改從相簿選一張照片。")
            return
        }
        self.configured = true
        self.resume()
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
    }

    func flip() {
        guard self.configured else { return }
        self.position = self.position == .back ? .front : .back
        self.session.beginConfiguration()
        for input in self.session.inputs {
            self.session.removeInput(input)
        }
        if let input = self.input(for: self.position) { self.session.addInput(input) }
        self.session.commitConfiguration()
    }

    func capture() async -> Data? {
        guard self.configured else { return nil }
        return await withCheckedContinuation { continuation in
            let delegate = PhotoDelegate { data in
                continuation.resume(returning: data)
            }
            self.pending = delegate
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    private func configure() -> Bool {
        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }
        self.session.sessionPreset = .photo
        guard let input = self.input(for: self.position),
              self.session.canAddInput(input),
              self.session.canAddOutput(self.output)
        else { return false }
        self.session.addInput(input)
        self.session.addOutput(self.output)
        return true
    }

    private func input(for position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
        else { return nil }
        return try? AVCaptureDeviceInput(device: device)
    }

    /// Starting a session blocks; off the main actor it is invisible.
    private func resume() {
        let session = self.session
        Task.detached {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Re-encode rather than pass `fileDataRepresentation()` straight
        // through: 0.88 JPEG is what the upload pipeline is tuned for, and the
        // round trip strips EXIF — including where the photo was taken.
        guard error == nil,
              let raw = photo.fileDataRepresentation(),
              let image = UIImage(data: raw),
              let jpeg = image.jpegData(compressionQuality: 0.88)
        else {
            self.completion(nil)
            return
        }
        self.completion(jpeg)
    }
}

/// The viewfinder. A `UIView` whose backing layer *is* the preview layer, so it
/// resizes with the view instead of needing a manual frame update.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = self.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            self.layer as! AVCaptureVideoPreviewLayer
        }
    }
}
