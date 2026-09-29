import Foundation

/// ユニットの一覧・メンバー・曲の有無をまとめて持つ索引。`unitReading.unitIndex()` で 1 回引いて使い回す。
struct UnitIndex: Sendable {
    let units: [Unit]
    /// unit_id → メンバー idol_id の集合
    let memberIds: [String: Set<String>]
    /// 楽曲が紐付いている unit_id (songs.unit_id 参照)。一覧・ピッカーは曲ありユニットだけを出す。
    let unitsWithSongs: Set<String>

    init(
        units: [Unit],
        memberIds: [String: Set<String>],
        unitsWithSongs: Set<String> = []
    ) {
        self.units = units
        self.memberIds = memberIds
        self.unitsWithSongs = unitsWithSongs
    }
}
