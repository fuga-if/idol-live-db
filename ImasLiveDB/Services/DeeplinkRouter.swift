import Foundation

/// アプリが受け取る deeplink の種別。
/// - Universal Links: `https://imas-live-api.tokata3011.workers.dev/app/events/{id}` など
/// - Custom scheme:   `imaslivedb://events/{id}` など (開発・テストで確実に動く経路)
enum Deeplink: Equatable {
    case event(id: String)
    case show(id: String)
}

/// deeplink URL の解析と、ローカル DB を引いた遷移先 (DetailDestination) への解決。
enum DeeplinkRouter {
    /// URL を `Deeplink` に解析する。対象外の URL は nil (呼び出し側で安全に無視)。
    /// `URL.pathComponents` / `host()` は percent-decode 済みなので
    /// `ml_kasuga_mirai` 形式の TEXT PK がそのまま得られる。
    static func parse(_ url: URL) -> Deeplink? {
        if url.scheme == DeeplinkBuilder.customScheme {
            // imaslivedb://events/{id} → host="events", pathComponents=["/", "{id}"]
            guard let host = url.host() else { return nil }
            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count == 1, let id = components.first, !id.isEmpty else { return nil }
            return deeplink(kind: host, id: id)
        }

        // Universal Link: https://{worker}/app/(events|shows)/{id}
        guard url.scheme == "https",
              url.host()?.lowercased() == DeeplinkBuilder.universalLinkBase.host()
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3, components[0] == "app",
              let id = components.last, !id.isEmpty
        else { return nil }
        return deeplink(kind: components[1], id: id)
    }

    private static func deeplink(kind: String, id: String) -> Deeplink? {
        switch kind {
        case "events": return .event(id: id)
        case "shows": return .show(id: id)
        default: return nil
        }
    }

    /// `Deeplink` をローカル DB で解決して画面遷移先を返す。
    /// 未知 ID (未同期・削除済み) は nil、DB エラーは throw — 呼び出し側で
    /// 「見つからない」と「読み込み失敗」を出し分ける。
    static func destination(for link: Deeplink, database: AppDatabase) throws -> DetailDestination? {
        switch link {
        case .event(let id):
            return try database.fetchEvent(id: id).map(DetailDestination.event)
        case .show(let id):
            return try database.fetchShow(id: id).map(DetailDestination.show)
        }
    }
}
