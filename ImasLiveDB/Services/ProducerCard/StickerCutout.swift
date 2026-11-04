import CoreImage
import UIKit
import Vision

/// 名刺の素材の背景を切り抜く (写っている人や物だけを残した透過の画像にする)。
/// 端末の中だけで切り抜く (Vision の前景の切り出し。画像をどこにも送らない)。
enum StickerCutout {
    enum Failure: Error {
        /// 切り抜ける人や物が見つからなかった。
        case noSubject
        /// 端末が切り抜きに対応していない・画像を読めなかった。
        case unavailable
    }

    /// 前景だけを残した画像 (被写体の外接に切り詰める)。
    static func cutout(_ image: UIImage) async throws -> UIImage {
        let upright = PaperCardRectifier.upright(image)
        guard let cg = upright.cgImage else { throw Failure.unavailable }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw Failure.unavailable
            }
            guard let result = request.results?.first, !result.allInstances.isEmpty else { throw Failure.noSubject }
            let buffer: CVPixelBuffer
            do {
                buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                        croppedToInstancesExtent: true)
            } catch {
                throw Failure.unavailable
            }
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { throw Failure.unavailable }
            return UIImage(cgImage: out)
        }.value
    }
}
