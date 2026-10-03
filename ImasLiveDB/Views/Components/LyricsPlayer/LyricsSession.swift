import Foundation
import Observation

/// いま鳴っている曲の歌詞を、再生中バー (ミニプレイヤー) から引けるように預かる所。
///
/// 歌詞タブがその曲のフル再生中に歌詞を読んだとき、ここへ 1 曲分だけ置く。
/// バーはこれを見て今の行を出し、タップで歌詞プレイヤーを開く。
///
/// ⚠️ 歌詞の本文を持つので、置き場は**プロセスのメモリだけ** (`Models/Lyrics.swift` 冒頭の許諾条件)。
/// UserDefaults・ファイル・App Group・ウィジェットへ書き出さないこと。
/// 鳴っている曲が変わったら (止めたら) すぐ手放す。
@MainActor @Observable
final class LyricsSession {
    static let shared = LyricsSession()

    struct Entry {
        let song: Song
        let seed: String?
        let artistLine: String?
        let artworkURL: URL?
        let lyrics: Lyrics
        let cast: LyricPartCast
    }

    private(set) var entry: Entry?

    private init() {}

    /// その曲がフル再生で鳴っているときだけ預かる (別の曲の歌詞を開いただけでは差し替えない)。
    func register(_ entry: Entry) {
        let player = MusicKitService.shared
        guard player.isFullPlayback, player.nowPlayingSongId == entry.song.id else { return }
        self.entry = entry
    }

    /// 鳴っている曲の歌詞。鳴っていなければ nil。
    func entry(forSongId songId: String?) -> Entry? {
        guard let songId, entry?.song.id == songId else { return nil }
        return entry
    }

    /// 鳴っている曲が変わったら手放す。
    func release(unlessSongId songId: String?) {
        if entry?.song.id != songId { entry = nil }
    }
}
