import Foundation

// =============================================================================
// 曲詳細の束ね取得レスポンス (GET /songs/{song_id}/detail)
//
// 曲詳細を開くたびにタグ / 類似曲 / ペンライトで 3 リクエスト飛んでいたのを 1 本にまとめた
// もの。Worker 無料枠 (10万リクエスト/日) を曲詳細のオープンだけで食い潰さないための束ね。
// 歌詞も同梱されるので、歌詞タブを常時読み込みにしてもリクエストは増えない。
//
// ⚠️ `lyrics` を含む = このレスポンス全体が歌詞と同じ扱いになる。
//    `Encodable` / GRDB プロトコルに準拠させないこと (Models/Lyrics.swift の注記参照)。
//    取得も `URLSession.shared` (共有ディスク URLCache) ではなく
//    `APIClient.noDiskCache` の専用セッションを通すこと (Services/SongDetailAPI.swift)。
//
// ⚠️ 入れ子は既存の型 (`SongTagListResponse` / `SimilarSongsResponse` /
//    `PenlightVoteResult` / `Lyrics`) をそのまま使う。ここに専用 DTO を作らない。
// =============================================================================

/// 曲詳細 1 画面ぶんのサーバ側データ。
///
/// 各要素は「取れなかった / 今は無い」を等しく `nil` で表す:
/// - 歌詞なし・未公開・未認証 → `lyrics == nil`
/// - サーバ側で個別取得が失敗した部分 → その要素だけ `nil`
///
/// つまり `nil` はエラーではない。呼び出し側は空状態を出せばよい。
struct SongDetailBundle: Decodable, Sendable {
    let songId: String
    let tags: SongTagListResponse?
    let similar: SimilarSongsResponse?
    let penlight: PenlightVoteResult?
    let lyrics: Lyrics?
}

extension SongDetailBundle {
    private enum CodingKeys: String, CodingKey {
        case songId, tags, similar, penlight, lyrics
    }

    /// 部分ごとに寛容にデコードする。
    ///
    /// 1 要素が想定外の形でも他を道連れにしない。契約上「取れなかった部分は null」なので、
    /// 形が合わなかった部分も同じく「今は無い」に倒すのが一貫している
    /// (未配信 Worker と新しいアプリが同時に存在しうる、という既存の前提とも揃う)。
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func part<T: Decodable>(_ key: CodingKeys) -> T? {
            guard let value = try? c.decodeIfPresent(T.self, forKey: key) else { return nil }
            return value
        }
        let id: String = part(.songId) ?? ""
        self.init(
            songId: id,
            tags: part(.tags),
            similar: part(.similar),
            penlight: part(.penlight),
            // 入れ子の歌詞は songId を持たない形もありうるので、束ねの songId で補う。
            lyrics: (part(.lyrics) as Lyrics?)?.resolvingSongId(id)
        )
    }
}
