import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
@preconcurrency import Vision

/// 歌詞カード (ブックレット・歌詞カード・その写真) の文字を端末の中で読む。
///
/// 認識は Vision (端末の中だけ。画像はどこにも送らず、保存もしない)。言語補正は入れる
/// (読みが言葉として通るように)。1 片ごとに上位 3 つの候補を取り、英単語を端末の辞書
/// (`UITextChecker`) に通して、言葉にならない読み (a と o の見間違いなど) を避ける。
/// 候補の選び方と見直しの要否、読み順の作り直しはコア (`lyricOcrPickCandidate` / `lyricOcrLayout`) が決める。
/// 結果は入力欄に入れるだけで、本人が見直してから送る。
enum LyricsCardOCR {
    struct Reading {
        let text: String
        /// 読み取りに自信の無い行。本人に見直してもらう。
        let doubtfulLines: [String]
    }

    /// 1 片の枠 (左上原点の画素) と候補。
    private struct RawPiece: Sendable {
        let x, y, width, height: Double
        let candidates: [(text: String, confidence: Double)]
    }

    /// 写真を順に読み、1 枚ずつ並べ直した本文を空行でつないで返す。
    @MainActor
    static func read(_ images: [UIImage]) async -> Reading {
        let cgImages = images.compactMap(\.cgImage)
        let pages = await Task.detached(priority: .userInitiated) {
            cgImages.map { image -> (CGImage, [RawPiece]) in
                let ready = prepared(image) ?? image
                return (ready, recognize(ready))
            }
        }.value
        let checker = UITextChecker()
        var texts: [String] = []
        var doubtful: [String] = []
        for (image, raw) in pages {
            var pieces: [OcrPiece] = []
            for piece in raw {
                var candidates = piece.candidates.map {
                    OcrCandidate(text: $0.text, confidence: $0.confidence,
                                 unknownWords: unknownWords(in: $0.text, checker: checker))
                }
                // 日本語の読みで辞書に無い英単語が残った片は、その部分だけ英語として読み直して候補に足す
                // (日本語の読みでは英単語の間の空白が落ちたり、字形の似た字に化けたりする)。
                // 日本語の混じる片は読み直さない (英語の読みでは日本語の字が落ちるため)。
                if candidates.allSatisfy({ $0.unknownWords > 0 }),
                   let top = candidates.first?.text, top.unicodeScalars.allSatisfy(\.isASCII) {
                    let english = await Task.detached(priority: .userInitiated) {
                        recognizeEnglish(image, x: piece.x, y: piece.y, width: piece.width, height: piece.height)
                    }.value
                    candidates += english.map {
                        OcrCandidate(text: $0.text, confidence: $0.confidence,
                                     unknownWords: unknownWords(in: $0.text, checker: checker))
                    }
                }
                let choice = lyricOcrPickCandidate(candidates: candidates)
                let text = candidates.isEmpty ? "" : candidates[Int(choice.index)].text
                pieces.append(OcrPiece(text: text, x: piece.x, y: piece.y, width: piece.width, height: piece.height,
                                       doubtful: choice.doubtful))
            }
            let layout = lyricOcrLayout(pieces: pieces)
            if !layout.text.isEmpty { texts.append(layout.text) }
            doubtful += layout.doubtfulLines
        }
        return Reading(text: texts.joined(separator: "\n\n"), doubtfulLines: doubtful)
    }

    /// 端末の英語の辞書に無い単語の数。
    @MainActor
    private static func unknownWords(in text: String, checker: UITextChecker) -> UInt32 {
        UInt32(lyricOcrLatinWords(text: text).filter { word in
            let range = NSRange(word.startIndex..., in: word)
            return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                                 wrap: false, language: "en_US").location != NSNotFound
        }.count)
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

    /// 1 枚の文字の片と候補 (左上原点の画素の枠)。
    private static func recognize(_ image: CGImage) -> [RawPiece] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let width = Double(image.width), height = Double(image.height)
        return (request.results ?? []).compactMap { observation in
            let candidates = observation.topCandidates(3).map { ($0.string, Double($0.confidence)) }
            guard !candidates.isEmpty else { return nil }
            let box = observation.boundingBox  // 左下原点・0〜1
            return RawPiece(x: box.minX * width, y: (1 - box.maxY) * height,
                            width: box.width * width, height: box.height * height,
                            candidates: candidates)
        }
    }

    /// 片の枠の部分だけを英語として読み直す (少し余白を付けて切り出す)。
    private static func recognizeEnglish(_ image: CGImage, x: Double, y: Double, width: Double,
                                         height: Double) -> [(text: String, confidence: Double)] {
        let pad = height * 0.3
        let rect = CGRect(x: x - pad, y: y - pad, width: width + pad * 2, height: height + pad * 2)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let crop = image.cropping(to: rect.integral) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: crop, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        guard !lines.isEmpty else { return [] }
        return [(lines.map(\.string).joined(separator: " "), Double(lines.map(\.confidence).min() ?? 0))]
    }
}
