//! 曲詳細まわりのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS AppDatabase+SongQueries.swift (詳細系) / Android SongDao。
//! ここは domain::song_detail_queries への委譲だけ。1 ユーザー操作 = 1 呼び出し。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::song_detail_queries::{
    self, AlbumSummaryRecord, PerformanceHistoryEntry, SeriesSummaryRecord, SongDetailRecord,
};
use std::collections::HashMap;

#[uniffi::export]
impl SnapshotStore {
    /// 曲 id 群の一括取得 (入力 id 順・未知 id は読み飛ばし)。fetchSongs(ids:) 相当。
    pub fn song_records_by_ids(
        &self,
        song_ids: Vec<String>,
    ) -> Result<Vec<SongDetailRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::song_records_by_ids(&snap, &song_ids))
    }

    /// 一覧に出す資格のある曲だけを id で引く (派生曲と brand='other' を隠す)。
    /// fetchListableSongs(ids:) 相当。
    pub fn listable_song_records_by_ids(
        &self,
        song_ids: Vec<String>,
    ) -> Result<Vec<SongDetailRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::listable_song_records_by_ids(&snap, &song_ids))
    }

    /// song_id → original 歌唱者の idol id 列 (sort_order 順)。0 人の曲はキーなし。
    /// fetchSongPerformerIdolsMap(songIds:) 相当。
    pub fn song_performer_idol_ids_map(
        &self,
        song_ids: Vec<String>,
    ) -> Result<HashMap<String, Vec<String>>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::performer_idol_ids_map(&snap, &song_ids))
    }

    /// 曲の披露履歴 (show.date 降順)。fetchSongPerformanceHistory(songId:) 相当。
    pub fn song_performance_history(
        &self,
        song_id: String,
    ) -> Result<Vec<PerformanceHistoryEntry>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::performance_history(&snap, &song_id))
    }

    /// CD シリーズ別アルバム集計 (MIN(release_date) 降順)。fetchAlbums 相当。
    pub fn album_summaries(
        &self,
        brand_ids: Vec<String>,
        query: Option<String>,
    ) -> Result<Vec<AlbumSummaryRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::album_summaries(&snap, &brand_ids, query.as_deref()))
    }

    /// CD シリーズグループ別集計 (MIN(release_date) 降順)。fetchSeries 相当。
    pub fn series_summaries(
        &self,
        brand_ids: Vec<String>,
        query: Option<String>,
    ) -> Result<Vec<SeriesSummaryRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::series_summaries(&snap, &brand_ids, query.as_deref()))
    }

    /// 楽曲シリーズ (series_group) 名の一覧 (曲数降順)。fetchSeriesGroups 相当。
    pub fn series_group_names(
        &self,
        brand_ids: Vec<String>,
    ) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::series_group_names(&snap, &brand_ids))
    }

    /// 同じ曲の別バージョン一族 (自分は除く)。fetchVariantSongs(of:) 相当。
    pub fn variant_song_records(
        &self,
        song_id: String,
    ) -> Result<Vec<SongDetailRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_detail_queries::variant_song_records(&snap, &song_id))
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

    /// 未ロード時は全 API が型付きエラーを返す (アプリ側が SQL 経路へフォールバック
    /// できる契約)。
    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(store.song_records_by_ids(vec![]), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.song_performance_history("x".into()), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.album_summaries(vec![], None), Err(SnapshotError::NotLoaded)));
    }

    /// inbound は委譲のみ (domain 直呼びと同一結果) であることを代表 API で確認する。
    #[test]
    fn ffi_layer_delegates_to_domain() {
        let store = loaded_store();
        let snap = store.current().unwrap();

        let ids: Vec<String> = snap.songs.iter().take(20).map(|s| s.id.clone()).collect();
        assert_eq!(
            store.song_records_by_ids(ids.clone()).unwrap(),
            crate::domain::song_detail_queries::song_records_by_ids(&snap, &ids)
        );
        assert_eq!(
            store.song_performer_idol_ids_map(ids.clone()).unwrap(),
            crate::domain::song_detail_queries::performer_idol_ids_map(&snap, &ids)
        );
        assert_eq!(
            store.album_summaries(vec![], None).unwrap(),
            crate::domain::song_detail_queries::album_summaries(&snap, &[], None)
        );
        assert_eq!(
            store.variant_song_records(ids[0].clone()).unwrap(),
            crate::domain::song_detail_queries::variant_song_records(&snap, &ids[0])
        );
    }
}
