import Foundation

/// `UnitReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則)。
/// ポートの全メソッドに対応する core API があるため、未ロード時以外は全て core 経路。
struct CoreUnitRepository: UnitReading {
    let snapshot: CoreSnapshotManager
    /// スナップショット未ロード時の受け皿 (Strangler の旧経路)。
    ///
    /// 全メソッド移送済みなのでここへ落ちる理由は「未移送」ではなく
    /// 「スナップショットが無い」だけ。ローダが表・列を 1 つ読み損ねると
    /// 全クエリが同時に死ぬので、この経路は残す。
    let fallback: GRDBUnitRepository

    func unitIndex() async throws -> UnitIndex {
        try await snapshot.withStore(fallbackTo: { try await fallback.unitIndex() }) { store in
            // 逆引き索引 (unit→members / idol→units) の組み立てはプラットフォーム側。
            // core は units 全行 + unit_members 全行 + 曲ありユニット id という素材で返す。
            let record = try store.unitIndexRecord()
            return CoreRecordMapping.unitIndex(from: record)
        }
    }

    func unit(id: String) async throws -> Unit? {
        try await snapshot.withStore(fallbackTo: { try await fallback.unit(id: id) }) { store in
            try store.unitRecord(id: id).map(CoreRecordMapping.unit(from:))
        }
    }

    func unitMembers(unitId: String) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.unitMembers(unitId: unitId) }) { store in
            // core は sort_order 順の idol_id 列だけ返す (実体化はプラットフォーム側の規約)。
            try CoreRecordMapping.idols(store: store, orderedIds: store.unitMemberIdolIds(unitId: unitId))
        }
    }

    func unitSongs(unitId: String) async throws -> [Song] {
        try await snapshot.withStore(fallbackTo: { try await fallback.unitSongs(unitId: unitId) }) { store in
            try CoreRecordMapping.songs(store: store, orderedIds: store.unitSongIds(unitId: unitId))
        }
    }

    func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.unitIdsWithSongs(unitIds: unitIds) }) { store in
            Set(try store.unitIdsWithSongs(unitIds: unitIds))
        }
    }

    func performedUnitIds(eventId: String) async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.performedUnitIds(eventId: eventId) }) { store in
            Set(try store.performedUnitIds(eventId: eventId))
        }
    }

    func allUnits() async throws -> [Unit] {
        try await snapshot.withStore(fallbackTo: { try await fallback.allUnits() }) { store in
            try store.allUnitRecords().map(CoreRecordMapping.unit(from:))
        }
    }
}
