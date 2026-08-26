//! 披露実績の統計の FFI 口。
//!
//! 曲詳細を 1 回開くのに共起と歌唱者の両方が要るので、**1 呼び出しで束ねて返す**
//! ([`SnapshotStore::song_performance_insights`])。個別に呼びたい場面のために
//! 単体の口も残してあるが、画面から使うのは束ねた方。

use crate::domain::performance_stats::{
    co_occurring_songs as co, singers_for_song as singers, CoOccurrence, SingerTally,
};
use crate::inbound::snapshot_store::{SnapshotError, SnapshotStore};

/// 曲詳細に出す披露実績。
///
/// **どちらも過去の実績であって予言ではない。** UI では必ず回数を添えること
/// (`together` / `performances`、`times` / `total`)。回数を出さずに
/// 「よく一緒に来る」とだけ書くと、外れたときに嘘になる。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongPerformanceInsights {
    /// 同じ公演で演奏された曲 (多い順)。
    pub co_occurring: Vec<CoOccurrence>,
    /// その曲を歌った実績 (多い順)。
    pub singers: Vec<SingerTally>,
}

#[uniffi::export]
impl SnapshotStore {
    /// 曲詳細ぶんの披露実績を 1 回で取る。
    ///
    /// 相手の曲名・アイドル名は id でしか返らないので、呼び出し側が
    /// `song_records_by_ids` / `idol_records_by_ids` を **1 回ずつ**引いて解決する
    /// (行ごとに引かないこと)。
    pub fn song_performance_insights(
        &self,
        song_id: String,
        co_limit: u32,
        singer_limit: u32,
    ) -> Result<SongPerformanceInsights, SnapshotError> {
        let snap = self.current()?;
        Ok(SongPerformanceInsights {
            co_occurring: co(&snap, &song_id, co_limit),
            singers: singers(&snap, &song_id, &[], singer_limit),
        })
    }

    /// この曲と同じ公演で演奏された曲を、多い順に返す。
    pub fn co_occurring_songs(
        &self,
        song_id: String,
        limit: u32,
    ) -> Result<Vec<CoOccurrence>, SnapshotError> {
        let snap = self.current()?;
        Ok(co(&snap, &song_id, limit))
    }

    /// この曲を歌った実績を、多い順に返す。
    ///
    /// `candidate_idol_ids` に公演の出演者を渡すとその中だけに絞れる (セトリ予想用)。
    /// 空なら全アイドルが対象。
    pub fn singers_for_song(
        &self,
        song_id: String,
        candidate_idol_ids: Vec<String>,
        limit: u32,
    ) -> Result<Vec<SingerTally>, SnapshotError> {
        let snap = self.current()?;
        Ok(singers(&snap, &song_id, &candidate_idol_ids, limit))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(store.co_occurring_songs("x".into(), 5), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.singers_for_song("x".into(), vec![], 5), Err(SnapshotError::NotLoaded)));
        assert!(matches!(
            store.song_performance_insights("x".into(), 5, 5),
            Err(SnapshotError::NotLoaded)
        ));
    }

    /// 束ねた口が、個別に呼んだ結果と同じものを返すこと。
    #[test]
    fn bundled_matches_the_individual_calls() {
        let store = SnapshotStore::new();
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        store.load(db).unwrap();
        let snap = store.current().unwrap();
        // 披露回数の多い曲を選ぶ
        let mut counts: std::collections::HashMap<u32, u32> = std::collections::HashMap::new();
        for it in &snap.setlist_items {
            *counts.entry(it.song).or_insert(0) += 1;
        }
        let (&top, _) = counts.iter().max_by_key(|(_, &n)| n).unwrap();
        let id = snap.songs[top as usize].id.clone();

        let bundled = store.song_performance_insights(id.clone(), 10, 10).unwrap();
        assert_eq!(bundled.co_occurring, store.co_occurring_songs(id.clone(), 10).unwrap());
        assert_eq!(bundled.singers, store.singers_for_song(id, vec![], 10).unwrap());
        assert!(!bundled.co_occurring.is_empty(), "よく演奏される曲に共起が無いのはおかしい");
    }
}
