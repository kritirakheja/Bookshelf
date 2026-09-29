import SwiftUI
import VisionKit

/// Live camera view that reports the first book barcode (ISBN) it sees.
/// Needs a real iPhone: `DataScannerViewController` isn't supported in the simulator.
struct ScannerView: UIViewControllerRepresentable {
    let onISBN: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onISBN: onISBN) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onISBN: (String) -> Void
        private var reported = false

        init(onISBN: @escaping (String) -> Void) {
            self.onISBN = onISBN
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !reported else { return }
            for case .barcode(let barcode) in items {
                // Book barcodes are EAN-13 codes starting 978 or 979; others are prices etc.
                if let code = barcode.payloadStringValue, code.hasPrefix("978") || code.hasPrefix("979") {
                    reported = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onISBN(code)
                    return
                }
            }
        }
    }
}
