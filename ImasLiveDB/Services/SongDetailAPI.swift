import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "song_detail_api")

/// 曲詳細の束ね取得クライアント (`GET /songs/{song_id}/detail`)。
///
/// 曲詳細を開くたびにタグ / 類似曲 / ペンライトで 3 リクエスト飛んでいたのを 1 本にまとめる。
/// Worker 無料枠 (10万リクエスト/日) を曲詳細のオープンだけで使い切らないための束ね。
/// 歌詞も同梱されるので、歌詞タブを常時読み込みにしてもリクエスト数は増えない。
///
/// ⚠️ **`APIClient.shared` を使わないこと。** レスポンスに歌詞が含まれるため、
/// `URLSession.shared` (共有ディスク `URLCache`) で叩くと歌詞本文が Caches ディレクトリに
/// 書かれてしまう。JASRAC 許諾の条件 (一括ダウンロード不可) に反するので、必ず
/// `APIClient.noDiskCache` の ephemeral セッションを通す。
actor SongDetailAPI {
    static let shared = SongDetailAPI()

    /// 歌詞を含むレスポンス専用の APIClient (ディスクキャッシュ無しセッション)。
    private let client = APIClient.noDiskCache

    /// 旧経路で歌詞だけを取るための読み取りポート (メモリのみ保持の実装)。
    private let lyricsReading: any LyricsReading

    init(lyricsReading: any LyricsReading = LyricsAPI.shared) {
        self.lyricsReading = lyricsReading
    }

    /// 束ねエンドポイントが未配信の Worker を掴んでいるか (404 を 1 度でも受けたら true)。
    ///
    /// 新しいアプリと未更新の Worker が同時に存在しうる (審査期間・段階配信) ため、
    /// 束ねが無い環境では旧個別エンドポイントに落とす。プロセス内で記憶するので、
    /// 余計な 404 を払うのはアプリ起動後の最初の 1 回だけ。
    private var bundleUnsupported = false

    /// 曲詳細 1 画面ぶんのサーバ側データ。
    ///
    /// song_id は非 ASCII (`cg_お願いシンデレラ` 等) を含むので percent-encode が要るが、
    /// `APIClient` 内の `URL.appendingPathComponent` が path セグメントを 1 回エンコードする。
    /// ここで手動 `addingPercentEncoding` を被せると二重エンコードになり、サーバ側の
    /// `decodeURIComponent` 1 回では戻りきらず別キー扱いになる (LyricsAPI と同じ規約)。
    ///
    /// 認証は任意。未認証でも 200 が返り、歌詞と「自分の投票/自分のタグ」だけが空になる。
    func songDetail(songId: String) async throws -> SongDetailBundle {
        if !bundleUnsupported {
            do {
                return try await client.request(
                    "GET",
                    path: "/songs/\(songId)/detail",
                    authorized: true
                )
            } catch APIClientError.notFound {
                // 束ね未配信の Worker。以降はこのプロセスでは旧経路に固定する。
                bundleUnsupported = true
                logger.warning("song_detail_bundle_unavailable: falling back to legacy endpoints")
            }
        }
        return await legacyBundle(songId: songId)
    }

    /// 旧個別エンドポイントから束ねと同じ形を組み立てる (束ね未配信 Worker 用の暫定経路)。
    ///
    /// 直列だった旧実装と違い 4 本を並列で投げる。リクエスト数は束ねより多いが、
    /// これは Worker が更新されるまでの一時的な状態で、更新後は二度と通らない。
    /// 個々の失敗は nil に倒す (束ねの契約と同じく「取れなかった = 今は無い」)。
    private func legacyBundle(songId: String) async -> SongDetailBundle {
        async let tags = try? CommunityAPI.shared.songTags(songId: songId)
        async let similar = try? CommunityAPI.shared.similarSongsByTags(songId: songId)
        async let penlight = try? CommunityAPI.shared.penlightVotes(songId: songId)
        // 歌詞だけは専用クライアント経由 (LyricsAPI) で取る。ここでも URLSession.shared は通さない。
        async let lyrics = try? lyricsReading.lyrics(songId: songId)
        return SongDetailBundle(
            songId: songId,
            tags: await tags,
            similar: await similar,
            penlight: await penlight,
            lyrics: await lyrics ?? nil
        )
    }
}

extension SongDetailAPI: SongDetailReading {}

#if DEBUG
/// サーバ側の束ね (と歌詞) が未完成でも見た目を確認するためのフェイク。
/// 歌詞だけダミー文言に差し替え、他はそのまま実サーバの結果を使う (取れなければ空)。
/// 著作物は一切使わない。
///
/// 起動時に環境変数 `FAKE_LYRICS=1` を渡すと `AppContainer` がこちらを注入する:
/// `SIMCTL_CHILD_FAKE_LYRICS=1 xcrun simctl launch <udid> com.fugaif.ImasLiveDB`
struct FakeLyricsSongDetailReading: SongDetailReading {
    var base: any SongDetailReading = SongDetailAPI.shared
    var fakeLyrics: any LyricsReading = FakeLyricsReading()

    func songDetail(songId: String) async throws -> SongDetailBundle {
        let real = try? await base.songDetail(songId: songId)
        return SongDetailBundle(
            songId: songId,
            tags: real?.tags,
            similar: real?.similar,
            penlight: real?.penlight,
            lyrics: try await fakeLyrics.lyrics(songId: songId)
        )
    }
}
#endif
