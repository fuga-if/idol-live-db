//! 習熟度の FFI 面。ロジックは domain::mastery。
//!
//! 1 画面ぶんの曲を射影 (`MasterySong`) で 1 回渡して、群の配列を受け取る。
//! 曲ごとに呼ぶと 3,000 曲で 3,000 回の境界越えになる。

use crate::domain::mastery::{
    MasteryAxis, MasteryBulkScope, MasteryGroup, MasteryGroupSort, MasteryProgressFilter,
    MasterySong, MasterySummary,
};

/// 習熟度の分母にする曲の絞り込み。この条件で `song_list` を引いた曲を `MasterySong` に詰める。
#[uniffi::export]
pub fn mastery_song_filter() -> crate::domain::song_list_queries::SongListFilter {
    crate::domain::mastery::mastery_song_filter()
}

#[uniffi::export]
pub fn build_mastery_groups(
    songs: Vec<MasterySong>,
    axis: MasteryAxis,
    steps: u8,
    sort: MasteryGroupSort,
    progress: MasteryProgressFilter,
    name_filter: String,
) -> Vec<MasteryGroup> {
    crate::domain::mastery::build_mastery_groups(&songs, axis, steps, sort, progress, &name_filter)
}

#[uniffi::export]
pub fn mastery_summary(songs: Vec<MasterySong>, steps: u8) -> MasterySummary {
    crate::domain::mastery::mastery_summary(&songs, steps)
}

#[uniffi::export]
pub fn next_mastery_level(current: u8, steps: u8) -> u8 {
    crate::domain::mastery::next_mastery_level(current, steps)
}

#[uniffi::export]
pub fn remap_mastery_level(level: u8, old_steps: u8, new_steps: u8) -> u8 {
    crate::domain::mastery::remap_mastery_level(level, old_steps, new_steps)
}

#[uniffi::export]
pub fn mastery_bulk_targets(
    song_ids: Vec<String>,
    levels: Vec<u8>,
    scope: MasteryBulkScope,
) -> Vec<String> {
    crate::domain::mastery::mastery_bulk_targets(&song_ids, &levels, scope)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str, series: &str, level: u8) -> MasterySong {
        MasterySong {
            song_id: id.into(),
            title: id.into(),
            series_group: Some(series.into()),
            cd_series: None,
            unit_name: None,
            singer_label: None,
            release_date: None,
            level,
            collected: false,
        }
    }

    /// FFI 関数が domain へ委譲していること (値渡し = FFI と同じ所有権移動)。
    #[test]
    fn delegates_to_domain() {
        let songs = vec![song("a", "CANVAS", 4), song("b", "CANVAS", 0)];
        let expected = crate::domain::mastery::build_mastery_groups(
            &songs, MasteryAxis::Series, 4,
            MasteryGroupSort::SongCount, MasteryProgressFilter::All, "");
        assert_eq!(
            build_mastery_groups(songs.clone(), MasteryAxis::Series, 4,
                                 MasteryGroupSort::SongCount, MasteryProgressFilter::All, "".into()),
            expected);
        assert_eq!(expected[0].percent, 50);

        assert_eq!(mastery_summary(songs, 4).total, 2);
        assert_eq!(next_mastery_level(4, 4), 4);
        assert_eq!(remap_mastery_level(4, 4, 3), 3);
        assert_eq!(
            mastery_bulk_targets(
                vec!["a".into(), "b".into()],
                vec![0, 2],
                MasteryBulkScope::UnsetOnly
            ),
            vec!["a".to_string()]
        );
    }
}
