//! アイドル→曲の逆引きスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: AppDatabase+IdolQueries.swift の曲関連クエリ
//! (fetchIdolSongs / fetchIdolPerformedSongs / fetchIdolSongHistory / fetchUnitIdsWithSongs)。
//! ここは Snapshot への委譲だけ。並び順・重複排除などの非自明ロジックは
//! domain::idol_song_queries に置く。

use crate::domain::idol_song_queries::{
    self, IdolPerformedSongRecord, IdolSongRecord, IdolSongShowRecord,
};
use super::snapshot_store::{SnapshotError, SnapshotStore};

#[uniffi::export]
impl SnapshotStore {
    /// アイドルの持ち歌一覧 (release_date 降順)。SQL 時代の fetchIdolSongs 相当。
    /// role 未指定時は role 違いの重複行が返る点も SQL と同じ。
    pub fn idol_song_records(
        &self,
        idol_id: String,
        role: Option<String>,
    ) -> Result<Vec<IdolSongRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(idol_song_queries::idol_songs(&snap, &idol_id, role.as_deref()))
    }

    /// アイドルがライブで披露した曲一覧 (披露回数降順)。fetchIdolPerformedSongs 相当。
    pub fn idol_performed_song_records(
        &self,
        idol_id: String,
    ) -> Result<Vec<IdolPerformedSongRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(idol_song_queries::idol_performed_songs(&snap, &idol_id))
    }

    /// アイドルが特定の曲を披露した公演履歴 (日付降順)。fetchIdolSongHistory 相当。
    pub fn idol_song_history_records(
        &self,
        idol_id: String,
        song_id: String,
    ) -> Result<Vec<IdolSongShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(idol_song_queries::idol_song_history(&snap, &idol_id, &song_id))
    }

    /// 指定ユニット ID のうち楽曲を持つもの (入力順・重複なし)。fetchUnitIdsWithSongs 相当。
    pub fn unit_ids_with_songs(
        &self,
        unit_ids: Vec<String>,
    ) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(idol_song_queries::unit_ids_with_songs(&snap, &unit_ids))
    }

    /// ユニット経由の関与曲 (所属ユニットの持ち曲 song_id 列)。
    pub fn idol_unit_song_ids(&self, idol_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(idol_song_queries::idol_unit_song_ids(&snap, &idol_id))
    }

    /// 指定アイドルのいずれかが原曲歌唱者として立つ曲の song_id 列
    /// (songs 添字昇順・重複なし)。SQL 時代の fetchSongIdsWithAnyArtist 相当。
    /// 曲一覧の担当アイドル絞り込みが顧客で、集合化は呼び出し側 (iOS は Set<String>)。
    /// 1 idol ずつ FFI を往復させないため、id 集合をまとめて受ける形にしてある。
    pub fn song_ids_with_any_artist(
        &self,
        idol_ids: Vec<String>,
    ) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(idol_song_queries::song_ids_with_any_artist(&snap, &idol_ids))
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
        assert!(matches!(
            store.idol_song_records("x".into(), None),
            Err(SnapshotError::NotLoaded)
        ));
        assert!(matches!(
            store.idol_performed_song_records("x".into()),
            Err(SnapshotError::NotLoaded)
        ));
        assert!(matches!(
            store.idol_song_history_records("x".into(), "y".into()),
            Err(SnapshotError::NotLoaded)
        ));
        assert!(matches!(store.unit_ids_with_songs(vec![]), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.idol_unit_song_ids("x".into()), Err(SnapshotError::NotLoaded)));
    }

    /// FFI 面の疎通: 実データで空でない結果が委譲越しに返る (ロジック検証は domain 側)。
    #[test]
    fn delegation_returns_data_for_a_real_idol() {
        let store = loaded_store();
        let snap = store.current().unwrap();
        let ii = (0..snap.idols.len())
            .find(|&i| !snap.performed_items_by_idol[i].is_empty())
            .expect("歌唱記録持ちアイドルは居る");
        let idol_id = snap.idols[ii].id.clone();

        let performed = store.idol_performed_song_records(idol_id.clone()).unwrap();
        assert!(!performed.is_empty());
        let history = store
            .idol_song_history_records(idol_id.clone(), performed[0].song_id.clone())
            .unwrap();
        assert!(!history.is_empty());
        // original 縛り (アイドル詳細「楽曲 (原曲)」タブの実引数) も疎通確認
        let originals = store.idol_song_records(idol_id, Some("original".into())).unwrap();
        for r in &originals {
            assert_eq!(r.role, "original");
        }
    }
}
