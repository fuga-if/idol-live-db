import Foundation

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

    /// 曲詳細 1 画面ぶんのサーバ側データ。
    ///
    /// song_id は非 ASCII (`cg_お願いシンデレラ` 等) を含むので percent-encode が要るが、
    /// `APIClient` 内の `URL.appendingPathComponent` が path セグメントを 1 回エンコードする。
    /// ここで手動 `addingPercentEncoding` を被せると二重エンコードになり、サーバ側の
    /// `decodeURIComponent` 1 回では戻りきらず別キー扱いになる (LyricsAPI と同じ規約)。
    ///
    /// 認証は任意。未認証でも 200 が返り、歌詞と「自分の投票/自分のタグ」だけが空になる。
    func songDetail(songId: String) async throws -> SongDetailBundle {
        try await client.request("GET", path: "/songs/\(songId)/detail", authorized: true)
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
