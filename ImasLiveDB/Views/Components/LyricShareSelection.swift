import Foundation

/// 歌詞タブで、共有のために選んだ行の範囲 (`Lyrics.lines` の添字)。
///
/// 長押しした行が起点 (`anchor`)、選択中にタップした行が終点 (`focus`)。終点を起点の
/// 前後どちらに置いても、その間の行が全部入る (行ごとの選択。行内の位置は持たない)。
/// 歌詞タブ (`SongLyricsTab`) が書き、曲詳細 (`SongSheetContent`) が画面の下に帯を出す。
///
/// ⚠️ 持つのは添字だけ。本文は持たない (共有に乗るのは URL だけ)。
struct LyricShareSelection: Equatable {
    let songId: String
    var anchor: Int
    var focus: Int

    init(songId: String, line: Int) {
        self.songId = songId
        anchor = line
        focus = line
    }

    var range: ClosedRange<Int> { min(anchor, focus)...max(anchor, focus) }
    var isSingleLine: Bool { anchor == focus }

    func contains(_ line: Int) -> Bool { range.contains(line) }

    var url: URL {
        DeeplinkBuilder.lyricURL(songId: songId, fromLine: range.lowerBound, toLine: range.upperBound)
    }

    /// 「12行目」「12〜14行目」。番号は本文のある行で数える (コア)。
    func linesLabel(_ lyrics: Lyrics) -> String {
        shareLyricLinesLabel(lineTexts: lyrics.lines.map(\.text),
                             fromLine: UInt32(range.lowerBound), toLine: UInt32(range.upperBound))
    }

    /// 帯の下段。1 行だけのうちは広げ方を案内する (見ただけでは分からない)。
    var note: String { isSingleLine ? "ほかの行をタップで範囲を広げる" : "この部分へのリンク" }
}
