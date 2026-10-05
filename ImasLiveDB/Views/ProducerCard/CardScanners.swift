import CoreImage.CIFilterBuiltins
import SwiftUI
@preconcurrency import Vision
@preconcurrency import VisionKit

// =============================================================================
// 名刺を読むカメラ。
//
// CardQRScanner        アプリの名刺の QR を読む (VisionKit の DataScanner)。読めた文字列を 1 回だけ返す。
// PaperCardCamera      紙の名刺の表裏を撮る (VisionKit の書類カメラ。名刺の形に切り抜かれる)。
// PaperCardCodeReader  撮った写真から QR を拾う (Vision)。文字の読み取りはしない。
// PaperCardRectifier   写真ライブラリから選んだ紙の名刺を、四隅を見つけて平らにして切り抜く。
// PhotoQRReader        写真に写った QR を 1 つ読む (自分の QR を写真から入れるとき)。
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

// MARK: - 写真の名刺を平らにする

/// 写真ライブラリから選んだ紙の名刺の写真を、真上から撮ったように平らにして切り抜く。
/// 書類カメラ (`PaperCardCamera`) で撮ったものは切り抜き済みなので通さない。
///
/// 四隅は Vision の書類の検出 (`VNDetectDocumentSegmentationRequest`) で探し、見つからなければ
/// 四角の検出 (`VNDetectRectanglesRequest`) で探す。どちらも見つからなければ元の写真のまま。
/// 四隅は左上・右上・右下・左下の順、写真の中の 0〜1 (左上が原点)。
enum PaperCardRectifier {
    struct Result {
        /// 向きを揃えた元の写真 (四隅を直すときはこれに重ねる)。
        let original: UIImage
        /// 見つけた四隅。見つからなければ nil。
        let corners: [CGPoint]?
        /// 平らにした写真 (四隅が無ければ元の写真)。
        let image: UIImage
    }

    /// 四隅を直す前の初めの形 (見つからなかったとき)。写真の内側に少し寄せた四角。
    static let defaultCorners = [CGPoint(x: 0.08, y: 0.08), CGPoint(x: 0.92, y: 0.08),
                                 CGPoint(x: 0.92, y: 0.92), CGPoint(x: 0.08, y: 0.92)]

    /// CIContext はスレッドをまたいで使ってよい (Apple の文書どおり) が Sendable ではないので、
    /// 古い Xcode の CI が並行性の検査で落とす。
    nonisolated(unsafe) private static let context = CIContext()

    static func rectify(_ image: UIImage) async -> Result {
        let upright = upright(image)
        guard let cg = upright.cgImage else { return Result(original: upright, corners: nil, image: upright) }
        let corners = await Task.detached(priority: .userInitiated) { detectCorners(cg) }.value
        guard let corners, let flat = correct(upright, corners: corners) else {
            return Result(original: upright, corners: nil, image: upright)
        }
        return Result(original: upright, corners: corners, image: flat)
    }

    /// 写真の向きを上に揃え、長辺を 3000px までに縮める (Vision と CoreImage は向きを見ないため)。
    static func upright(_ image: UIImage, maxPixels: CGFloat = 3000) -> UIImage {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, maxPixels / max(px.width, px.height, 1))
        guard image.imageOrientation != .up || ratio < 1 else { return image }
        let size = CGSize(width: (px.width * ratio).rounded(), height: (px.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 四隅を探す。Vision の座標 (左下が原点) を左上が原点に直して返す。
    nonisolated static func detectCorners(_ cg: CGImage) -> [CGPoint]? {
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let document = VNDetectDocumentSegmentationRequest()
        if (try? handler.perform([document])) != nil,
           let found = document.results?.first, found.confidence >= 0.5,
           let quad = plausible(corners(of: found)) {
            return quad
        }
        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 1
        rectangles.minimumConfidence = 0.6
        rectangles.minimumSize = 0.2
        rectangles.minimumAspectRatio = 0.3
        rectangles.quadratureTolerance = 30
        if (try? handler.perform([rectangles])) != nil, let found = rectangles.results?.first {
            return plausible(corners(of: found))
        }
        return nil
    }

    /// 写真の縁に 2 つ以上の角が貼り付いた四角は名刺ではない (書類の検出は何も写っていない
    /// 写真でも縁に沿った四角を返すことがある)。小さすぎる四角も捨てる。
    nonisolated private static func plausible(_ quad: [CGPoint]) -> [CGPoint]? {
        let margin: CGFloat = 0.015
        let onEdge = quad.filter { $0.x < margin || $0.x > 1 - margin || $0.y < margin || $0.y > 1 - margin }
        // 四角の面積 (靴紐の公式)。
        var area: CGFloat = 0
        for i in quad.indices {
            let a = quad[i], b = quad[(i + 1) % quad.count]
            area += a.x * b.y - b.x * a.y
        }
        return onEdge.count < 2 && abs(area) / 2 >= 0.08 ? quad : nil
    }

    nonisolated private static func corners(of r: VNRectangleObservation) -> [CGPoint] {
        [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
    }

    /// 四隅を真上から見た長方形に引き伸ばす (CoreImage の `CIPerspectiveCorrection`)。
    static func correct(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4, let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // CoreImage は左下が原点。
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: (1 - p.y) * h) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cg)
        filter.topLeft = point(corners[0])
        filter.topRight = point(corners[1])
        filter.bottomRight = point(corners[2])
        filter.bottomLeft = point(corners[3])
        guard let output = filter.outputImage, output.extent.width >= 32, output.extent.height >= 32,
              let result = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: result)
    }
}

// MARK: - 写真に写った QR を読む

enum PhotoQRReader {
    /// 写真に写った QR の中身 (先頭の 1 つ)。無ければ nil。
    static func firstCode(in image: UIImage) async -> String? {
        await PaperCardCodeReader.codes(in: [PaperCardRectifier.upright(image)]).first
    }
}
