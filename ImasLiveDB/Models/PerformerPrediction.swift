import Foundation

// MARK: - PerformerPredictionDTO (API レスポンス)

/// 「誰が歌う」予想 API が返す「コミュニティデータ」のみ。
///
/// アイドルメタデータ (name/color 等) は **API からは取得しない**。
/// それらの正は CloudKit / iOS local カタログであり、iOS local から解決する。
///
/// APIClient の decoder は convertFromSnakeCase を効かせているため、
/// CodingKeys は書かず property 名そのままに任せる (snake_case 手書きは keyNotFound になる)。
/// API は show_id / song_id / first_voted_by / first_voted_at も返すが、
/// iOS 側では使わないため Decodable で宣言しない (未使用キーは自動的に無視される)。
struct PerformerPredictionDTO: Codable, Sendable {
    let idolId: String
    let voteCount: Int
    let hasUserVoted: Bool
}

// MARK: - PerformerPrediction (表示用モデル)

/// 画面表示用の予想。API のコミュニティデータ (`PerformerPredictionDTO`) に
/// iOS local カタログのアイドルメタデータを結合して組み立てる。
struct PerformerPrediction: Identifiable, Sendable {
    var id: String { idolId }
    let idolId: String
    let voteCount: Int
    let hasUserVoted: Bool
    let idolName: String
    let idolColor: String?

    /// API の予想データと local アイドルを結合。local にアイドルが無い場合でも idolId にフォールバックして表示する。
    init(dto: PerformerPredictionDTO, idol: Idol?) {
        idolId = dto.idolId
        voteCount = dto.voteCount
        hasUserVoted = dto.hasUserVoted
        idolName = idol?.name ?? dto.idolId
        idolColor = idol?.color
    }
}

// MARK: - PerformerVoteResult

/// POST /shows/:showId/songs/:songId/performers のレスポンス。
/// 201 (新規) / 200 (冪等) 共通。iOS 側では票数更新後にキャッシュ無効化して再 fetch するため
/// already_voted / not_voted フラグは使わない (未宣言キーは自動無視される)。
struct PerformerVoteResult: Codable, Sendable {
    let idolId: String
    let voteCount: Int
}

// MARK: - PerformerUnvoteResult

/// DELETE /shows/:showId/songs/:songId/performers/:idolId のレスポンス。
struct PerformerUnvoteResult: Codable, Sendable {
    let idolId: String
    let voteCount: Int
}
