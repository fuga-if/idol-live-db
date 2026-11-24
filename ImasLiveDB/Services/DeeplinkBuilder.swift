import Foundation

/// シェア用 deeplink URL の生成 (id → URL)。
/// Universal Links (https) を共有 URL の正とし、ShareLink やバイラルシェア画像など
/// 複数の機能から共用する独立した型。
enum DeeplinkBuilder {
    /// Universal Links を受ける imas-live-api worker のベース URL。
    static let universalLinkBase = URL(string: "https://imas-live-api.tokata3011.workers.dev")!

    /// 開発・テスト用 custom URL scheme (imaslivedb://)。
    static let customScheme = "imaslivedb"

    /// イベント詳細への共有 URL (https://…/app/events/{eventId})。
    ///
    /// 組み立て (ID の `@` を `%40` にする等) はコアが持つ。`@` を生で残すと、SNS の
    /// リンク検出がメールアドレスの境界と誤認して URL をそこで切る。
    static func eventURL(id: String) -> URL { url(shareEventUrl(id: id)) }

    /// 公演セトリへの共有 URL (https://…/app/shows/{showId})。
    static func showURL(id: String) -> URL { url(shareShowUrl(id: id)) }

    /// みんなの投票のお題への共有 URL (公開サイトのお題一覧の、そのお題の節)。
    static func pollURL(id: String) -> URL { url(sharePollUrl(id: id)) }

    /// 歌詞の一部への共有 URL (公開サイトの曲ページ + `#lyric-12` / `#lyric-12-14`)。
    /// 行は `Lyrics.lines` の 0 始まりの添字 (Web の歌詞 API の `lines` と同じ並び)。行ごとなので位置は渡さない。
    /// `/songs/` は Universal Links の対象外なので、受け取った人のブラウザで開く。
    static func lyricURL(songId: String, fromLine: Int, toLine: Int) -> URL {
        url(shareLyricUrl(songId: songId,
                          from: LyricShareEnd(line: UInt32(max(0, fromLine)), offset: nil),
                          to: LyricShareEnd(line: UInt32(max(0, toLine)), offset: nil)))
    }

    private static func url(_ string: String) -> URL {
        URL(string: string) ?? universalLinkBase
    }
}
