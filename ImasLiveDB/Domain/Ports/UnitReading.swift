import Foundation

/// ユニットマスタの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/GRDBUnitRepository`。
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
    /// 指定イベントでユニット単独曲として披露されたユニット id 集合。
    func performedUnitIds(eventId: String) async throws -> Set<String>
    /// 全ユニット (ピッカー用)。
    func allUnits() async throws -> [Unit]
}
