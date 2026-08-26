import Foundation

/// `PerformanceEvidenceReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
///
/// 共有コアのスナップショットが無い間もこの節を出し続けるための経路。数え方は
/// `AppDatabase+PerformanceEvidenceQueries` でコアと 1:1 に揃えてある
/// (経路が違うと根拠の数字が変わる、では根拠として使えない)。
struct GRDBPerformanceEvidenceRepository: PerformanceEvidenceReading {
    let database: AppDatabase

    func songPerformanceEvidence(
        songId: String,
        coLimit: Int,
        singerLimit: Int
    ) async throws -> SongPerformanceEvidence {
        try await database.fetchSongPerformanceEvidenceAsync(
            songId: songId,
            coLimit: max(0, coLimit),
            singerLimit: max(0, singerLimit)
        )
    }
}
