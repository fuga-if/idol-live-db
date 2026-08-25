//! アイドル・ブランドマスタのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `IdolReading` / `BrandReading` ポート配下
//! (AppDatabase+IdolQueries / +EventQueries の criterion / +StatsQueries の
//! searchIdols・fetchBrands / +Sync の picker)。ここは domain::idol_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_detail_queries.rs と同じ):
//! - アイドルは詳細プロフィール画面が全カラムを使うため **全域射影の Record** で返す
//!   (id 列で返して引き直させると 2 呼び出しになり「1 ユーザー操作 = 1 FFI」に反する)。
//! - IdolFilterCriterion (Swift enum) はケースごとに独立した関数で受ける。生成
//!   バインディングがアプリと同一モジュールに入るため、同名 enum を FFI に生やすと
//!   既存 Swift 型と衝突する (idol_list_filtering.rs の前例と同じ判断)。
//!   .brand ケースは idol_list(brand_id:) が担う。
//! - アイドル→曲の逆引き (idol_songs 系) は Phase 2 の idol_song_queries.rs が
//!   既に export 済み (二重 export しない)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::idol_queries::{
    self as queries, BrandRecord, IdolRecord, IdolShowRecord, IdolUnitRecord,
    IdolVoiceActorRecord,
};
use std::collections::HashMap;

#[uniffi::export]
impl SnapshotStore {
    /// アイドル一覧 (外部ゲスト除外・sort_order 順)。brand_id 指定で idol_brands 絞り込み。
    /// SQL 時代の fetchIdols(brandId:) / IdolFilterCriterion.brand 相当。
    pub fn idol_list(&self, brand_id: Option<String>) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idol_list(&snap, brand_id.as_deref()))
    }

    /// アイドル id 群の一括取得 (入力 id 順・初出のみ・未知 id は読み飛ばし)。
    /// SQL 時代の fetchIdols(ids:) / fetchIdol(id:) 相当。
    pub fn idol_records_by_ids(
        &self,
        idol_ids: Vec<String>,
    ) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idol_records_by_ids(&snap, &idol_ids))
    }

    /// 誕生月フィルタ (1..=12)。SQL 時代の IdolFilterCriterion.birthMonth 相当。
    pub fn idols_by_birth_month(&self, month: u32) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idols_by_birth_month(&snap, month))
    }

    /// 星座フィルタ (完全一致)。SQL 時代の IdolFilterCriterion.constellation 相当。
    pub fn idols_by_constellation(
        &self,
        constellation: String,
    ) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idols_by_constellation(&snap, &constellation))
    }

    /// 出身地フィルタ (完全一致)。SQL 時代の IdolFilterCriterion.birthPlace 相当。
    pub fn idols_by_birth_place(
        &self,
        birth_place: String,
    ) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idols_by_birth_place(&snap, &birth_place))
    }

    /// 血液型フィルタ (完全一致)。SQL 時代の IdolFilterCriterion.bloodType 相当。
    pub fn idols_by_blood_type(
        &self,
        blood_type: String,
    ) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idols_by_blood_type(&snap, &blood_type))
    }

    /// idol_id → 現任 CV 名のマップ (現任なしのアイドルはキーなし)。
    /// SQL 時代の fetchIdolCastNames 相当。
    pub fn idol_cast_names(&self) -> Result<HashMap<String, String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idol_cast_names(&snap))
    }

    /// 声優名 (完全一致・歴代対象) で担当アイドルを逆引き。
    /// SQL 時代の fetchIdolsByVoiceActor 相当。
    pub fn idols_by_voice_actor(&self, name: String) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idols_by_voice_actor(&snap, &name))
    }

    /// 名前 / かな / ローマ字 / 別名 / CV 名の部分一致検索 (sort_order 順・limit 打ち切り)。
    /// SQL 時代の searchIdols(query:limit:) 相当。
    pub fn search_idols(
        &self,
        query: String,
        limit: u32,
    ) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::search_idols(&snap, &query, limit))
    }

    /// 編集 UI のピッカー用: 全アイドル (外部ゲスト含む・sort_order 順)。
    /// SQL 時代の fetchAllIdolsForPicker 相当。
    pub fn all_idols_for_picker(&self) -> Result<Vec<IdolRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::all_idols_for_picker(&snap))
    }

    /// 現任 CV 名 (valid_to IS NULL)。後任未定の交代期間中は None。
    /// SQL 時代の fetchCurrentVoiceActor 相当。
    pub fn idol_current_voice_actor(
        &self,
        idol_id: String,
    ) -> Result<Option<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::current_voice_actor_name(&snap, &idol_id))
    }

    /// 歴代 CV (IFNULL(valid_from,'') DESC = 新しい順)。
    /// SQL 時代の fetchVoiceActorHistory 相当。
    pub fn idol_voice_actor_history(
        &self,
        idol_id: String,
    ) -> Result<Vec<IdolVoiceActorRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::voice_actor_history(&snap, &idol_id))
    }

    /// 所属ユニット一覧 (unit.name 昇順)。SQL 時代の fetchIdolUnits 相当。
    pub fn idol_units(&self, idol_id: String) -> Result<Vec<IdolUnitRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idol_units(&snap, &idol_id))
    }

    /// 出演公演一覧 (セトリ歌唱 ∪ show_cast・date DESC)。SQL 時代の fetchIdolShows 相当。
    pub fn idol_shows(&self, idol_id: String) -> Result<Vec<IdolShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::idol_shows(&snap, &idol_id))
    }

    /// 全ブランド (sort_order 順)。SQL 時代の fetchBrands 相当。
    pub fn brand_records(&self) -> Result<Vec<BrandRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::brand_records(&snap))
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
        assert!(matches!(store.idol_list(None), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.brand_records(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.idol_cast_names(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(
            store.search_idols("み".into(), 50),
            Err(SnapshotError::NotLoaded)
        ));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        let all = store.idol_list(None).unwrap();
        assert!(all.len() > 100, "全アイドル数={}", all.len());

        let brands = store.brand_records().unwrap();
        assert!(brands.len() >= 5);
        let brand_idols = store.idol_list(Some(brands[0].id.clone())).unwrap();
        assert!(!brand_idols.is_empty());

        let picked = store.idol_records_by_ids(vec![all[0].id.clone()]).unwrap();
        assert_eq!(picked.len(), 1);
        assert_eq!(picked[0].id, all[0].id);

        assert!(!store.idol_cast_names().unwrap().is_empty());
        assert!(!store.all_idols_for_picker().unwrap().is_empty());
        assert!(!store.idols_by_birth_month(1).unwrap().is_empty());
        assert!(store.idols_by_voice_actor("存在しない声優".into()).unwrap().is_empty());
        assert!(store.idol_shows("存在しないid".into()).unwrap().is_empty());
        assert_eq!(store.idol_current_voice_actor("存在しないid".into()).unwrap(), None);
    }
}
