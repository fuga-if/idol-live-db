import Foundation

/// `StatsReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則)。
/// 4 メソッドすべてに対応する core API があるため、未ロード時以外は全て core 経路。
struct CoreStatsRepository: StatsReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時の受け皿 (Strangler の旧経路)。
    let fallback: GRDBStatsRepository

    func brandSongCounts() async throws -> [BrandSongCount] {
        try await snapshot.withStore(fallbackTo: { try await fallback.brandSongCounts() }) { store in
            try store.brandSongCounts().map(CoreRecordMapping.brandSongCount(from:))
        }
    }

    func songPlayCountRanking(limit: Int) async throws -> [SongPlayCount] {
        try await snapshot.withStore(fallbackTo: { try await fallback.songPlayCountRanking(limit: limit) }) { store in
            try store.songPlayCountRanking(limit: UInt32(max(0, limit))).map(CoreRecordMapping.songPlayCount(from:))
        }
    }

    func castShowCountRanking(limit: Int) async throws -> [CastShowCount] {
        try await snapshot.withStore(fallbackTo: { try await fallback.castShowCountRanking(limit: limit) }) { store in
            try store.castShowCountRanking(limit: UInt32(max(0, limit))).map(CoreRecordMapping.castShowCount(from:))
        }
    }

    func yearlyShowCounts() async throws -> [YearlyShowCount] {
        try await snapshot.withStore(fallbackTo: { try await fallback.yearlyShowCounts() }) { store in
            try store.yearlyShowCounts().map(CoreRecordMapping.yearlyShowCount(from:))
        }
    }
}
