import SwiftUI
import VisionKit

/// Photographs a book's front cover with the system document scanner, which finds the
/// cover's edges, straightens it and crops away the background. That gives a clean
/// cover image and much easier text to read. Falls back to a plain photo picker where
/// the scanner isn't available (the simulator).
struct CoverCapture: View {
    let onImage: (UIImage) -> Void

    var body: some View {
        if VNDocumentCameraViewController.isSupported {
            CoverScanner(onImage: onImage)
                .ignoresSafeArea()
        } else {
            CameraPicker(onImage: onImage)
                .ignoresSafeArea()
        }
    }
}

private struct CoverScanner: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: CoverScanner

        init(parent: CoverScanner) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Only the first page is used: the front cover.
            if scan.pageCount > 0 {
                parent.onImage(scan.imageOfPage(at: 0))
            }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
