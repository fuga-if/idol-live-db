//! 「次はこれ」の FFI 口。規則は domain::next_song。

use crate::domain::next_song::recommend_next;
pub use crate::domain::next_song::{NextSongPick, NextSongReason};
use crate::inbound::snapshot_store::{SnapshotError, SnapshotStore};

#[uniffi::export]
impl SnapshotStore {
    /// 今の曲のあとに流す曲を、よい順に最大 `limit` 件。`exclude` はもう流した曲。
    pub fn next_song_recommendations(
        &self,
        song_id: String,
        exclude: Vec<String>,
        limit: u32,
    ) -> Result<Vec<NextSongPick>, SnapshotError> {
        let snap = self.current()?;
        Ok(recommend_next(&snap, &song_id, &exclude, limit))
    }
}
