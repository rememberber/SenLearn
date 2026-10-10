import SwiftUI
import VisionKit

struct DocumentCamera: UIViewControllerRepresentable {
    var onComplete: ([Data]) -> Void
    var onCancel: () -> Void
    var onFailure: (Error) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: DocumentCamera

        init(parent: DocumentCamera) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.onFailure(MaterialImporter.ImportError.noPhotos); return }
            guard scan.pageCount <= MaterialImporter.maximumPhotos else { parent.onFailure(MaterialImporter.ImportError.tooManyPhotos); return }
            var pages: [Data] = []
            var totalBytes = 0
            for index in 0..<scan.pageCount {
                let data = autoreleasepool { scan.imageOfPage(at: index).jpegData(compressionQuality: 0.9) }
                guard let data else { parent.onFailure(MaterialImporter.ImportError.encodingFailed); return }
                guard data.count <= MaterialImporter.maximumFileBytes - totalBytes else { parent.onFailure(MaterialImporter.ImportError.fileTooLarge); return }
                totalBytes += data.count
                pages.append(data)
            }
            parent.onComplete(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onFailure(error) }
    }
}
