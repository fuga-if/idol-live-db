import Foundation

/// Discord のロール受け取り (「データ協力」ロール) の入口。
///
/// Worker に `POST /discord/link` で 1 回限り (10 分) の Discord 認可 URL を発行してもらい、
/// それをシステムのブラウザで開くだけ。Discord でログインした後の結果 (サーバー参加・ロール付与・
/// 「あとN件」) は Worker 自身のページが出すので、アプリはコールバックを受けない。
/// Android `data/community/DiscordLinkService.kt` と対。
enum DiscordLinkService {
    private struct LinkResponse: Decodable {
        let url: String
    }

    private struct EmptyBody: Encodable {}

    /// 認可 URL を発行してもらう。ログイン中のセッションで送る (未ログインは 401)。
    static func authorizeURL() async throws -> URL {
        let response: LinkResponse = try await APIClient.shared.request(
            "POST",
            path: "/discord/link",
            body: EmptyBody(),
            authorized: true
        )
        guard let url = URL(string: response.url), url.scheme == "https" else {
            throw APIClientError.decoding(URLError(.badURL))
        }
        return url
    }

    /// 失敗をユーザー向けの短い文言にする。503 は「連携を止めている (未設定)」。
    static func errorMessage(for error: Error) -> String {
        if case let APIClientError.server(status, _) = error, status == 503 {
            return "いまは受け付けていません"
        }
        return "Discordのページを開けませんでした。時間をおいて再試行してください。"
    }
}
