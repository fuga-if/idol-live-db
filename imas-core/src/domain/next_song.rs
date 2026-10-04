//! 「次はこれ」— 曲が終わったあとに続けて流す曲を選ぶ。
//!
//! 選ぶ順は、根拠のはっきりしたものから:
//! 1. **よく一緒に演奏される曲** (同じ公演に来た回数。`performance_stats::CoOccurIndex`)
//! 2. **同じ人が歌う曲** (今の曲の原唱者の曲。新しい順)
//! 3. **同じブランドの曲** (披露回数の多い順)
//!
//! Apple Music で鳴らせない曲 (apple_music_id が無い) と派生曲 (parent_song_id がある。
//! リミックス・別バージョンが続くと同じ曲が流れているように聞こえる) は選ばない。
//! 流した曲は呼び出し側が `exclude` に積むので、同じ曲には戻らない。
//!
//! 理由は UI に出すので回数を添える (`together`)。過去の実績であって予言ではない。

use crate::domain::performance_stats::CoOccurIndex;
use crate::domain::snapshot::Snapshot;
use std::collections::HashSet;

/// なぜこの曲か。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum NextSongReason {
    /// 同じ公演で `together` 回演奏された。
    PerformedTogether { together: u32 },
    /// 今の曲の原唱者 `idol_id` が歌っている。
    SameSinger { idol_id: String },
    /// 同じブランドの曲。
    SameBrand,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct NextSongPick {
    pub song_id: String,
    pub reason: NextSongReason,
}

/// 共起の候補を見る上限 (鳴らせない曲・流した曲を飛ばしても足りる数)。
const CO_CANDIDATES: u32 = 60;

/// 今の曲 `current` のあとに流す曲を、よい順に最大 `limit` 件。
pub fn recommend_next(snap: &Snapshot, current: &str, exclude: &[String], limit: u32) -> Vec<NextSongPick> {
    let Some(&cur) = snap.song_index_by_id.get(current) else { return Vec::new() };
    let mut taken: HashSet<String> = exclude.iter().cloned().collect();
    taken.insert(current.to_string());
    let mut out: Vec<NextSongPick> = Vec::new();
    let limit = limit as usize;

    let playable = |song: u32| {
        let s = &snap.songs[song as usize];
        s.parent_song_id.is_none() && s.apple_music_id.as_deref().is_some_and(|id| !id.is_empty())
    };
    let mut push = |out: &mut Vec<NextSongPick>, song: u32, reason: NextSongReason| {
        let id = &snap.songs[song as usize].id;
        if out.len() < limit && playable(song) && taken.insert(id.clone()) {
            out.push(NextSongPick { song_id: id.clone(), reason });
        }
    };

    for co in CoOccurIndex::build(snap).co_occurring(snap, current, CO_CANDIDATES) {
        if let Some(&song) = snap.song_index_by_id.get(&co.song_id) {
            push(&mut out, song, NextSongReason::PerformedTogether { together: co.together });
        }
    }

    for link in snap.artists_by_song[cur as usize].iter().filter(|l| l.role == "original") {
        let idol_id = snap.idols[link.idol as usize].id.clone();
        for song_link in snap.songs_by_idol[link.idol as usize].iter().filter(|l| l.role == "original") {
            push(&mut out, song_link.song, NextSongReason::SameSinger { idol_id: idol_id.clone() });
        }
    }

    if let Some(brand) = snap.songs[cur as usize].brand_id.as_deref() {
        let mut same_brand: Vec<u32> = (0..snap.songs.len() as u32)
            .filter(|&s| snap.songs[s as usize].brand_id.as_deref() == Some(brand))
            .collect();
        same_brand.sort_by(|&a, &b| {
            snap.performance_counts[b as usize]
                .cmp(&snap.performance_counts[a as usize])
                .then_with(|| snap.songs[a as usize].id.cmp(&snap.songs[b as usize].id))
        });
        for song in same_brand {
            push(&mut out, song, NextSongReason::SameBrand);
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 披露回数の多い曲を 1 つ選ぶ (同梱 DB で確かめる)。
    fn popular_song(snap: &Snapshot) -> String {
        let (i, _) = snap.performance_counts.iter().enumerate().max_by_key(|(_, n)| **n).unwrap();
        snap.songs[i].id.clone()
    }

    #[test]
    fn picks_playable_non_variant_songs_and_skips_excluded() {
        let store = crate::test_support::bundle_store();
        let snap = store.current().unwrap();
        let current = popular_song(&snap);
        let picks = recommend_next(&snap, &current, &[], 10);
        assert_eq!(picks.len(), 10);
        assert!(picks.iter().all(|p| p.song_id != current));
        for p in &picks {
            let s = &snap.songs[snap.song_index_by_id[&p.song_id] as usize];
            assert!(s.parent_song_id.is_none());
            assert!(s.apple_music_id.as_deref().is_some_and(|id| !id.is_empty()));
        }
        // 先頭は共起 (よく演奏される曲には必ず共起がある)。
        assert!(matches!(picks[0].reason, NextSongReason::PerformedTogether { .. }));

        // 流した曲は外れて、次の候補が繰り上がる。
        let exclude = vec![picks[0].song_id.clone()];
        let again = recommend_next(&snap, &current, &exclude, 10);
        assert_eq!(again[0], picks[1]);
        // 重複しない。
        let ids: HashSet<_> = again.iter().map(|p| &p.song_id).collect();
        assert_eq!(ids.len(), again.len());
    }

    #[test]
    fn unknown_song_gives_nothing() {
        let store = crate::test_support::bundle_store();
        let snap = store.current().unwrap();
        assert!(recommend_next(&snap, "no_such_song", &[], 5).is_empty());
    }
}
