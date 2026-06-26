import Foundation

/// `BrandReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBBrandRepository: BrandReading {
    let database: AppDatabase

    func brands() async throws -> [Brand] {
        try database.fetchBrands()
    }
}
