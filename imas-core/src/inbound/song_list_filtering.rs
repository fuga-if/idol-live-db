//! 楽曲一覧絞り込みの FFI 面。ロジックは domain::song_list_filtering。
//!
//! エンティティ全体ではなく射影 (`SongListFilterEntry`) を受け、採用 index 列を返す
//! (呼び出し側が自国の配列を index で引き直す)。1 ユーザー操作 = 1 呼び出し。

use crate::domain::song_list_filtering::{SongListFilterCriteria, SongListFilterEntry};

#[uniffi::export]
pub fn filter_song_list(entries: Vec<SongListFilterEntry>, criteria: SongListFilterCriteria) -> Vec<u32> {
    crate::domain::song_list_filtering::filter_song_list(&entries, &criteria)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::song_list_filtering::SongCollectMode;
    use std::collections::HashMap;

    /// 回帰 (2026-08-25 委譲未完結): inbound の FFI 関数が domain へ正しく委譲し、
    /// アプリ側ラッパ (SongListFiltering.swift / SongListViewModel.kt) が期待する
    /// 「採用 index 列」を返すことを、値渡し (FFI と同じ所有権移動) で確認する。
    #[test]
    fn filter_song_list_delegates_to_domain() {
        let entries = vec![
            SongListFilterEntry { song_id: "s1".into(), title: "曲1".into(), title_kana: Some("あ".into()) },
            SongListFilterEntry { song_id: "s2".into(), title: "曲2".into(), title_kana: Some("い".into()) },
            SongListFilterEntry { song_id: "s3".into(), title: "曲3".into(), title_kana: None },
        ];
        let criteria = SongListFilterCriteria {
            collect_mode: SongCollectMode::Collected,
            collected_ids: vec!["s1".into(), "s3".into()],
            require_favorite: false,
            favorite_ids: vec![],
            require_note: false,
            note_ids: vec![],
            require_my_pick: false,
            my_pick_song_ids: vec![],
            tag_song_ids: None,
            rank_by_tag_votes: false,
            tag_vote_counts: HashMap::new(),
        };
        let expected =
            crate::domain::song_list_filtering::filter_song_list(&entries, &criteria);
        assert_eq!(filter_song_list(entries, criteria), expected);
        assert_eq!(expected, vec![0, 2]);
    }
}
