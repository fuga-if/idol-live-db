import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "call_guide_api")

/// コールガイド保存クライアント (`PUT /songs/{song_id}/calls`)。
///
/// ⚠️ **`APIClient.shared` を使わないこと。** リクエスト/レスポンスに歌詞の断片
/// (`anchor_text`) が乗るうえ、`URLSession.shared` は**ディスク上の `URLCache`** を持つ。
/// 歌詞に触れる経路は `LyricsAPI` / `SongDetailAPI` と同じく必ず
/// `APIClient.noDiskCache` (ephemeral) を通す。
///
/// song_id は非 ASCII (`cg_お願いシンデレラ` 等) を含むが、percent-encode は
/// `APIClient` 内の `URL.appendingPathComponent` が 1 回だけ行う。ここで手動で
/// `addingPercentEncoding` を被せると二重エンコードになる (LyricsAPI と同じ規約)。
actor CallGuideAPI: CallGuideWriting {
    static let shared = CallGuideAPI()

    private let client = APIClient.noDiskCache

    private init() {}

    func updateCallGuide(songId: String, lines: [CallGuidePayload.Line]) async throws {
        do {
            try await client.requestVoid(
                "PUT",
                path: "/songs/\(songId)/calls",
                body: CallGuidePayload(lines: lines),
                authorized: true
            )
        } catch {
            logger.warning("call_guide_put_failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// コールガイドの整備状況 (`GET /calls/dashboard`)。
    ///
    /// **`authorized: false` で投げること。** `Authorization` を付けると Worker 側の
    /// `edgeCacheEligible` が false になり、全端末で共有できるはずのエッジキャッシュに
    /// 載らなくなる (index.ts)。この応答に個人データは無いので、認証を付ける理由も無い。
    func callGuideDashboard() async throws -> CallGuideDashboard {
        try await client.request("GET", path: "/calls/dashboard", authorized: false)
    }
}

/// 読み口も同じアクタに載せる。歌詞ドメインの通信経路を 1 本に保つため
/// (このエンドポイント自体は本文を返さないが、経路を分けると次の実装者が
/// `APIClient.shared` を使い始める入口になる)。
extension CallGuideAPI: CallGuideDashboardReading {}

#if DEBUG
/// サーバ未実装でも編集の動線を確認するためのフェイク。保存した内容はどこにも残さない。
///
/// 起動時に環境変数 `FAKE_LYRICS=1` を渡すと `AppContainer` がこちらを注入する。
struct FakeCallGuideWriting: CallGuideWriting {
    func updateCallGuide(songId: String, lines: [CallGuidePayload.Line]) async throws {
        try? await Task.sleep(for: .milliseconds(300))
        logger.debug("fake_call_guide_put song=\(songId, privacy: .public) lines=\(lines.count)")
    }
}

/// Worker 未デプロイでもダッシュボードの見た目を確認するためのフェイク。
///
/// 起動時に環境変数 `FAKE_LYRICS=1` を渡すと `AppContainer` がこちらを注入する。
/// 手元の曲マスタから先頭何件かを借りて 3 セクションを埋めるだけで、通信もしないし
/// どこにも残さない。
struct FakeCallGuideDashboardReading: CallGuideDashboardReading {
    var withCallsCount = 5
    var recentEditCount = 6
    var wantedCount = 12

    func callGuideDashboard() async throws -> CallGuideDashboard {
        try? await Task.sleep(for: .milliseconds(200))
        // ⚠️ `AppContainer.shared` はここで解決すること。プロパティの既定値にすると
        // `AppContainer.shared` の初期化中に自分自身を読みに行って落ちる。
        let songs = try await AppContainer.shared.songReading.songs(
            filter: SongSearchFilter(), sortOrder: .titleKana, ascending: nil)
        let ids = songs.map(\.song.id)
        let now = Int(Date().timeIntervalSince1970)
        let names = ["f***", "匿名", "p***", "み***"]

        let withCalls = ids.prefix(withCallsCount).enumerated().map { i, id in
            CallGuideSongSummary(
                songId: id,
                callLines: 8 + i * 3,
                callCount: 20 + i * 7,
                updatedAt: now - (i + 1) * 3600 * 9,
                updatedBy: names[i % names.count])
        }
        // 「付けた / 更新 / 削除」の 3 パターンが 1 画面で見えるように前後の数を散らす。
        let recent = ids.prefix(recentEditCount).enumerated().map { i, id -> CallGuideEditEntry in
            let before = i % 3 == 0 ? 0 : 12 + i
            let after = i % 3 == 2 ? 0 : 20 + i * 4
            return CallGuideEditEntry(
                id: 1000 + i, songId: id, at: now - (i + 1) * 1800,
                by: names[(i + 1) % names.count],
                callLinesBefore: before == 0 ? 0 : 5, callLinesAfter: after == 0 ? 0 : 9,
                callCountBefore: before, callCountAfter: after)
        }
        let wanted = Array(ids.dropFirst(withCallsCount).prefix(wantedCount))
        return CallGuideDashboard(
            generatedAt: now,
            songsWithCalls: Array(withCalls),
            recentEdits: Array(recent),
            taggedWithoutCalls: wanted,
            callTag: CallGuideTagStatus(
                tagId: "tag_44Kz44O844Or5puy", tagName: "コール曲",
                tagged: 291, withCalls: withCalls.count, withoutLyrics: 46))
    }
}
#endif
