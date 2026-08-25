import Foundation

/// `BrandReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則):
/// - ロード済み → `SnapshotStore.brandRecords()`
/// - 未ロード / ロード失敗 / メモリ警告で破棄後 → 従来の `GRDBBrandRepository`
struct CoreBrandRepository: BrandReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時の受け皿 (Strangler の旧経路)。
    let fallback: GRDBBrandRepository

    func brands() async throws -> [Brand] {
        try await snapshot.withStore(fallbackTo: { try await fallback.brands() }) { store in
            try store.brandRecords().map(CoreRecordMapping.brand(from:))
        }
    }
}
