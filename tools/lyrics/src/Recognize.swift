// Recognize.swift — Vision で画像から文字を拾う層。
//
// macOS 26 には新旧 2 系統の文字認識がある:
//   - RecognizeTextRequest       … 行単位の observation を返す
//   - RecognizeDocumentsRequest  … 段落/表/リストまで構造化した DocumentObservation
//
// 縦書き歌詞ブックレットで両方試した結果 (docs は tools/lyrics/Makefile の verify 参照):
//   両者の `lines` は同一の RecognizedTextObservation を返すが、
//   RecognizeDocumentsRequest の `transcript` は縦書きの列を横につなげてしまい
//   読み順が壊れる。よって transcript は使わず、どちらの engine でも
//   行 observation だけを取り出して Layout.swift で自前に並べ替える。
//   既定は軽い RecognizeTextRequest。

import CoreGraphics
import Foundation
import ImageIO
import Vision

enum Engine: String {
    case text
    case documents
}

struct RecognizeOptions {
    var engine: Engine = .text
    var languages: [String] = ["ja-JP", "en-US"]
    /// 言語補正。歌詞は造語・当て字が多く、補正は「画像に無い語」に化けうるので既定 off。
    var languageCorrection: Bool = false
    var customWords: [String] = []
}

enum RecognizeError: Error, CustomStringConvertible {
    case unsupportedOS
    case cannotLoadImage(String)
    case cannotLoadPDF(String)

    var description: String {
        switch self {
        case .unsupportedOS: return "macOS 26 以降が必要"
        case .cannotLoadImage(let p): return "画像を読めない: \(p)"
        case .cannotLoadPDF(let p): return "PDF を読めない: \(p)"
        }
    }
}

@available(macOS 26.0, *)
enum Recognizer {

    /// 画像 1 枚を認識して Piece 配列にする。
    static func pieces(in image: CGImage, options: RecognizeOptions) async throws -> [Piece] {
        let observations: [RecognizedTextObservation]
        switch options.engine {
        case .text:
            var req = RecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.recognitionLanguages = options.languages.map { Locale.Language(identifier: $0) }
            req.usesLanguageCorrection = options.languageCorrection
            if !options.customWords.isEmpty { req.customWords = options.customWords }
            observations = try await req.perform(on: image)
        case .documents:
            let req = RecognizeDocumentsRequest()
            let docs = try await req.perform(on: image)
            observations = docs.flatMap { $0.document.text.lines }
        }

        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        return observations.compactMap { obs in
            let candidates = obs.topCandidates(3)
            guard let best = candidates.first else { return nil }
            let n = obs.boundingBox.cgRect  // 正規化・原点左下
            // 原点左上のピクセル座標へ。
            let box = CGRect(x: n.origin.x * w,
                             y: (1.0 - n.origin.y - n.height) * h,
                             width: n.width * w,
                             height: n.height * h)
            return Piece(text: best.string,
                         box: box,
                         confidence: best.confidence,
                         alternatives: candidates.dropFirst().map { $0.string })
        }
    }

    /// 入力パス 1 つ (画像 or PDF) を CGImage 群に展開する。PDF は全ページ。
    static func loadImages(path: String, pdfDPI: CGFloat) throws -> [CGImage] {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = CGPDFDocument(url as CFURL) else { throw RecognizeError.cannotLoadPDF(path) }
            var out: [CGImage] = []
            for i in 1...max(doc.numberOfPages, 1) {
                guard let page = doc.page(at: i) else { continue }
                if let img = rasterize(page: page, dpi: pdfDPI) { out.append(img) }
            }
            return out
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw RecognizeError.cannotLoadImage(path)
        }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { throw RecognizeError.cannotLoadImage(path) }
        var out: [CGImage] = []
        for i in 0..<count {
            // HEIC / TIFF の多重画像も一応全部見る (通常は 1 枚)。
            let opts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            if let img = CGImageSourceCreateImageAtIndex(src, i, opts as CFDictionary) { out.append(img) }
        }
        guard !out.isEmpty else { throw RecognizeError.cannotLoadImage(path) }
        return out
    }

    private static func rasterize(page: CGPDFPage, dpi: CGFloat) -> CGImage? {
        let media = page.getBoxRect(.cropBox)
        let scale = dpi / 72.0
        let w = Int((media.width * scale).rounded())
        let h = Int((media.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -media.origin.x, y: -media.origin.y)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}
