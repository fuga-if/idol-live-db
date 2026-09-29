//! 回収ダッシュボードの FFI 面。規則は [`crate::domain::collection_dashboard`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::collection_dashboard::{self as domain, CollectionDashboardRecord};

#[uniffi::export]
impl SnapshotStore {
    /// 統計タブの回収ダッシュボード 1 画面分 (回収率・未回収曲・「聴けるかも」の公演)。
    /// `collected_song_ids` は回収済みの曲 (一覧の回収バッジと同じ集合)、`today` は JST の今日、
    /// `chance_limit` は「聴けるかも」を何件まで返すか (今の画面は 8)。
    pub fn collection_dashboard(
        &self,
        collected_song_ids: Vec<String>,
        pick_idol_ids: Vec<String>,
        today: String,
        chance_limit: u32,
    ) -> Result<CollectionDashboardRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::collection_dashboard(&snap, &collected_song_ids, &pick_idol_ids, &today, chance_limit))
    }
}
