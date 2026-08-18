import Foundation

/// 歌詞本文の横断検索ポート (driven port)。
///
/// `LyricsReading` (1曲ぶんの取得) と分けてあるのは、こちらが**曲を跨ぐ**唯一の歌詞経路で、
/// JASRAC 許諾の「一括ダウンロードできない形式」に一番近づく機能だから。
/// 契約として次を守る (サーバ側 routes/lyrics.ts と対になっている):
///
/// - 返るのは 1 曲につきスニペット 1 本だけ。行の集合も全文も返らない。
/// - スニペットは一致箇所の前後を切った窓であって、行全体ですらない。
/// - 曲名・アーティストは含まれない。呼び出し側が `songId` から同梱 SQLite で解決する
///   (サーバはマスタを持っていない)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol LyricsSearchReading: Sendable {
    /// 歌詞本文にクエリを含む曲を探す。
    ///
    /// 2 文字未満は検索しない (サーバが 400 を返す前にクライアントで弾く)。
    /// 未認証 (401) は `APIClientError.notAuthorized` を投げる。
    func searchLyrics(query: String) async throws -> [LyricsSearchHit]
}

/// 歌詞検索の 1 件。
///
/// `matchStart` / `matchLength` は **`snippet` 内の Unicode スカラー単位**のオフセット。
/// コールのアンカー (`LyricCall.start` / `.end`) と同じ規約に揃えてある。
/// UTF-16 コードユニットで数えると絵文字や結合文字を含む行でズレる。
struct LyricsSearchHit: Decodable, Identifiable, Sendable, Equatable {
    let songId: String
    /// 一致箇所の前後だけを切り出した窓。前後が続く場合は "…" が付く。
    let snippet: String
    let matchStart: Int
    let matchLength: Int

    var id: String { songId }

    /// `snippet` 内の一致範囲。サーバが壊れた値を返しても落ちないよう丸める。
    var matchRange: Range<Int> {
        let count = snippet.unicodeScalars.count
        let start = min(max(0, matchStart), count)
        let end = min(start + max(0, matchLength), count)
        return start ..< end
    }
}

/// `GET /lyrics/search` の応答。
struct LyricsSearchResponse: Decodable, Sendable {
    let query: String
    let hits: [LyricsSearchHit]
    /// サーバ側の上限。ヒットがこれに達していたら「まだあるかも」を画面に出すために使う。
    let limit: Int
}
