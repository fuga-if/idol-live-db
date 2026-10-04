import Foundation

/// 「次はこれ」— 曲が終わったあとに流す曲。選び方はコア (`domain/next_song.rs`)。
struct NextSongCandidate: Sendable, Equatable {
    let song: Song
    /// 画面に添える理由 (「同じ公演で 12 回」など)。
    let label: String
}

protocol NextSongRecommending: Sendable {
    /// 今の曲 `songId` のあとに流す曲を、よい順に最大 `limit` 件。`exclude` はもう流した曲。
    func nextSongs(after songId: String, exclude: [String], limit: Int) async throws -> [NextSongCandidate]
}
