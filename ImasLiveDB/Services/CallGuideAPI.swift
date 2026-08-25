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
}

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
#endif
