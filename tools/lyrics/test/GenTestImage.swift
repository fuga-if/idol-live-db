// GenTestImage.swift — 読み順検証用のテスト画像を生成する。
//
// 実物のブックレットはリポジトリに置けない (著作物) ので、検証は
// ここで描いた自作のダミー文 (著作物ではない仮名の羅列) で行う。
// CoreText で本物の縦組み (kCTFrameProgressionRightToLeft + 縦組み字形) を描くので、
// 列の位置関係・字送りは実際の縦書きブックレットと同じ性質になる。
//
//   swiftc -O test/GenTestImage.swift -o bin/gen-testimage
//   ./bin/gen-testimage <出力ディレクトリ>

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct TextBlock {
    var text: String
    var rect: CGRect          // 左下原点 (CoreGraphics 素のまま)
    var fontSize: CGFloat
    var vertical: Bool
}

func draw(blocks: [TextBlock], size: CGSize, to url: URL) {
    guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))

    for b in blocks {
        let fontName = b.vertical ? "HiraMinProN-W3" : "HiraginoSans-W3"
        let font = CTFontCreateWithName(fontName as CFString, b.fontSize, nil)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1),
        ]
        if b.vertical { attrs[kCTVerticalFormsAttributeName as NSAttributedString.Key] = true }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = b.fontSize * 0.55
        attrs[.paragraphStyle] = para

        let attr = NSAttributedString(string: b.text, attributes: attrs)
        let fs = CTFramesetterCreateWithAttributedString(attr)
        let frameAttrs: CFDictionary = b.vertical
            ? [kCTFrameProgressionAttributeName: CTFrameProgression.rightToLeft.rawValue] as CFDictionary
            : [:] as CFDictionary
        let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0),
                                             CGPath(rect: b.rect, transform: nil), frameAttrs)
        CTFrameDraw(frame, ctx)
    }

    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    FileHandle.standardError.write("gen: \(url.lastPathComponent)\n".data(using: .utf8)!)
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

// --- 1. 縦書き 1 段 ---------------------------------------------------------
// 期待読み順: 右の列から左へ。verify.py の期待値と対応。
let v1 = ["あかつきのそらへ", "ちいさなてをふる", "きみのなまえをよぶ",
          "かぜがはこんでゆく", "ゆめのつづきをうたう", "ひかりのなかで"]
draw(blocks: [TextBlock(text: v1.joined(separator: "\n"),
                        rect: CGRect(x: 120, y: 200, width: 1360, height: 1600),
                        fontSize: 58, vertical: true)],
     size: CGSize(width: 1600, height: 2000),
     to: dir.appendingPathComponent("vertical.png"))

// --- 2. 縦書き + ルビ -------------------------------------------------------
// 本文 58px の右脇に 26px のルビを添える (実物のルビ比率に近い)。
let v2body = ["あかつきのそらへ", "ちいさなてをふる", "きみのなまえをよぶ", "ひかりのなかで"]
var rubyBlocks: [TextBlock] = [
    TextBlock(text: v2body.joined(separator: "\n"),
              rect: CGRect(x: 120, y: 200, width: 1360, height: 1600),
              fontSize: 58, vertical: true),
]
// 縦組みのルビは基底列の「右脇」= 列間の谷に入る。本文の字面に重ねない。
// 本文 58px の列ピッチは約 120px、字面 54px なので谷は約 66px。そこに 26px を置く。
rubyBlocks.append(TextBlock(text: "あさひ",
                            rect: CGRect(x: 1386, y: 1620, width: 34, height: 130),
                            fontSize: 26, vertical: true))
rubyBlocks.append(TextBlock(text: "こえ",
                            rect: CGRect(x: 1266, y: 1650, width: 34, height: 100),
                            fontSize: 26, vertical: true))
draw(blocks: rubyBlocks,
     size: CGSize(width: 1600, height: 2000),
     to: dir.appendingPathComponent("vertical_ruby.png"))

// --- 3. 縦書き 2 段 (上下) --------------------------------------------------
// 上段を読み切ってから下段。段の間に大きな余白を空ける。
let v3top = ["あかつきのそらへ", "ちいさなてをふる", "きみのなまえをよぶ"]
let v3bottom = ["かぜがはこんでゆく", "ゆめのつづきをうたう", "ひかりのなかで"]
draw(blocks: [
    TextBlock(text: v3top.joined(separator: "\n"),
              rect: CGRect(x: 120, y: 1180, width: 1360, height: 760),
              fontSize: 52, vertical: true),
    TextBlock(text: v3bottom.joined(separator: "\n"),
              rect: CGRect(x: 120, y: 120, width: 1360, height: 760),
              fontSize: 52, vertical: true),
], size: CGSize(width: 1600, height: 2000),
   to: dir.appendingPathComponent("vertical_2block.png"))

// --- 4. 横書き 2 段組み (左右) ---------------------------------------------
// 左段を読み切ってから右段。素朴に y でソートすると左右が混ざる = 失敗ケース。
let h4left = ["あかつきのそらへ", "ちいさなてをふる", "きみのなまえをよぶ"]
let h4right = ["かぜがはこんでゆく", "ゆめのつづきをうたう", "ひかりのなかで"]
draw(blocks: [
    TextBlock(text: h4left.joined(separator: "\n"),
              rect: CGRect(x: 100, y: 200, width: 620, height: 1600),
              fontSize: 46, vertical: false),
    TextBlock(text: h4right.joined(separator: "\n"),
              rect: CGRect(x: 900, y: 200, width: 620, height: 1600),
              fontSize: 46, vertical: false),
], size: CGSize(width: 1600, height: 2000),
   to: dir.appendingPathComponent("horizontal_2col.png"))

// --- 5. 横書き 1 段 ---------------------------------------------------------
draw(blocks: [
    TextBlock(text: (h4left + h4right).joined(separator: "\n"),
              rect: CGRect(x: 100, y: 200, width: 1400, height: 1600),
              fontSize: 52, vertical: false),
], size: CGSize(width: 1600, height: 2000),
   to: dir.appendingPathComponent("horizontal.png"))
