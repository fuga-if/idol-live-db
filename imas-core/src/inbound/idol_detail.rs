//! アイドル詳細の「次の出演」「タグが似ているアイドル」の FFI 面。
//! 規則は [`crate::domain::idol_detail`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::idol_detail::{self as domain, SimilarIdolCandidate};

/// 出演公演の日付の列から「次の出演」の添字 (今日 = `today_key` 以降でいちばん早いもの)。
/// `today_key` には JST の今日 (`jst_today`) を渡す。
#[uniffi::export]
pub fn next_show_index(dates: Vec<String>, today_key: String) -> Option<u32> {
    domain::next_show_index(&dates, &today_key)
}

/// サーバに頼む「タグが似ているアイドル」の件数 (外部ゲストを除いた後に足りるよう多め)。
#[uniffi::export]
pub fn similar_idols_fetch_limit() -> u32 {
    domain::SIMILAR_IDOLS_FETCH_LIMIT
}

#[uniffi::export]
impl SnapshotStore {
    /// サーバが返した候補から画面に出すものを選ぶ (手元に無い id と外部ゲストを除き、
    /// サーバの並びのまま 10 件)。
    pub fn pick_similar_idols(
        &self,
        candidates: Vec<SimilarIdolCandidate>,
    ) -> Result<Vec<SimilarIdolCandidate>, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::pick_similar_idols(&snap, &candidates))
    }
}
