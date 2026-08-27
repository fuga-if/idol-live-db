//! 統計まわりのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `AppDatabase+StatsQueries` の Stats 系 (Android は StatsDao 相当)。
//! ポート対応: `StatsReading` 全メソッド + `SongReading.brandedSongIds` +
//! `SongReading.cdSeriesList` + `DiagnosticsReading.metaValue`。ここは domain::stats_queries / domain::snapshot への
//! 委譲だけ。
//!
//! FFI 形状の規約 (song_list_queries.rs と同じ):
//! - 集計クエリはエンティティではなく **表示行そのものの射影 Record** で返す
//!   (集計行に再引きする実体が無いため。一覧系の「id 列で返す」と対になる判断)。
//! - `DiagnosticsReading` の databaseStats / syncDiagnostics は移送しない
//!   (永続 DB そのものを観測する診断。理由は domain::stats_queries のモジュール doc)。
//! - 回収率のマーク依存側はプラットフォームが解決する。ここは母集合
//!   (`branded_song_ids`) だけを供給する。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::stats_queries::{
    self as queries, BrandSongCountRecord, CastShowCountRecord, SongPlayCountRecord,
    YearlyShowCountRecord,
};

#[uniffi::export]
impl SnapshotStore {
    /// ブランド別楽曲数 (楽曲ゼロのブランドも 0 件で載る)。
    /// SQL 時代の fetchBrandSongCounts 相当。
    pub fn brand_song_counts(&self) -> Result<Vec<BrandSongCountRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::brand_song_counts(&snap))
    }

    /// ライブ披露回数ランキング (披露 0 回の曲は載らない)。
    /// SQL 時代の fetchSongPlayCountRanking 相当 (iOS 既定 limit=20)。
    pub fn song_play_count_ranking(
        &self,
        limit: u32,
    ) -> Result<Vec<SongPlayCountRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::song_play_count_ranking(&snap, limit))
    }

    /// アイドル別出演公演数ランキング (出演記録の無いアイドルは載らない)。
    /// SQL 時代の fetchCastShowCountRanking 相当 (iOS 既定 limit=20)。
    pub fn cast_show_count_ranking(
        &self,
        limit: u32,
    ) -> Result<Vec<CastShowCountRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::cast_show_count_ranking(&snap, limit))
    }

    /// 年別ライブ開催数推移 (年の昇順)。SQL 時代の fetchYearlyShowCounts 相当。
    pub fn yearly_show_counts(&self) -> Result<Vec<YearlyShowCountRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::yearly_show_counts(&snap))
    }

    /// brand_id が設定されている曲 id (回収率集計の母集合)。
    /// SQL 時代の fetchBrandedSongIds 相当。集合化は呼び出し側 (iOS は Set<String>)。
    pub fn branded_song_ids(&self) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::branded_song_ids(&snap))
    }

    /// meta 表の値 (schema_version / data_version 等)。SQL 時代の fetchMetaValue 相当。
    /// 行なしと value NULL は区別せず None (Meta.getValue の観測挙動と同じ)。
    pub fn meta_value(&self, key: String) -> Result<Option<String>, SnapshotError> {
        Ok(self.current()?.meta_value(&key).map(str::to_string))
    }

    /// CD シリーズ名の一覧 (BINARY 昇順・重複なし・空文字と NULL は除外)。
    /// SQL 時代の fetchCdSeriesList 相当で、曲フィルタのピッカーが顧客。
    pub fn cd_series_list(&self) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::cd_series_list(&snap))
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
        assert!(matches!(store.brand_song_counts(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.song_play_count_ranking(20), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.cast_show_count_ranking(20), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.yearly_show_counts(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.branded_song_ids(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.meta_value("data_version".into()), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        assert!(!store.brand_song_counts().unwrap().is_empty());
        assert_eq!(store.song_play_count_ranking(20).unwrap().len(), 20);
        assert_eq!(store.cast_show_count_ranking(20).unwrap().len(), 20);
        assert!(!store.yearly_show_counts().unwrap().is_empty());
        assert!(store.branded_song_ids().unwrap().len() > 1000);
        assert!(store.meta_value("data_version".into()).unwrap().is_some());
        assert_eq!(store.meta_value("存在しないキー".into()).unwrap(), None);
    }
}
