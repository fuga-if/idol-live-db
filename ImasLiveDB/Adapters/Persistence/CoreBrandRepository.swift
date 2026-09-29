import Foundation

/// `BrandReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
/// スナップショットがまだなら、ロードを待ってから答える (`CoreSnapshotManager.withStore`)。
struct CoreBrandRepository: BrandReading {
    let snapshot: CoreSnapshotManager

    func brands() async throws -> [Brand] {
        try await snapshot.withStore { store in
            try store.brandRecords().map(CoreRecordMapping.brand(from:))
        }
    }
}
