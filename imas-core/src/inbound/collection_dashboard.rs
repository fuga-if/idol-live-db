//! 回収ダッシュボードの FFI 面。規則は [`crate::domain::collection_dashboard`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::collection_dashboard::{self as domain, CollectionDashboardRecord, CollectionScope, UncollectedListRecord};

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

    /// 未回収一覧の画面 1 つ分 (ブランド別の回収率のバー・「すべて見る」の先)。原曲単位で、
    /// 未回収を「披露済み」と「未披露」に分けて返す。`collected_song_ids` はダッシュボードと同じ集合。
    pub fn uncollected_songs(
        &self,
        collected_song_ids: Vec<String>,
        scope: CollectionScope,
    ) -> Result<UncollectedListRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::uncollected_songs(&snap, &collected_song_ids, &scope))
    }

    /// 回収した原曲の数 (P名刺・プロフィール帳の「回収曲」。ダッシュボードの全体の回収数と同じ)。
    pub fn collected_original_song_count(&self, collected_song_ids: Vec<String>) -> Result<u32, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::collected_original_song_count(&snap, &collected_song_ids))
    }
}
