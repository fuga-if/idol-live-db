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
    /// `appending(components:)` が ID を URL エンコードする (TEXT PK は ASCII だが念のため)。
    static func eventURL(id: String) -> URL {
        universalLinkBase.appending(components: "app", "events", id)
    }

    /// 公演セトリへの共有 URL (https://…/app/shows/{showId})。
    static func showURL(id: String) -> URL {
        universalLinkBase.appending(components: "app", "shows", id)
    }

    /// SNS シェア文。イベント名/公演名 + URL のシンプルな形式。
    static func shareText(name: String, url: URL) -> String {
        "\(name)\n\(url.absoluteString)"
    }
}
