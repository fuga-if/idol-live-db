//! 楽曲一覧まわりのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `AppDatabase+SongQueries` / `AppDatabase+EventQueries` の一覧系
//! (Android は SongDao 相当)。ここは domain::song_list_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_queries.rs と同じ):
//! - 一覧はエンティティ全体でなく **表示順の song_id 列** で返す。実体化 (Record 取得や
//!   SongWithArtists 組み立て) はプラットフォーム側が自国の store で行う。
//! - **user_marks はスナップショットに無い**。回収系は参加マークをプラットフォーム側で
//!   解決した show/event の id 集合を引数で受け取る (バッジは「現地のみ」等の参加種別
//!   条件を適用済みの show id を、並び替えは種別条件なしの全 attended show id を渡す)。
//! - シリーズ一覧 (fetchSeries / fetchSeriesGroups 相当) は song_detail_queries.rs の
//!   `series_summaries` / `series_group_names` が担う (二重 export しない)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::song_list_queries::{
    self as queries, SongListFilter, SongListSort,
};
use std::collections::HashMap;

#[uniffi::export]
impl SnapshotStore {
    /// 絞り込み + 整列済みの楽曲一覧 (表示順の song_id 列)。
    /// SQL 時代の fetchSongs(filter:sortOrder:ascending:) 相当。
    /// `attended_*` は CollectedCount / CollectedRate の並び替えでだけ使う
    /// (それ以外のソートでは空配列で良い)。
    pub fn song_list(
        &self,
        filter: SongListFilter,
        sort: SongListSort,
        ascending: Option<bool>,
        attended_show_ids: Vec<String>,
        attended_event_ids: Vec<String>,
    ) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(self.ids(
            &snap,
            queries::song_list_indexes(
                &snap,
                &filter,
                sort,
                ascending,
                &attended_show_ids,
                &attended_event_ids,
            ),
        ))
    }

    /// CD シリーズ名 (完全一致) の楽曲一覧。SQL 時代の songsByCdSeriesQuery 相当。
    pub fn songs_by_cd_series(&self, series: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(self.ids(&snap, queries::songs_by_cd_series(&snap, &series)))
    }

    /// シリーズ (series_group 完全一致) の楽曲一覧。SQL 時代の songsBySeriesGroupQuery 相当。
    pub fn songs_by_series_group(&self, name: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(self.ids(&snap, queries::songs_by_series_group(&snap, &name)))
    }

    /// リリース年 ("YYYY" 前方一致) の楽曲一覧。SQL 時代の songsByReleaseYearQuery 相当。
    pub fn songs_by_release_year(&self, year: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(self.ids(&snap, queries::songs_by_release_year(&snap, &year)))
    }

    /// 任意の id 集合を 50 音順で返す。SQL 時代の songsByIdsOrderedQuery 相当。
    pub fn songs_by_ids_ordered(&self, ids: Vec<String>) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(self.ids(&snap, queries::songs_by_ids_ordered(&snap, &ids)))
    }

    /// song_id → 全公演での披露回数 (披露 0 回は載らない)。
    /// SQL 時代の fetchSongPerformanceCounts (一覧バッジ・全曲マップ) 相当。
    pub fn song_performance_count_map(&self) -> Result<HashMap<String, u32>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::performance_count_map(&snap))
    }

    /// song_id → 現地回収数 (参加した公演のうちその曲が披露された公演の異なり数)。
    /// SQL 時代の fetchSongCollectedCounts (real_live_only=true) /
    /// attendedSongCountMap (false) 相当。参加マークの解決はプラットフォーム側。
    pub fn song_collected_count_map(
        &self,
        attended_show_ids: Vec<String>,
        attended_event_ids: Vec<String>,
        real_live_only: bool,
    ) -> Result<HashMap<String, u32>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::collected_count_map(
            &snap,
            &attended_show_ids,
            &attended_event_ids,
            real_live_only,
        ))
    }
}

impl SnapshotStore {
    /// 添字列 → song_id 列 (uniffi::export の対象外のヘルパ)。
    fn ids(&self, snap: &crate::domain::snapshot::Snapshot, indexes: Vec<u32>) -> Vec<String> {
        indexes.into_iter().map(|i| snap.songs[i as usize].id.clone()).collect()
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

    fn browse_filter() -> SongListFilter {
        SongListFilter {
            include_other_brand: false,
            exclude_live_only: true,
            ..SongListFilter::default()
        }
    }

    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(
            store.song_list(browse_filter(), SongListSort::TitleKana, None, vec![], vec![]),
            Err(SnapshotError::NotLoaded)
        ));
        assert!(matches!(store.song_performance_count_map(), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        let ids = store
            .song_list(browse_filter(), SongListSort::TitleKana, None, vec![], vec![])
            .unwrap();
        assert!(ids.len() > 1000, "一覧は千曲単位で返る (len={})", ids.len());

        let perf = store.song_performance_count_map().unwrap();
        assert!(!perf.is_empty());
        assert!(store.song_collected_count_map(vec![], vec![], true).unwrap().is_empty());

        let by_year = store.songs_by_release_year("2015".into()).unwrap();
        assert!(!by_year.is_empty());
        assert_eq!(store.songs_by_ids_ordered(vec!["存在しないid".into()]).unwrap(), Vec::<String>::new());
    }
}
