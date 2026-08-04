// Model.swift — OCR 中間表現。
//
// Vision の正規化座標 (原点 左下 / 0...1) は縦書きの並び替えで直感に反するので、
// 取り込んだ時点でピクセル座標 (原点 左上) に直す。以降のレイアウト処理は
// すべて「左上原点・ピクセル」で統一する。

import CoreGraphics
import Foundation

/// 文字の連なり (Vision の 1 observation)。歌詞 1 行と 1:1 とは限らない。
struct Piece {
    /// 認識文字列。ここに写っていない文字を足してはいけない。
    var text: String
    /// 左上原点のピクセル矩形。
    var box: CGRect
    /// Vision の信頼度 (0...1)。日本語は 0.5 / 1.0 に量子化されがち。
    var confidence: Float
    /// 2 位以下の候補 (人が直すときの手掛かり)。
    var alternatives: [String]
    /// ルビ判定の結果。
    var kind: Kind = .body

    enum Kind: String {
        case body
        case ruby
    }

    var charCount: Int { text.count }

    /// 「1 文字の大きさ」に相当する寸法。縦書きは幅、横書きは高さ。
    func charSize(_ orientation: Orientation) -> CGFloat {
        orientation == .vertical ? box.width : box.height
    }

    /// 行方向 (読み進む向き) の座標。
    func alongAxis(_ orientation: Orientation) -> CGFloat {
        orientation == .vertical ? box.minY : box.minX
    }

    /// 行送り方向 (次の行へ移る向き) の座標。
    func acrossAxis(_ orientation: Orientation) -> CGFloat {
        orientation == .vertical ? box.midX : box.midY
    }
}

enum Orientation: String {
    case vertical
    case horizontal
}

/// 並び替え済みの 1 行。縦書きなら 1 列。
struct Line {
    var text: String
    var confidence: Float
    var box: CGRect
    var pieces: [Piece]
    /// この行の近くにあったルビ。
    var ruby: [Piece] = []
}

/// 段組みの 1 ブロック。
struct Block {
    var lines: [Line]
    var box: CGRect
}

/// 1 ページ (画像 1 枚 / PDF 1 ページ) の結果。
struct PageResult {
    var sourcePath: String
    var pageIndex: Int
    var pixelSize: CGSize
    var orientation: Orientation
    var orientationDecidedBy: String
    var verticalVote: Int
    var horizontalVote: Int
    var blocks: [Block]
    var rubyPieces: [Piece]
    /// ルビと本文の大きさが連続していて分離しきれない疑いがある。
    var rubyAmbiguousCount: Int
    var notes: [String]
}
