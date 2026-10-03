import ActivityKit
import Foundation

/// ロック画面・Dynamic Island に出す「いま歌っている行」のライブアクティビティ。
/// (このファイルは本体とウィジェット拡張の両方に含める)
///
/// ⚠️ 歌詞の本文を載せるのは、いま歌っている行と次の行の 2 行だけ。曲全体を載せないこと。
/// 再生を止めたら・曲が変わったら即座に終わらせ、終わった後も画面に残さない
/// (`LyricsLiveActivityController`)。App Group・ファイルには書かない (`Models/Lyrics.swift` 冒頭)。
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// いま歌っている行。イントロ・間奏では nil。
        var line: String?
        /// 次の行 (薄く添える)。
        var nextLine: String?
        /// いまの行を歌う人の担当色 (hex)。パート分けが無ければ空。
        var singerColors: [String]
        /// いまの行を歌う人の名前 (「春香・千早」)。
        var singerNames: [String]
        var isPlaying: Bool
    }

    var songTitle: String
    var artistLine: String?
    /// 差し色 (曲・ブランドの色 hex)。
    var seedHex: String?
}
