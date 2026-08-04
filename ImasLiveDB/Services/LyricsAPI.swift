import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "lyrics_api")

/// `NSCache` は class 型しか値に取れないので、値型 `Lyrics` を包む箱。
/// この箱もアーカイブ経路を持たない (`NSCoding` 非準拠) ので、ディスクには出ない。
private final class LyricsBox {
    let value: Lyrics
    init(_ value: Lyrics) { self.value = value }
}

/// 歌詞取得クライアント。
///
/// ⚠️ JASRAC 許諾の条件 (ユーザが一括ダウンロードできない形式での配信) を満たすため、
/// 歌詞は**プロセス内メモリにしか置かない**。実装上の担保:
///
/// 1. `URLSession.shared` を使わない。共有セッションはディスク上の `URLCache` を持つので、
///    レスポンス本文 (= 歌詞) が Caches ディレクトリに書かれてしまう。
///    ここでは `.ephemeral` + `urlCache = nil` + `reloadIgnoringLocalAndRemoteCacheData` の
///    専用セッションを使い、ディスクにもメモリキャッシュにも一切残さない。
/// 2. 保持は `NSCache` (countLimit 8) のみ。ここに載るのは `Lyrics` の値であって永続化経路は無い。
/// 3. バックグラウンド遷移 (`ImasLiveDBApp` の scenePhase == .background) と
///    メモリ警告で `purge()` して即座に捨てる。
///
/// 認証・401 自動リフレッシュ・エラー分類は `APIClient` に委ねる (セッションだけ差し替える)。
actor LyricsAPI {
    /// 生成と同時にメモリ警告の監視を張る。
    static let shared: LyricsAPI = {
        let api = LyricsAPI()
        api.startObservingMemoryWarnings()
        return api
    }()

    /// 歌詞専用の APIClient。ディスクキャッシュを持たないセッションで組み立てる。
    private let client: APIClient

    /// メモリのみの LRU。歌詞は 1 曲ぶんが大きくないので 8 曲で十分。
    private let cache = NSCache<NSString, LyricsBox>()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        // ephemeral は既にディスクを使わないが、意図を型で残すため明示的に潰す。
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        self.client = APIClient(session: URLSession(configuration: config))
        cache.countLimit = 8
    }

    /// メモリ警告で歌詞を捨てる。`NSCache` 自体もメモリ逼迫で evict するが、
    /// 「歌詞は残さない」のは要件なので明示的にも捨てる。
    nonisolated func startObservingMemoryWarnings() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.purge() }
        }
    }

    /// 指定曲の歌詞。未登録 (404) は nil。
    ///
    /// song_id は非 ASCII (`cg_お願いシンデレラ` 等) を含むので percent-encode が要るが、
    /// `APIClient` 内の `URL.appendingPathComponent` が path セグメントを 1 回エンコードする。
    /// ここで手動 `addingPercentEncoding` を被せると二重エンコードになり、サーバ側の
    /// `decodeURIComponent` 1 回では戻りきらず別キー扱いになる (CommunityAPI と同じ規約)。
    func lyrics(songId: String) async throws -> Lyrics? {
        let key = songId as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        do {
            let lyrics: Lyrics = try await client.request(
                "GET",
                path: "/songs/\(songId)/lyrics",
                authorized: true
            )
            cache.setObject(LyricsBox(lyrics), forKey: key)
            return lyrics
        } catch APIClientError.notFound {
            // 歌詞が用意されていない曲。エラーではなく「無い」。
            return nil
        } catch {
            logger.warning("lyrics_fetch_failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// メモリ上の歌詞を全て破棄する。
    func purge() {
        cache.removeAllObjects()
    }
}

extension LyricsAPI: LyricsReading {}

#if DEBUG
/// サーバ未完成時に見た目を確認するためのフェイク実装。
/// 著作物は一切使わず、ダミー文言のみを返す。
///
/// 起動時に環境変数 `FAKE_LYRICS=1` を渡すと `AppContainer` がこちらを注入する:
/// `SIMCTL_CHILD_FAKE_LYRICS=1 xcrun simctl launch <udid> com.fugaif.ImasLiveDB`
struct FakeLyricsReading: LyricsReading {
    func lyrics(songId: String) async throws -> Lyrics? {
        // 「歌詞なし」表示も確認できるよう、id に "nolyrics" を含む曲は 404 相当にする。
        guard !songId.contains("nolyrics") else { return nil }
        var lines: [LyricLine] = []
        var ord = 0
        func add(_ kind: LyricLineKind, _ text: String, section: String? = nil) {
            lines.append(LyricLine(id: "ll_\(ord)", ord: ord, kind: kind,
                                   text: text, section: section, startMs: nil))
            ord += 1
        }
        add(.marker, "イントロ")
        add(.blank, "")
        add(.marker, "1番", section: "A")
        for i in 1...4 { add(.lyric, "ダミー歌詞のサンプル行です \(i)", section: "A") }
        add(.blank, "")
        add(.marker, "サビ", section: "chorus")
        for i in 1...3 { add(.lyric, "ここはサビのダミー行 \(i)、折り返しの見え方を確認するために少しだけ長めの文字列にしてあります", section: "chorus") }
        add(.blank, "")
        add(.marker, "アウトロ")
        return Lyrics(songId: songId, source: "ダミーデータ (表示確認用)",
                      updatedAt: 1_754_300_000, lines: lines)
    }

    func purge() async {}
}
#endif
