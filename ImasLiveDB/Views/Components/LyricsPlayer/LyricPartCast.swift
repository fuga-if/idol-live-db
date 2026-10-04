import SwiftUI
import UIKit

/// パート分けを描くための歌唱者の引き表。歌詞タブ・歌詞プレイヤー・再生中バーで同じ引き方にする。
///
/// 行が持つのはアイドルの id だけ (`LyricLine.singers`)。色と名前はここで原唱者から引く。
/// 原唱者にいない id は出さない (曲の編成に無い人の帯を作らない)。
struct LyricPartCast {
    /// 原唱者 (並びが帯の縞の順)。
    let artists: [Idol]
    private let byId: [String: Idol]

    init(artists: [Idol]) {
        self.artists = artists
        self.byId = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static let empty = LyricPartCast(artists: [])

    func colors(_ ids: [String]) -> [String] { ids.compactMap { byId[$0]?.color } }
    func names(_ ids: [String]) -> [String] { ids.compactMap { byId[$0]?.shortName } }
    /// 行の字の下に引く、歌う人の色の線 (ひと続きごと)。`mapRange` で表示する本文の中の位置に置き直す
    /// (歌詞プレイヤーは被せの括弧を外した本文を出すので)。
    func marks(_ line: LyricLine, scheme: ColorScheme,
               mapRange: ((Int, Int) -> (Int, Int)?)? = nil) -> [ImasRubyText.PartMark] {
        guard !line.allSingers.isEmpty else { return [] }
        return line.partSegments.compactMap { segment in
            let colors = colors(segment.singers).map { UIColor(ImasTheme.derive(seed: $0, scheme: scheme).accent) }
            guard !colors.isEmpty else { return nil }
            let range = mapRange.map { $0(Int(segment.start), Int(segment.end)) } ?? (Int(segment.start), Int(segment.end))
            return range.map { ImasRubyText.PartMark(start: $0.0, end: $0.1, colors: colors) }
        }
    }

    /// 行のひと続きごとの名前 (行の途中で歌う人が変わるところで分ける)。
    func groups(_ line: LyricLine) -> [[String]] {
        line.partBreaks.isEmpty ? [names(line.singers)] : line.partSegments.map { names($0.singers) }
    }

    /// 原唱者の並びに揃える (付け外しの後に呼ぶ)。
    func ordered(_ ids: [String]) -> [String] {
        let order = artists.map(\.id)
        return ids.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }
}
