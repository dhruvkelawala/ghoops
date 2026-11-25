import SwiftUI
import VisionKit

struct PairingScanner: UIViewControllerRepresentable {
    var receive: (String) -> Bool
    var unavailable: () -> Void

    static var available: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanner: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: false)
        scanner.delegate = context.coordinator
        Task { @MainActor [weak scanner] in
            guard let scanner else { return }
            do { try scanner.startScanning() }
            catch { unavailable() }
        }
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.scanner = self
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var scanner: PairingScanner
        init(scanner: PairingScanner) { self.scanner = scanner }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let item) in addedItems {
                if let text = item.payloadStringValue, scanner.receive(text) {
                    dataScanner.stopScanning()
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            scanner.unavailable()
        }
    }
}
