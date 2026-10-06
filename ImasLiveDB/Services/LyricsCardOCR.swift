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
                let pieces = recognize(cg)
                let text = lyricOcrLayout(pieces: pieces).text
                if !text.isEmpty { pages.append(text) }
            }
            return pages.joined(separator: "\n\n")
        }.value
    }

    /// 1 枚の文字の片 (左上原点の画素の枠)。言語の自動補正は切る (歌詞の字を書き換えさせない)。
    private static func recognize(_ image: CGImage) -> [OcrPiece] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
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
