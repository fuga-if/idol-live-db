//! ユニット系スナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `GRDBUnitRepository` (UnitReading ポート) が委譲していた
//! `AppDatabase+StatsQueries` / `AppDatabase+IdolQueries` のユニット系クエリ。
//! ここは domain::unit_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_list_queries.rs と同じ):
//! - 1 ユーザー操作 = 1 呼び出し。unitIndex はロード時前計算の射影を 1 Record で返す。
//! - メンバー・持ち曲の一覧は **表示順の id 列** で返す。実体化 (Idol / Song Record の
//!   組み立て) はプラットフォーム側が自国の store で行う。
//! - `UnitReading.unitIdsWithSongs` 相当は Phase 2 の `unit_ids_with_songs`
//!   (inbound/idol_song_queries.rs) が既に export 済み。二重 export しない。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::unit_queries::{self as queries, UnitIndexRecord, UnitRecord};

#[uniffi::export]
impl SnapshotStore {
    /// ユニット逆引き索引の材料一式 (units 全行 + unit_members 全行 + 曲ありユニット)。
    /// SQL 時代の fetchUnitIndex 相当 (メモ化不要 — 前計算の射影なので毎回軽い)。
    pub fn unit_index_record(&self) -> Result<UnitIndexRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::unit_index_data(&snap))
    }

    /// 単一ユニット。SQL 時代の fetchUnit(id:) 相当。未知 id は nil。
    pub fn unit_record(&self, id: String) -> Result<Option<UnitRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::unit_by_id(&snap, &id))
    }

    /// 全ユニット (brand_id ASC, name ASC)。SQL 時代の fetchAllUnits 相当 (ピッカー用)。
    pub fn all_unit_records(&self) -> Result<Vec<UnitRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::all_units(&snap))
    }

    /// 所属メンバーの idol_id 列 (sort_order 順)。SQL 時代の fetchUnitMembers 相当。
    pub fn unit_member_idol_ids(&self, unit_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::unit_member_idol_ids(&snap, &unit_id))
    }

    /// ユニット持ち曲の song_id 列 (release_date 昇順)。SQL 時代の fetchUnitSongs 相当。
    pub fn unit_song_ids(&self, unit_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::unit_song_ids(&snap, &unit_id))
    }

    /// 指定イベントでユニット単独曲として披露されたユニット id 集合。
    /// SQL 時代の fetchPerformedUnitIds 相当 (呼び出し側は Set として扱う)。
    pub fn performed_unit_ids(&self, event_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::performed_unit_ids(&snap, &event_id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loaded_store() -> std::sync::Arc<SnapshotStore> {
        let store = SnapshotStore::new();
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        store.load(db).expect("bundle DB はロードできる");
        store
    }

    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(store.unit_index_record(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.unit_record("x".into()), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.all_unit_records(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.unit_member_idol_ids("x".into()), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.unit_song_ids("x".into()), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.performed_unit_ids("x".into()), Err(SnapshotError::NotLoaded)));
    }

    /// FFI 面の疎通: 実データで意味のある結果が委譲越しに返る (等価性は domain 側で保証)。
    #[test]
    fn ffi_surface_smoke() {
        let store = loaded_store();

        let index = store.unit_index_record().unwrap();
        assert!(index.units.len() >= 100, "units={}", index.units.len());
        assert!(!index.member_links.is_empty());
        assert!(!index.song_unit_ids.is_empty());

        let all = store.all_unit_records().unwrap();
        assert_eq!(all.len(), index.units.len());

        // 曲ありユニットの 1 つで単一取得・メンバー・持ち曲を通しで引く。
        let uid = index.song_unit_ids[0].clone();
        let unit = store.unit_record(uid.clone()).unwrap().expect("実在ユニット");
        assert_eq!(unit.id, uid);
        assert!(!store.unit_song_ids(uid.clone()).unwrap().is_empty());
        // members はユニットにより 0 の可能性があるため件数は断定しない (エラーでないこと)。
        store.unit_member_idol_ids(uid).unwrap();

        assert_eq!(store.unit_record("存在しないunit".into()).unwrap(), None);
        assert!(store.performed_unit_ids("存在しないevent".into()).unwrap().is_empty());
    }
}
