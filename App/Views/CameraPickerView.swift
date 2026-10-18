import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CameraCheDo: String, Identifiable {
    case photo
    case video
    case caHai
    var id: String { rawValue }
}

struct CameraPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var cheDo: CameraCheDo = .caHai
    var onChupAnh: ((UIImage) -> Void)? = nil
    var onQuayVideo: ((URL) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        let coCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
        picker.sourceType = coCamera ? .camera : .photoLibrary

        switch cheDo {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
            if coCamera { picker.cameraCaptureMode = .photo }
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
            if coCamera {
                picker.cameraCaptureMode = .video
                picker.videoQuality = .typeMedium
            }
        case .caHai:
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            if coCamera {
                picker.cameraCaptureMode = .photo
                picker.videoQuality = .typeMedium
            }
        }

        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            defer { parent.dismiss() }

            if let videoURL = info[.mediaURL] as? URL {
                // Sao chép ngay video sang thư mục tạm độc lập trước khi UIImagePickerController bị huỷ
                let tempDir = FileManager.default.temporaryDirectory
                let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
                let destURL = tempDir.appendingPathComponent("quay_\(UUID().uuidString).\(ext)")
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: videoURL, to: destURL)
                let fileURL = FileManager.default.fileExists(atPath: destURL.path) ? destURL : videoURL
                parent.onQuayVideo?(fileURL)
            } else if let image = info[.originalImage] as? UIImage {
                parent.onChupAnh?(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
