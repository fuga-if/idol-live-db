import Foundation

/// `UnitReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
/// スナップショットがまだなら、ロードを待ってから答える (`CoreSnapshotManager.withStore`)。
struct CoreUnitRepository: UnitReading {
    let snapshot: CoreSnapshotManager

    func unitIndex() async throws -> UnitIndex {
        try await snapshot.withStore { store in
            // 逆引き索引 (unit→members / idol→units) の組み立てはプラットフォーム側。
            // core は units 全行 + unit_members 全行 + 曲ありユニット id という素材で返す。
            let record = try store.unitIndexRecord()
            return CoreRecordMapping.unitIndex(from: record)
        }
    }

    func unit(id: String) async throws -> Unit? {
        try await snapshot.withStore { store in
            try store.unitRecord(id: id).map(CoreRecordMapping.unit(from:))
        }
    }

    func unitMembers(unitId: String) async throws -> [Idol] {
        try await snapshot.withStore { store in
            // core は sort_order 順の idol_id 列だけ返す (実体化はプラットフォーム側の規約)。
            try CoreRecordMapping.idols(store: store, orderedIds: store.unitMemberIdolIds(unitId: unitId))
        }
    }

    func unitSongs(unitId: String) async throws -> [Song] {
        try await snapshot.withStore { store in
            try CoreRecordMapping.songs(store: store, orderedIds: store.unitSongIds(unitId: unitId))
        }
    }

    func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> {
        try await snapshot.withStore { store in
            Set(try store.unitIdsWithSongs(unitIds: unitIds))
        }
    }

    func allUnits() async throws -> [Unit] {
        try await snapshot.withStore { store in
            try store.allUnitRecords().map(CoreRecordMapping.unit(from:))
        }
    }
}
