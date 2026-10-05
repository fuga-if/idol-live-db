import SwiftUI
@preconcurrency import Vision
@preconcurrency import VisionKit

// =============================================================================
// 名刺を読むカメラ。
//
// CardQRScanner        アプリの名刺の QR を読む (VisionKit の DataScanner)。読めた文字列を 1 回だけ返す。
// PaperCardCamera      紙の名刺の表裏を撮る (VisionKit の書類カメラ。名刺の形に切り抜かれる)。
// PaperCardCodeReader  撮った写真から QR を拾う (Vision)。文字の読み取りはしない。
// =============================================================================

// MARK: - QR を読む

struct CardQRScanner: UIViewControllerRepresentable {
    /// 読めた QR の中身。同じ中身を何度も返さない。
    let onScan: (String) -> Void

    /// この端末でカメラの読み取りが使えるか (シミュレータ・古い端末・カメラを許可していないと false)。
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        private var last: String?

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let code) = item, let text = code.payloadStringValue,
                      text != last else { continue }
                last = text
                onScan(text)
                return
            }
        }
    }
}

// MARK: - 紙の名刺を撮る

struct PaperCardCamera: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // 表と裏の 2 枚まで。3 枚目以降は名刺ではないので使わない。
            let images = (0..<min(scan.pageCount, 2)).map { scan.imageOfPage(at: $0) }
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: any Error) {
            onCancel()
        }
    }
}

// MARK: - 写真から QR を拾う

enum PaperCardCodeReader {
    /// 写真に刷られた QR の中身 (写真の順、重複なし)。
    static func codes(in images: [UIImage]) async -> [String] {
        let cgImages = images.compactMap(\.cgImage)
        return await Task.detached(priority: .userInitiated) {
            var found: [String] = []
            for cg in cgImages {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([request])
                for result in request.results ?? [] {
                    if let text = result.payloadStringValue, !found.contains(text) { found.append(text) }
                }
            }
            return found
        }.value
    }
}
