import Foundation

/// `TimelineReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` のクエリへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBTimelineRepository: TimelineReading {
    let database: AppDatabase

    func timelineBars(brandId: String?) async throws -> [TimelineBar] {
        try await database.fetchTimelineBarsAsync(brandId: brandId)
    }
}
