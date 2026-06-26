import Foundation

// MARK: - PredictionDTO (API レスポンス)

/// 予想 API が返す「コミュニティデータ」のみ。
///
/// 曲メタデータ (title/artwork/preview/appleMusicId 等) は **API からは取得しない**。
/// それらの正は CloudKit / iOS local カタログであり、D1 に曲ミラーを持たせると
/// 新曲追加のたびにズレて「投票できない」バグになるため、iOS local から解決する。
///
/// APIClient の decoder は convertFromSnakeCase を効かせているため、
/// CodingKeys は書かず property 名そのままに任せる (snake_case 手書きは keyNotFound になる)。
struct PredictionDTO: Codable, Sendable {
    let showId: String
    let songId: String
    let voteCount: Int
    let firstVotedBy: String?
    let firstVotedAt: String?
    let hasUserVoted: Bool
}

// MARK: - SetlistPrediction (表示用モデル)

/// 画面表示用の予想。API のコミュニティデータ (`PredictionDTO`) に
/// iOS local カタログの曲メタデータを結合して組み立てる。
struct SetlistPrediction: Identifiable, Sendable {
    var id: String { songId }
    let showId: String
    let songId: String
    let voteCount: Int
    let firstVotedBy: String?
    let firstVotedAt: String?
    let songTitle: String
    let songBrandId: String?
    let artworkUrl: String?
    let previewUrl: String?
    let appleMusicId: String?
    let hasUserVoted: Bool

    /// API の予想データと local 曲を結合。local に曲が無い場合でも songId を題名にフォールバックして表示する。
    init(dto: PredictionDTO, song: Song?) {
        showId = dto.showId
        songId = dto.songId
        voteCount = dto.voteCount
        firstVotedBy = dto.firstVotedBy
        firstVotedAt = dto.firstVotedAt
        hasUserVoted = dto.hasUserVoted
        songTitle = song?.title ?? dto.songId
        songBrandId = song?.brandId
        artworkUrl = song?.artworkUrl
        previewUrl = song?.previewUrl
        appleMusicId = song?.appleMusicId
    }
}

struct PredictionVoteResult: Codable, Sendable {
    let songId: String
    let voteCount: Int
    let alreadyVoted: Bool?
}

/// 「マイ予想」: 自分が投票した予想 1 件 (API はコミュニティデータのみ、曲/公演メタは local 解決)。
struct MyPredictionDTO: Codable, Sendable {
    let showId: String
    let songId: String
    let voteCount: Int
    let votedAt: String?
}
