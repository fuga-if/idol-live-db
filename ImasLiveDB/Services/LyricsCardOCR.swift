import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
@preconcurrency import Vision

/// 歌詞カード (ブックレット・歌詞カード・その写真) の文字を端末の中で読む。
///
/// 認識は Vision (端末の中だけ。画像はどこにも送らず、保存もしない)。読み順の作り直し
/// (縦書き・段組み・ルビ外し・空行) はコアの `lyricOcrLayout` が決める。
/// 結果は入力欄に入れるだけで、本人が見直してから送る。認識した字は直さない。
enum LyricsCardOCR {
    /// 写真を順に読み、1 枚ずつ並べ直した本文を空行でつないで返す。
    static func read(_ images: [UIImage]) async -> String {
        let cgImages = images.compactMap(\.cgImage)
        return await Task.detached(priority: .userInitiated) {
            var pages: [String] = []
            for cg in cgImages {
                let pieces = recognize(prepared(cg) ?? cg)
                let text = lyricOcrLayout(pieces: pieces).text
                if !text.isEmpty { pages.append(text) }
            }
            return pages.joined(separator: "\n\n")
        }.value
    }

    private static let context = CIContext()

    /// 読み取りの前の下ごしらえ。色を抜いて明暗をはっきりさせ (色の地や写真の上の文字に効く)、
    /// 小さい画像 (スクリーンショットの切り抜きなど) は短辺 2,000px まで拡大する。字の形は変えない。
    private static func prepared(_ image: CGImage) -> CGImage? {
        var ci = CIImage(cgImage: image)
        let shortSide = Double(min(image.width, image.height))
        if shortSide > 0, shortSide < 2000 {
            let scale = CIFilter.lanczosScaleTransform()
            scale.inputImage = ci
            scale.scale = Float(min(2000 / shortSide, 3))
            scale.aspectRatio = 1
            if let out = scale.outputImage { ci = out }
        }
        let tone = CIFilter.colorControls()
        tone.inputImage = ci
        tone.saturation = 0
        tone.contrast = 1.3
        guard let out = tone.outputImage else { return nil }
        return context.createCGImage(out, from: out.extent)
    }

    /// 1 枚の文字の片 (左上原点の画素の枠)。言語の自動補正は切る (歌詞の字を書き換えさせない)。
    private static func recognize(_ image: CGImage) -> [OcrPiece] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        request.revision = VNRecognizeTextRequestRevision3
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let width = Double(image.width), height = Double(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox  // 左下原点・0〜1
            return OcrPiece(text: text,
                            x: box.minX * width,
                            y: (1 - box.maxY) * height,
                            width: box.width * width,
                            height: box.height * height)
        }
    }
}
