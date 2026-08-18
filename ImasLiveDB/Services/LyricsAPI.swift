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
///    `APIClient.noDiskCache` (`.ephemeral` + `urlCache = nil` +
///    `reloadIgnoringLocalAndRemoteCacheData`) を使い、ディスクにもメモリキャッシュにも
///    一切残さない。歌詞を同梱する束ね取得 (`SongDetailAPI`) も同じクライアントを共有する。
/// 2. 保持は `NSCache` のみ。ここに載るのは `Lyrics` の値であって永続化経路は無い。
///    件数ではなくバイト数で上限を持たせている (`totalCostLimit`)。歌詞は 1 曲
///    数 KB なので件数で絞る意味が薄く、絞ると読み返すたびに再取得が走る。
/// 3. メモリ逼迫時は `NSCache` が自動で evict する。加えてメモリ警告でも捨てる。
///    バックグラウンド遷移では捨てない — 制約は「ディスクに書かない」ことであって
///    RAM の保持時間ではなく、捨てると復帰のたびに再取得が走るだけだから。
///
/// 認証・401 自動リフレッシュ・エラー分類は `APIClient` に委ねる (セッションだけ差し替える)。
actor LyricsAPI {
    /// 生成と同時にメモリ警告の監視を張る。
    static let shared: LyricsAPI = {
        let api = LyricsAPI()
        api.startObservingMemoryWarnings()
        return api
    }()

    /// 歌詞を含むレスポンス専用の APIClient (ディスクキャッシュ無しセッション)。
    private let client = APIClient.noDiskCache

    /// メモリのみのキャッシュ。上限はバイト数で持つ (§2)。
    /// 16MB は全 2,685 曲を載せてもなお余る見積り (1 曲あたり数 KB)。
    /// 実際には見た曲しか載らないので、この上限に当たることはまず無い。
    private static let cacheCostLimit = 16 * 1024 * 1024
    private let cache = NSCache<NSString, LyricsBox>()

    private init() {
        cache.countLimit = 0                       // 件数では絞らない
        cache.totalCostLimit = Self.cacheCostLimit
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
            cache.setObject(LyricsBox(lyrics), forKey: key, cost: Self.cost(of: lyrics))
            return lyrics
        } catch APIClientError.notFound {
            // 歌詞が用意されていない曲。エラーではなく「無い」。
            return nil
        } catch {
            logger.warning("lyrics_fetch_failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// 歌詞本文の横断検索。返るのは 1 曲につきスニペット 1 本だけ。
    ///
    /// ⚠️ 結果はキャッシュしない。1曲ぶんの歌詞と違って同じクエリを読み返す使い方をしないし、
    /// 曲を跨いだ断片をメモリに溜めるのは「歌詞は残さない」の趣旨から遠い。
    func searchLyrics(query: String) async throws -> [LyricsSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // サーバも 400 で弾くが、1文字での無駄なリクエストを飛ばさない。
        guard trimmed.count >= Self.minSearchLength else { return [] }
        do {
            let response: LyricsSearchResponse = try await client.request(
                "GET",
                path: "/lyrics/search",
                query: ["q": trimmed],
                authorized: true
            )
            return response.hits
        } catch {
            logger.warning("lyrics_search_failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// routes/lyrics.ts の SEARCH_MIN_CHARS と同値。
    static let minSearchLength = 2

    /// キャッシュ上の重み。UTF-8 バイト数に Swift の String/配列オーバーヘッド分を
    /// ざっくり上乗せする。正確である必要はなく、暴走しない目安があればよい。
    private static func cost(of lyrics: Lyrics) -> Int {
        lyrics.lines.reduce(0) { $0 + $1.text.utf8.count + 64 }
    }

    /// メモリ上の歌詞を全て破棄する。
    func purge() {
        cache.removeAllObjects()
    }
}

extension LyricsAPI: LyricsReading {}
extension LyricsAPI: LyricsSearchReading {}

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
        func add(_ kind: LyricLineKind, _ text: String, section: String? = nil,
                 clap: LyricClap? = nil, calls: [LyricCall] = []) {
            lines.append(LyricLine(id: "ll_\(ord)", ord: ord, kind: kind,
                                   text: text, section: section, startMs: nil,
                                   clap: clap, calls: calls))
            ord += 1
        }
        /// スカラー範囲からアンカー文字列を切り出してコールを 1 件作る。
        /// `start`/`end` は Unicode スカラー単位 (本番と同じ規約)。
        func call(_ id: String, in text: String, _ range: Range<Int>, _ callText: String,
                  _ emphasis: CallEmphasis = .normal, timing: CallTiming = .after,
                  stale: Bool? = nil) -> LyricCall {
            let scalars = Array(text.unicodeScalars)
            let clamped = min(range.lowerBound, scalars.count)..<min(range.upperBound, scalars.count)
            return LyricCall(id: id, start: clamped.lowerBound, end: clamped.upperBound,
                             anchorText: String(String.UnicodeScalarView(scalars[clamped])),
                             text: callText, emphasis: emphasis, timing: timing, stale: stale)
        }
        /// 幅ゼロ (行末に返す追っかけ) のコール。サーバ側と同じく timing は常に after。
        func trailing(_ id: String, in text: String, _ callText: String,
                      _ emphasis: CallEmphasis = .normal) -> LyricCall {
            let end = text.unicodeScalars.count
            return LyricCall(id: id, start: end, end: end, anchorText: "",
                             text: callText, emphasis: emphasis, timing: .after, stale: nil)
        }

        add(.marker, "イントロ", calls: [
            LyricCall(id: "c_intro", start: 0, end: 0, anchorText: "",
                      text: "（いち・にの・さん・レッツ・ゴー！）", emphasis: .normal,
                      timing: .after, stale: nil),
        ])
        add(.blank, "")
        add(.marker, "1番", section: "A")
        for i in 1...4 {
            let text = "ダミー歌詞のサンプル行です \(i)"
            var calls: [LyricCall] = []
            var clap: LyricClap?
            switch i {
            case 1:
                clap = .backBeat
                calls = [call("c_1a", in: text, 0..<3, "(Hi!)")]
            case 2:
                // 範囲付き (追っかけ / 同時) と幅ゼロ (行末) が同じ行に混ざった状態。
                // ①②③ と » の出し分け、「同時」「行末」の札の見え方の確認用。
                clap = .fourOnFloor
                calls = [
                    call("c_2a", in: text, 0..<3, "(Fuu--!)"),
                    call("c_2b", in: text, 0..<3, "(Hi! Hi!)", .optional),
                    call("c_2c", in: text, 7..<13, "（サンプル行です）", .normal, timing: .over),
                    trailing("c_2d", in: text, "(Hi!) × 4"),
                ]
            case 3:
                clap = .ppph
                calls = [call("c_3a", in: text, 3..<5, "(Oi!)", .performerRequest)]
            default:
                // 追っかけだけの行 (実際の多数派)。札は出ず » だけで示される。
                clap = .noCall
                calls = [trailing("c_4t", in: text, "(Fuu--!)")]
            }
            add(.lyric, text, section: "A", clap: clap, calls: calls)
        }
        add(.blank, "")
        add(.marker, "サビ", section: "chorus")
        for i in 1...3 {
            let text = "ここはサビのダミー行 \(i)、折り返しの見え方を確認するために少しだけ長めの文字列にしてあります"
            var calls: [LyricCall] = []
            if i == 1 {
                calls = [
                    call("c_4a", in: text, 0..<6, "(Fuwa × 4)"),
                    call("c_4b", in: text, 24..<30, "(Woooo,Yeah!!)", .performerRequest),
                ]
            }
            if i == 2 {
                // 「歌詞が編集されてアンカーがズレた」印の確認用。
                calls = [call("c_5a", in: text, 0..<4, "(Hey!!)", .optional, stale: true)]
            }
            if i == 3 {
                calls = [trailing("c_6t", in: text, "（せーの！）")]
            }
            add(.lyric, text, section: "chorus", clap: i == 3 ? .backBeat : nil, calls: calls)
        }
        add(.blank, "")
        add(.marker, "アウトロ")
        return Lyrics(songId: songId, source: "ダミーデータ (表示確認用)",
                      updatedAt: 1_754_300_000, lines: lines, status: "draft")
    }

    func purge() async {}
}
#endif
