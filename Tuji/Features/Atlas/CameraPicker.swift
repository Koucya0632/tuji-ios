// Thin SwiftUI wrapper over UIImagePickerController in camera mode. Single-shot
// photo intake for the 自制圖鑑 quick-add flow — a full AVFoundation capture
// pipeline would be overkill for "snap one frame and hand back JPEG data".
//
// The captured frame is re-encoded to JPEG here (which also strips EXIF), so the
// caller receives upload-ready `Data` and never touches UIImage.

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// Delivered the re-encoded JPEG once the user accepts a shot.
    let onCapture: (Data) -> Void
    /// Cancel tap, or a frame we failed to encode.
    let onCancel: () -> Void

    /// False on the Simulator and any device without a usable camera — callers
    /// fall back to the photo-library path.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: self.onCapture, onCancel: self.onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.88)
            else {
                self.onCancel()
                return
            }
            self.onCapture(data)
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            self.onCancel()
        }
    }
}
