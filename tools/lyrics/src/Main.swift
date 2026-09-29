// Main.swift — lyrics-ocr CLI 本体。
//
// CD ブックレット画像から「写っている文字」だけを起こす。推測補完はしない。
// 使い方は --help を参照。ビルドは tools/lyrics/Makefile。

import CoreGraphics
import Foundation

let usage = """
lyrics-ocr — CD ブックレット画像 → 歌詞テキスト (ローカル OCR / Vision)

usage:
  lyrics-ocr [options] <画像 or ディレクトリ or PDF> ...

options:
  -o, --out <path>            出力先ファイル (既定: 標準出力)
      --format text|json      出力形式 (既定: text)
      --engine text|documents Vision の認識系統 (既定: text)
      --lang <a,b>            認識言語 (既定: ja-JP,en-US)
      --orientation auto|vertical|horizontal
                              縦横の強制 (既定: auto)
      --language-correction   言語補正を有効化 (既定: 無効。歌詞は造語が多く化けるため)
      --min-confidence <f>    このスコア未満の行にマーカーを付ける (既定: 0.5)
      --marker <s>            低信頼マーカー (既定: "[?]")
      --ruby-ratio <f>        本文中央値のこの比率未満をルビ扱い (既定: 0.62)
      --gutter <f>            段組みの谷とみなす空白幅 / 文字サイズ (既定: 3.0)
      --dpi <n>               PDF ラスタライズ解像度 (既定: 300)
      --custom-words <a,b>    認識辞書に足す語 (アイドル名など)
  -q, --quiet                 進捗を出さない
  -h, --help

注意:
  - 出力は「画像に写っている文字」のみ。欠けた文字を AI が補ってはいけない。
  - 低信頼行は行頭にマーカーが付く。必ず人が原本と突き合わせること。
  - 出力の "# " 始まりはメタ情報。postprocess.py がこの規約を使う。
"""

struct Options {
    var inputs: [String] = []
    var out: String?
    var format = "text"
    var recognize = RecognizeOptions()
    var layout = LayoutOptions(forcedOrientation: nil)
    var emit = EmitOptions()
    var dpi: CGFloat = 300
    var quiet = false
}

func parseArgs() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func next(_ flag: String) -> String {
        guard !args.isEmpty else { fail("\(flag) に値が必要") }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "-h", "--help": print(usage); exit(0)
        case "-q", "--quiet": o.quiet = true
        case "-o", "--out": o.out = next(a)
        case "--format": o.format = next(a)
        case "--engine":
            let v = next(a)
            guard let e = Engine(rawValue: v) else { fail("--engine は text|documents") }
            o.recognize.engine = e
        case "--lang": o.recognize.languages = next(a).split(separator: ",").map(String.init)
        case "--custom-words": o.recognize.customWords = next(a).split(separator: ",").map(String.init)
        case "--language-correction": o.recognize.languageCorrection = true
        case "--orientation":
            let v = next(a)
            if v == "auto" { o.layout.forcedOrientation = nil }
            else if let ori = Orientation(rawValue: v) { o.layout.forcedOrientation = ori }
            else { fail("--orientation は auto|vertical|horizontal") }
        case "--min-confidence": o.emit.minConfidence = Float(next(a)) ?? 0.5
        case "--marker": o.emit.marker = next(a)
        case "--ruby-ratio": o.layout.rubyRatio = CGFloat(Double(next(a)) ?? 0.62)
        case "--gutter": o.layout.gutterCharUnits = CGFloat(Double(next(a)) ?? 3.0)
        case "--dpi": o.dpi = CGFloat(Double(next(a)) ?? 300)
        default:
            if a.hasPrefix("-") { fail("未知のオプション: \(a)") }
            o.inputs.append(a)
        }
    }
    if o.inputs.isEmpty { print(usage); exit(2) }
    return o
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("エラー: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "pdf", "webp", "gif", "bmp"]

/// ディレクトリを再帰せず 1 段だけ展開し、名前順に並べる (ページ順を保つため)。
func expandInputs(_ inputs: [String]) -> [String] {
    var out: [String] = []
    let fm = FileManager.default
    for path in inputs {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { fail("見つからない: \(path)") }
        if isDir.boolValue {
            let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
            for c in children.sorted(by: naturalLess) where imageExtensions.contains((c as NSString).pathExtension.lowercased()) {
                out.append((path as NSString).appendingPathComponent(c))
            }
        } else {
            out.append(path)
        }
    }
    return out
}

/// page2.jpg が page10.jpg より前に来るように数値を数値として比較する。
func naturalLess(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
}

@available(macOS 26.0, *)
@main
struct LyricsOCR {
    static func main() async {
        let o = parseArgs()
        let files = expandInputs(o.inputs)
        if files.isEmpty { fail("処理対象の画像が無い") }

        var pages: [PageResult] = []
        var pageIndex = 0
        for file in files {
            let images: [CGImage]
            do { images = try Recognizer.loadImages(path: file, pdfDPI: o.dpi) }
            catch { FileHandle.standardError.write("スキップ (\(error)): \(file)\n".data(using: .utf8)!); continue }

            for img in images {
                pageIndex += 1
                if !o.quiet {
                    FileHandle.standardError.write("[\(pageIndex)] \(file) (\(img.width)x\(img.height))\n".data(using: .utf8)!)
                }
                do {
                    let pieces = try await Recognizer.pieces(in: img, options: o.recognize)
                    let size = CGSize(width: img.width, height: img.height)
                    let r = Layout.analyze(pieces: pieces, pixelSize: size, options: o.layout)
                    pages.append(PageResult(sourcePath: file,
                                            pageIndex: pageIndex,
                                            pixelSize: size,
                                            orientation: r.orientation,
                                            orientationDecidedBy: r.decidedBy,
                                            verticalVote: r.vVote,
                                            horizontalVote: r.hVote,
                                            blocks: r.blocks,
                                            rubyPieces: r.ruby,
                                            rubyAmbiguousCount: r.rubyAmbiguous,
                                            notes: r.notes))
                } catch {
                    FileHandle.standardError.write("認識失敗 (\(error)): \(file)\n".data(using: .utf8)!)
                }
            }
        }

        let header = [
            "lyrics-ocr raw output — 画像に写っている文字のみ。推測補完なし。",
            "generated: \(ISO8601DateFormatter().string(from: Date()))",
            "engine: \(o.recognize.engine.rawValue) / lang: \(o.recognize.languages.joined(separator: ","))"
                + " / language-correction: \(o.recognize.languageCorrection ? "on" : "off")",
        ]
        let body = o.format == "json"
            ? Emit.json(pages, options: o.emit)
            : Emit.text(pages, options: o.emit, header: header)

        if let out = o.out {
            let url = URL(fileURLWithPath: out)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            do { try body.write(to: url, atomically: true, encoding: .utf8) }
            catch { fail("書き出せない: \(out) (\(error))") }
            if !o.quiet { FileHandle.standardError.write("→ \(out)\n".data(using: .utf8)!) }
        } else {
            print(body, terminator: "")
        }
    }
}
