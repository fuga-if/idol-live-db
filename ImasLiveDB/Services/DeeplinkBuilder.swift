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

    /// みんなの投票のお題への共有 URL (https://…/app/polls/{pollId})。
    static func pollURL(id: String) -> URL { url(sharePollUrl(id: id)) }

    private static func url(_ string: String) -> URL {
        URL(string: string) ?? universalLinkBase
    }
}
