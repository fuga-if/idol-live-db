//! 曲まわりのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: AppDatabase+SongQueries.swift / Android SongDao。
//! ここは Snapshot への委譲だけ。絞り込み等の非自明ロジックは domain に置く。

use super::snapshot_store::{SnapshotError, SnapshotStore};

#[uniffi::export]
impl SnapshotStore {
    /// 歌唱者のアイドル id 列 (sort_order 順)。SQL 時代の fetchSongArtists(ByRole) 相当。
    pub fn song_artist_ids(&self, song_id: String, role: Option<String>) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(snap.song_artists(&song_id, role.as_deref()).into_iter().map(|i| i.id.clone()).collect())
    }

    /// 披露回数 (setlist_items 集計) を song_id ごとに返す。未知 id は 0。
    pub fn song_performance_counts(&self, song_ids: Vec<String>) -> Result<Vec<u32>, SnapshotError> {
        let snap = self.current()?;
        Ok(song_ids
            .iter()
            .map(|id| {
                snap.song_index_by_id
                    .get(id)
                    .map_or(0, |&i| snap.performance_counts[i as usize])
            })
            .collect())
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
        assert!(matches!(store.song_artist_ids("x".into(), None), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn artist_ids_come_back_for_known_songs() {
        let store = loaded_store();
        // original ロールは全曲登録の運用ルール (feedback) — 適当な実在曲で空でないこと
        let snap = store.current().unwrap();
        let with_artists = (0..snap.songs.len())
            .filter(|&i| !snap.artists_by_song[i].is_empty())
            .count();
        assert!(with_artists > 1000, "歌唱者つき曲数={with_artists}");
        let sample = &snap.songs[snap
            .artists_by_song
            .iter()
            .position(|l| !l.is_empty())
            .unwrap()];
        assert!(!store.song_artist_ids(sample.id.clone(), None).unwrap().is_empty());
    }

    #[test]
    fn performance_counts_align_with_ids() {
        let store = loaded_store();
        let counts = store
            .song_performance_counts(vec!["存在しないid".into()])
            .unwrap();
        assert_eq!(counts, vec![0]);
    }
}
