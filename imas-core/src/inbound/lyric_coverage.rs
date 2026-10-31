//! 歌詞の投稿状況の FFI 面。規則は [`crate::domain::lyric_coverage`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::lyric_coverage::{self as domain, LyricCoverageRecord};

#[uniffi::export]
impl SnapshotStore {
    /// 歌詞の投稿状況 (全体とブランド別)。`published_song_ids` はサーバの公開曲 id (`GET /lyrics/published`)。
    pub fn lyric_coverage(
        &self,
        published_song_ids: Vec<String>,
    ) -> Result<LyricCoverageRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::lyric_coverage(&snap, &published_song_ids))
    }

    /// 歌詞が公開されている曲の id 一覧 (`lyric_coverage` と同じ母集合)。`brand_id` でブランドを絞る。
    /// 並びはブランドの表示順 → 50 音。
    pub fn lyric_song_ids(
        &self,
        published_song_ids: Vec<String>,
        brand_id: Option<String>,
    ) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::lyric_song_ids(&snap, &published_song_ids, brand_id.as_deref()))
    }
}
