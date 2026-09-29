import Foundation

/// ユニットマスタの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/CoreUnitRepository` (共有コアのスナップショット)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol UnitReading: Sendable {
    /// ユニット逆引き用インデックス (メンバー構成からの判定に使う)。
    func unitIndex() async throws -> UnitIndex
    /// 単一ユニット。
    func unit(id: String) async throws -> Unit?
    /// 所属メンバー。
    func unitMembers(unitId: String) async throws -> [Idol]
    /// ユニット曲。
    func unitSongs(unitId: String) async throws -> [Song]
    /// 指定ユニット集合のうち、曲を持つユニット id 集合。
    func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String>
    /// 全ユニット (ピッカー用)。
    func allUnits() async throws -> [Unit]
}

extension UnitReading {
    /// 曲ありユニットのみ (`UnitIndex.unitsWithSongs`)。ユニット一覧・Poll候補ピッカー等、
    /// 曲を持たないユニットを対象外にしたい場面で共通して使う唯一の正。
    func unitsWithSongs() async throws -> [Unit] {
        let index = try await unitIndex()
        return index.units.filter { index.unitsWithSongs.contains($0.id) }
    }
}
