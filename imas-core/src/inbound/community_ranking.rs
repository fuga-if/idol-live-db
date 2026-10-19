//! みんなの集計の順位の FFI 面。規則は [`crate::domain::community_ranking`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::community_ranking::{self as domain, CommunityRankingKind, CommunityStats, RankedSong, SongCommunityStat};

/// `GET /community/song-stats` の応答を読む。読めなければ None。
#[uniffi::export]
pub fn community_stats_parse(json: String) -> Option<CommunityStats> {
    domain::parse_stats(&json)
}

/// 1 曲の集計 (載っていなければ全部 0)。
#[uniffi::export]
pub fn community_stat_for(stats: CommunityStats, song_id: String) -> SongCommunityStat {
    domain::stat_for(&stats, &song_id)
}

#[uniffi::export]
impl SnapshotStore {
    /// 順位表。`brand_id` を渡すとそのブランドの曲 (合同曲は参加ブランド全部) に絞る。
    /// マスタに無い曲は出さない。
    pub fn community_ranking(
        &self,
        stats: CommunityStats,
        kind: CommunityRankingKind,
        brand_id: Option<String>,
        limit: u32,
    ) -> Result<Vec<RankedSong>, SnapshotError> {
        let snap = self.current()?;
        let in_scope = |id: &str| {
            snap.song(id)
                .is_some_and(|s| brand_id.as_deref().is_none_or(|b| s.belongs_to_brand(b)))
        };
        Ok(domain::rank(&stats, kind, in_scope, limit as usize))
    }
}
