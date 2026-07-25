import Foundation

/// シェア用 deeplink URL の生成 (id → URL)。
/// Universal Links (https) を共有 URL の正とし、ShareLink やバイラルシェア画像など
/// 複数の機能から共用する独立した型。
enum DeeplinkBuilder {
    /// Universal Links を受ける imas-live-api worker のベース URL。
    static let universalLinkBase = URL(string: "https://imas-live-api.tokata3011.workers.dev")!

    /// 開発・テスト用 custom URL scheme (imaslivedb://)。
    static let customScheme = "imaslivedb"

    /// ID を URL パスに埋める前のエスケープ。
    ///
    /// `@` は RFC 3986 上はパスに置けるので `appending(components:)` は素通しするが、
    /// **SNS やメッセージアプリのリンク検出が `@` をメールアドレスの境界と誤認して
    /// そこで URL を切る**。`sh_the_idolm@ster_...` が `sh_the_idolm` で切られ、
    /// 共有されたリンクを踏むと 404 になっていた (TEXT PK に `@` を含む公演が該当)。
    /// `%40` にしておけば切られず、受け側は `pathComponents` が percent-decode するので
    /// そのまま元の ID に戻る。
    private static func escaped(_ id: String) -> String {
        id.replacingOccurrences(of: "@", with: "%40")
    }

    /// イベント詳細への共有 URL (https://…/app/events/{eventId})。
    static func eventURL(id: String) -> URL {
        URL(string: universalLinkBase.absoluteString + "/app/events/" + escaped(id))
            ?? universalLinkBase
    }

    /// 公演セトリへの共有 URL (https://…/app/shows/{showId})。
    static func showURL(id: String) -> URL {
        URL(string: universalLinkBase.absoluteString + "/app/shows/" + escaped(id))
            ?? universalLinkBase
    }

    /// みんなの投票のお題への共有 URL (https://…/app/polls/{pollId})。
    static func pollURL(id: String) -> URL {
        URL(string: universalLinkBase.absoluteString + "/app/polls/" + escaped(id))
            ?? universalLinkBase
    }

    /// SNS シェア文。イベント名/公演名 + URL のシンプルな形式。
    static func shareText(name: String, url: URL) -> String {
        "\(name)\n\(url.absoluteString)"
    }
}
