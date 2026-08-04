// Layout.swift — 読み順の復元。このツールで一番壊れると困るところ。
//
// Vision は observation の配列順を保証しない (実測では概ね並んでいるが、
// 段組みや縦横混在で崩れる)。ここで幾何情報だけから並べ直す。
//
// 手順:
//   1. 縦書き / 横書きを判定 (文字数で重み付けした多数決)
//   2. ルビ (小さい文字) を本文から分離
//   3. 段組みを 1 軸カット (X-Y cut の 1 段) で分割
//   4. ブロック内で行をまとめ、縦書きは 右→左、横書きは 上→下 に並べる

import CoreGraphics
import Foundation

struct LayoutOptions {
    /// auto なら自動判定。強制もできる。
    var forcedOrientation: Orientation?
    /// 本文中央値のこの比率より小さい文字はルビ扱い。
    var rubyRatio: CGFloat = 0.62
    /// ルビ判定の「どっちつかず」上限。rubyRatio...rubyAmbiguousRatio は要注意として数える。
    var rubyAmbiguousRatio: CGFloat = 0.85
    /// 段組みの谷と見なす空白幅 (文字サイズの倍数)。列間の隙間より十分大きく。
    var gutterCharUnits: CGFloat = 3.0
    /// 同じ行 (列) と見なす行送り方向のずれ (文字サイズの倍数)。
    var lineToleranceCharUnits: CGFloat = 0.7
    /// 行内で空白を挟む閾値 (文字サイズの倍数)。
    var spaceGapCharUnits: CGFloat = 0.8
}

enum Layout {

    static func analyze(pieces rawPieces: [Piece],
                        pixelSize: CGSize,
                        options: LayoutOptions) -> (orientation: Orientation,
                                                    decidedBy: String,
                                                    vVote: Int,
                                                    hVote: Int,
                                                    blocks: [Block],
                                                    ruby: [Piece],
                                                    rubyAmbiguous: Int,
                                                    notes: [String]) {
        var notes: [String] = []
        let (detected, vVote, hVote) = detectOrientation(rawPieces)
        let orientation = options.forcedOrientation ?? detected
        let decidedBy = options.forcedOrientation == nil ? "auto" : "forced"
        if options.forcedOrientation != nil, options.forcedOrientation != detected {
            notes.append("向きを --orientation で強制した (自動判定は \(detected.rawValue))")
        }
        if vVote > 0 && hVote > 0 {
            let minority = min(vVote, hVote)
            let total = vVote + hVote
            if Double(minority) / Double(total) > 0.25 {
                notes.append("縦横が混在している疑い (縦 \(vVote) / 横 \(hVote))。ページを切り分けて再実行を推奨")
            }
        }
        if rawPieces.isEmpty {
            notes.append("文字を 1 つも検出できなかった (解像度不足 / コントラスト不足の可能性)")
            return (orientation, decidedBy, vVote, hVote, [], [], 0, notes)
        }

        // --- ルビ分離 ---
        let median = medianCharSize(rawPieces, orientation)
        var body: [Piece] = []
        var ruby: [Piece] = []
        var ambiguous = 0
        for var p in rawPieces {
            let s = p.charSize(orientation)
            if s < options.rubyRatio * median {
                p.kind = .ruby
                ruby.append(p)
            } else {
                if s < options.rubyAmbiguousRatio * median { ambiguous += 1 }
                body.append(p)
            }
        }
        if body.isEmpty {  // 全部小さいと判定された = 中央値の取り方が悪い。分離を諦める。
            body = rawPieces.map { var q = $0; q.kind = .body; return q }
            ruby = []
            notes.append("ルビ分離に失敗 (全行が小さいと判定された)。ルビは本文に混ざったまま")
        }
        if ruby.isEmpty {
            notes.append(ambiguous > 0
                ? "ルビを分離できず (本文と連続した大きさの行が \(ambiguous) 件。混在の可能性あり)"
                : "ルビらしい小さい文字は検出されなかった")
        } else if ambiguous > 0 {
            notes.append("ルビ分離が不確実 (境界付近の行が \(ambiguous) 件)。--ruby-ratio の調整を検討")
        }

        // --- 段組み分割 → 行組み立て ---
        let bodyMedian = medianCharSize(body, orientation)
        let gutter = max(bodyMedian * options.gutterCharUnits, 1)
        let groups = splitIntoBlocks(body, orientation: orientation, gutter: gutter, pixelSize: pixelSize)
        var blocks: [Block] = []
        for g in groups {
            let lines = buildLines(g, orientation: orientation, median: bodyMedian, options: options)
            guard !lines.isEmpty else { continue }
            blocks.append(Block(lines: lines, box: unionBox(g)))
        }
        if blocks.count > 1 {
            notes.append("段組みを \(blocks.count) ブロックとして分割した (--gutter で調整可)")
        }

        // --- ルビを最寄りの本文行に紐づける ---
        if !ruby.isEmpty {
            var allLines: [(bi: Int, li: Int)] = []
            for (bi, b) in blocks.enumerated() {
                for li in b.lines.indices { allLines.append((bi, li)) }
            }
            for r in ruby {
                var bestIdx: (Int, Int)? = nil
                var bestDist = CGFloat.greatestFiniteMagnitude
                for idx in allLines {
                    let d = rectDistance(r.box, blocks[idx.bi].lines[idx.li].box)
                    if d < bestDist { bestDist = d; bestIdx = (idx.bi, idx.li) }
                }
                if let (bi, li) = bestIdx { blocks[bi].lines[li].ruby.append(r) }
            }
        }

        return (orientation, decidedBy, vVote, hVote, blocks, ruby, ambiguous, notes)
    }

    // MARK: - 向き判定

    /// 文字数で重み付けした多数決。1 文字だけの observation は縦横の情報を持たないので除外。
    static func detectOrientation(_ pieces: [Piece]) -> (Orientation, Int, Int) {
        var v = 0
        var h = 0
        for p in pieces where p.charCount >= 2 {
            let w = p.box.width
            let ht = p.box.height
            if ht > w * 1.2 {
                v += p.charCount
            } else if w > ht * 1.2 {
                h += p.charCount
            }
        }
        if v == 0 && h == 0 { return (.horizontal, 0, 0) }
        return (v > h ? .vertical : .horizontal, v, h)
    }

    // MARK: - 段組み

    /// 行送り方向に空白の帯 (谷) を探して切る。
    /// 縦書きは列そのものが x 方向に並ぶので x では切らず、y の谷 (上下の段) だけを切る。
    /// 横書きはその逆で、x の谷 (左右の段) だけを切る。
    static func splitIntoBlocks(_ pieces: [Piece],
                                orientation: Orientation,
                                gutter: CGFloat,
                                pixelSize: CGSize) -> [[Piece]] {
        guard pieces.count > 1 else { return pieces.isEmpty ? [] : [pieces] }
        let cutAlongY = (orientation == .vertical)
        let extent = cutAlongY ? pixelSize.height : pixelSize.width
        guard extent > 0 else { return [pieces] }

        let bins = 2000
        let scale = CGFloat(bins) / extent
        var occupied = [Bool](repeating: false, count: bins)
        for p in pieces {
            let lo = cutAlongY ? p.box.minY : p.box.minX
            let hi = cutAlongY ? p.box.maxY : p.box.maxX
            let a = max(0, min(bins - 1, Int((lo * scale).rounded(.down))))
            let b = max(0, min(bins - 1, Int((hi * scale).rounded(.up))))
            if a <= b { for i in a...b { occupied[i] = true } }
        }
        // 端の余白は谷として扱わない。
        guard let first = occupied.firstIndex(of: true), let last = occupied.lastIndex(of: true) else {
            return [pieces]
        }
        let gutterBins = Int((gutter * scale).rounded())
        var cuts: [CGFloat] = []
        var runStart = -1
        var i = first
        while i <= last {
            if !occupied[i] {
                if runStart < 0 { runStart = i }
            } else {
                if runStart >= 0 && (i - runStart) >= gutterBins {
                    cuts.append(CGFloat(runStart + i) / 2.0 / scale)
                }
                runStart = -1
            }
            i += 1
        }
        guard !cuts.isEmpty else { return [pieces] }

        var buckets = [[Piece]](repeating: [], count: cuts.count + 1)
        for p in pieces {
            let center = cutAlongY ? p.box.midY : p.box.midX
            var idx = 0
            while idx < cuts.count && center > cuts[idx] { idx += 1 }
            buckets[idx].append(p)
        }
        let nonEmpty = buckets.filter { !$0.isEmpty }
        // 縦書きの上下段 / 横書きの左右段はどちらも「小さい座標が先」。
        return nonEmpty
    }

    // MARK: - 行組み立て

    static func buildLines(_ pieces: [Piece],
                           orientation: Orientation,
                           median: CGFloat,
                           options: LayoutOptions) -> [Line] {
        guard !pieces.isEmpty else { return [] }
        let tolerance = max(median * options.lineToleranceCharUnits, 1)

        // 行送り方向でクラスタリング。縦書きは右→左なので降順、横書きは上→下で昇順。
        let sorted = pieces.sorted { a, b in
            let av = a.acrossAxis(orientation)
            let bv = b.acrossAxis(orientation)
            if av != bv { return orientation == .vertical ? av > bv : av < bv }
            return a.alongAxis(orientation) < b.alongAxis(orientation)
        }

        var groups: [[Piece]] = []
        var current: [Piece] = []
        var anchor: CGFloat = 0
        for p in sorted {
            let v = p.acrossAxis(orientation)
            if current.isEmpty {
                current = [p]
                anchor = v
            } else if abs(v - anchor) <= tolerance {
                current.append(p)
                // アンカーは平均に寄せる (少しずつ傾いたスキャンに追随)。
                anchor = current.reduce(CGFloat(0)) { $0 + $1.acrossAxis(orientation) } / CGFloat(current.count)
            } else {
                groups.append(current)
                current = [p]
                anchor = v
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.map { g -> Line in
            let ordered = g.sorted { $0.alongAxis(orientation) < $1.alongAxis(orientation) }
            var text = ""
            var prev: Piece? = nil
            for p in ordered {
                if let q = prev {
                    let gap = p.alongAxis(orientation) - (orientation == .vertical ? q.box.maxY : q.box.maxX)
                    if gap > median * options.spaceGapCharUnits { text += " " }
                }
                text += p.text
                prev = p
            }
            let conf = ordered.map { $0.confidence }.min() ?? 0
            return Line(text: text, confidence: conf, box: unionBox(ordered), pieces: ordered)
        }
    }

    // MARK: - 補助

    static func medianCharSize(_ pieces: [Piece], _ orientation: Orientation) -> CGFloat {
        // 文字数で重み付け (長い行の文字サイズを信頼する)。
        var samples: [CGFloat] = []
        for p in pieces {
            let s = p.charSize(orientation)
            for _ in 0..<max(1, min(p.charCount, 40)) { samples.append(s) }
        }
        guard !samples.isEmpty else { return 1 }
        samples.sort()
        return samples[samples.count / 2]
    }

    static func unionBox(_ pieces: [Piece]) -> CGRect {
        guard var r = pieces.first?.box else { return .zero }
        for p in pieces.dropFirst() { r = r.union(p.box) }
        return r
    }

    /// 矩形同士の最短距離 (重なっていれば 0)。
    static func rectDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(0, max(b.minX - a.maxX, a.minX - b.maxX))
        let dy = max(0, max(b.minY - a.maxY, a.minY - b.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }
}
