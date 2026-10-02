import Foundation

/// コールガイドの整備状況 (ある曲 / 最近の編集 / タグはあるのに未整備) の読み取りポート。
///
/// ⚠️ このポートを通るデータに**歌詞本文もコール本文もアンカー文字列も含まれない**
/// (曲 id と件数・日時・マスク済み表示名だけ)。だから `LyricsReading` と違って
/// `purge()` を持たないし、持たせなければならない種類のデータでもない。
/// もしサーバ応答にコール本文が増えたら、それは API 側の設計ミス
/// (この応答は認証不要でエッジキャッシュに載るため、断片が全端末で共有される)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol CallGuideDashboardReading: Sendable {
    /// `GET /calls/dashboard`。**認証不要** (未ログインでも読める)。
    func callGuideDashboard() async throws -> CallGuideDashboard
}

// MARK: - DTO
//
// DTO はポートと同じファイルに置く (`LyricsSearchReading` の前例に揃える)。
// 「この契約で何が返るか」を 1 ファイルで読み切れる方が、上の警告と離れないぶん安全。

/// `GET /calls/dashboard` の応答。`Decodable` のみ (こちらから送る形は存在しない)。
struct CallGuideDashboard: Decodable, Sendable, Equatable {
    /// 生成時刻 (epoch 秒)。エッジキャッシュ (`max-age=1800`) 越しなので、
    /// 手元に届いた時点で最大 30 分古い。画面はこれを「N分前時点」として見せる。
    let generatedAt: Int
    /// コールガイドがある曲 (updated_at 降順)。**サーバ上限 200 件**。
    /// 201 曲目以降は入らないので、`count` が 200 のときは打ち切りとみなすこと
    /// (これを「全部」として扱うと、曲一覧の絞り込みが黙って古い 200 曲だけになる)。
    let songsWithCalls: [CallGuideSongSummary]
    /// 最近のコール編集 (at 降順)。
    let recentEdits: [CallGuideEditEntry]
    /// 「コール曲」タグが付いていて歌詞もあるのに、コールが未整備の曲 id
    /// (票数降順)。**サーバ上限 100 件**。
    let taggedWithoutCalls: [String]
    /// 「コール曲」タグ側の内訳。タグが未作成/削除済みなら nil。
    let callTag: CallGuideTagStatus?
}

/// コールガイドがある曲 1 件ぶんのメタデータ。
struct CallGuideSongSummary: Decodable, Sendable, Equatable {
    let songId: String
    /// clap か calls が付いている行数。
    let callLines: Int
    /// コールの総数。
    let callCount: Int
    /// 最終更新 (epoch 秒)。**0 は「記録なし」**を意味する (backfill 分など)。
    /// Optional にしないのは、サーバが常にこのキーを返す契約だから
    /// (「キーが無い」と「更新時刻が分からない」を型で混ぜない)。
    let updatedAt: Int
    /// マスク済み表示名。記録が無いときはサーバが "匿名" を返すので **非 Optional**。
    let updatedBy: String
}

/// コール編集 1 件ぶんの履歴。中身 (歌詞・コール本文) は含まない。
struct CallGuideEditEntry: Decodable, Sendable, Equatable {
    let id: Int
    let songId: String
    let at: Int
    /// マスク済み表示名。記録が無いときはサーバが "匿名" を返すので **非 Optional**。
    let by: String
    let callLinesBefore: Int
    let callLinesAfter: Int
    let callCountBefore: Int
    let callCountAfter: Int
    // `summary` はサーバの機械文字列 (監査用)。表示文言は 4 つの数から組み立てるので
    // デコードもしない (表示文字列をサーバに持たせない)。
}

/// 「コール曲」タグ側の内訳。
struct CallGuideTagStatus: Decodable, Sendable, Equatable {
    let tagId: String
    let tagName: String
    /// タグが付いている曲の総数。
    let tagged: Int
    /// そのうちコールガイドがある曲。
    let withCalls: Int
    /// そのうち歌詞が未登録で「まだ書けない」曲。
    let withoutLyrics: Int

    /// いま書ける未整備曲の数。`taggedWithoutCalls` の母数と一致する
    /// (一覧は上限 100 件で打ち切られるので、件数はこちらが正)。
    var writable: Int { max(0, tagged - withCalls - withoutLyrics) }
}
