import SwiftUI
import UIKit
import PhotosUI

// Attaching a photo to a session: take one or pick one, upload the bytes to
// the hop host (the same POST /api/sessions/upload the web's drag-and-drop
// uses — a phone has no path Claude can read, the host does), then paste the
// landed path into the composer so Claude reads the image like any file.

/// The camera, as a SwiftUI sheet. UIImagePickerController is the one system
/// camera UI that needs no extra framework and works on every phone; the
/// library side uses SwiftUI's `.photosPicker`, which needs no permission
/// prompt at all (it's the system picker, sandboxed to what you choose).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

/// JPEG bytes sized for an upload over a phone link. A 12MP capture is
/// 3–6MB of HEIC that Claude cannot read anyway; 2048px on the long edge at
/// 0.85 is a few hundred KB and every detail a model can use. Also strips
/// orientation surprises by re-rendering the image upright.
func jpegForUpload(_ image: UIImage, maxEdge: CGFloat = 2048) -> Data? {
    let w = image.size.width, h = image.size.height
    guard w > 0, h > 0 else { return nil }
    let scale = min(1, maxEdge / max(w, h))
    let target = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
    let fmt = UIGraphicsImageRendererFormat.default()
    fmt.scale = 1
    let upright = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return upright.jpegData(compressionQuality: 0.85)
}

/// Quote a path for a shell only when it needs it — a port of the web's
/// shellQuotePath, so a pasted path reads identically on both clients. Bare
/// when safe (most uploads land somewhere boring), single-quoted otherwise.
func shellQuotePath(_ path: String) -> String {
    if path.isEmpty { return "''" }
    let safe = path.unicodeScalars.allSatisfy { s in
        (s.value >= 48 && s.value <= 57)        // 0-9
        || (s.value >= 65 && s.value <= 90)     // A-Z
        || (s.value >= 97 && s.value <= 122)    // a-z
        || "_@%+=:,./-".unicodeScalars.contains(s)
    }
    if safe { return path }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
