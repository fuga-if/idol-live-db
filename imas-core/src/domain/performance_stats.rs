//! 過去の披露実績から出す**共起と歌唱者の統計**。
//!
//! セトリ 13,777 件・出演者 60,383 件をスナップショットから走査して、
//! 「この曲とよく一緒に演奏される曲」「この曲を歌うのは誰が多いか」を出す。
//! 全曲ぶん回しても数十ミリ秒で終わるので、事前計算も保存もしない
//! (保存すると master 更新のたびに作り直す手間と、古い値を配る事故が増える)。
//!
//! # 何に使うか
//!
//! - 曲詳細の「この曲の日はだいたいこれも来る」
//! - セトリ予想で「この曲を誰が歌うか」の目安 (投票機能の初期表示・並べ替え)
//!
//! # 予想への使い方の注意
//!
//! ここが返すのは**過去の実績**であって予言ではない。新曲・初披露・
//! 特別編成では外れる。UI では「これまで n 回」のように**根拠の回数を必ず添える**こと。

use crate::domain::snapshot::Snapshot;
use std::collections::HashMap;

/// 一緒に演奏された回数。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CoOccurrence {
    /// 相手の曲 id。
    pub song_id: String,
    /// 同じ公演で一緒に演奏された公演数。
    pub together: u32,
    /// 相手の曲の総披露公演数 (分母。together/performances が「一緒に来る率」)。
    pub performances: u32,
}

/// その曲を歌った実績。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SingerTally {
    pub idol_id: String,
    /// その曲を歌った回数。
    pub times: u32,
    /// その曲の総披露回数 (分母)。
    pub total: u32,
}

/// 「一緒に来る曲」を数えるための前計算。
///
/// 素直に書くと 1 曲ぶん求めるのに全公演 (1,341) を舐めることになり、
/// 全 3,153 曲ぶん出す Web の書き出しでは 420 万回の走査 + 公演ごとの整列になる。
/// 公演の曲集合と、曲ごとの公演一覧を **1 度だけ**作って共有する。
///
/// 1 曲 1 回の呼び出しなら [`co_occurring_songs`] が内部でこれを作る。
pub struct CoOccurIndex {
    /// 公演ごとの、重複を除いた曲添字 (昇順)。
    songs_by_show: Vec<Vec<u32>>,
    /// 曲ごとの、その曲が演奏された公演添字 (昇順・重複なし)。
    /// 長さがそのまま「何公演で演奏されたか」。
    shows_by_song: Vec<Vec<u32>>,
}

impl CoOccurIndex {
    pub fn build(snap: &Snapshot) -> Self {
        let songs_by_show: Vec<Vec<u32>> = snap
            .setlist_items_by_show
            .iter()
            .map(|items| {
                let mut songs: Vec<u32> =
                    items.iter().map(|&i| snap.setlist_items[i as usize].song).collect();
                // 1 公演で 2 回演奏されても 1 と数える (アンコール再演で二重計上しない)。
                songs.sort_unstable();
                songs.dedup();
                songs
            })
            .collect();

        let mut shows_by_song = vec![Vec::new(); snap.songs.len()];
        for (show, songs) in songs_by_show.iter().enumerate() {
            for &song in songs {
                shows_by_song[song as usize].push(show as u32);
            }
        }
        Self { songs_by_show, shows_by_song }
    }

    /// その曲が演奏された公演数。
    pub fn performances(&self, song: u32) -> u32 {
        self.shows_by_song.get(song as usize).map_or(0, |shows| shows.len() as u32)
    }

    /// 対象曲と同じ公演に来た曲の上位。
    pub fn co_occurring(&self, snap: &Snapshot, song_id: &str, limit: u32) -> Vec<CoOccurrence> {
        let Some(&target) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
        let Some(shows) = self.shows_by_song.get(target as usize) else { return Vec::new() };

        // 対象曲が居た公演だけを見る (全公演を舐めない)。
        let mut together: HashMap<u32, u32> = HashMap::new();
        for &show in shows {
            for &song in &self.songs_by_show[show as usize] {
                if song != target {
                    *together.entry(song).or_insert(0) += 1;
                }
            }
        }

        let mut out: Vec<CoOccurrence> = together
            .into_iter()
            .map(|(song, n)| CoOccurrence {
                song_id: snap.songs[song as usize].id.clone(),
                together: n,
                performances: self.performances(song),
            })
            .collect();
        // 回数の多い順。同数は曲 id 順で決定的に。
        out.sort_by(|a, b| b.together.cmp(&a.together).then(a.song_id.cmp(&b.song_id)));
        out.truncate(limit as usize);
        out
    }
}

/// 曲ごとの「一緒に来る曲」上位。
///
/// 同じ公演に両方あった公演数で数える。1 公演で 2 回演奏されても 1 と数える
/// (アンコール再演で二重計上しないため)。
///
/// **複数の曲について求めるなら [`CoOccurIndex`] を 1 度作って使い回すこと。**
/// この関数は呼ぶたびに前計算をやり直す。
pub fn co_occurring_songs(snap: &Snapshot, song_id: &str, limit: u32) -> Vec<CoOccurrence> {
    CoOccurIndex::build(snap).co_occurring(snap, song_id, limit)
}

/// 曲ごとの「歌った人」上位。
///
/// `candidate_idol_ids` を渡すと、その集合に絞る (公演の出演者だけを見たいとき)。
/// 空なら全アイドルが対象。
pub fn singers_for_song(
    snap: &Snapshot,
    song_id: &str,
    candidate_idol_ids: &[String],
    limit: u32,
) -> Vec<SingerTally> {
    let Some(&target) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
    let candidates: Option<std::collections::HashSet<u32>> = if candidate_idol_ids.is_empty() {
        None
    } else {
        Some(
            candidate_idol_ids
                .iter()
                .filter_map(|id| snap.idol_index_by_id.get(id).copied())
                .collect(),
        )
    };

    // その曲の披露だけを見る。全 13,762 件の setlist_items を舐めると、
    // 3,153 曲ぶん出す Web の書き出しで 4,300 万回の走査になる。
    let items = snap.setlist_items_by_song.get(target as usize).map_or(&[][..], Vec::as_slice);
    let total = items.len() as u32;
    let mut tally: HashMap<u32, u32> = HashMap::new();
    for &i in items {
        for &idol in &snap.performers_by_item[i as usize] {
            if candidates.as_ref().is_none_or(|c| c.contains(&idol)) {
                *tally.entry(idol).or_insert(0) += 1;
            }
        }
    }

    let mut out: Vec<SingerTally> = tally
        .into_iter()
        .map(|(idol, times)| SingerTally {
            idol_id: snap.idols[idol as usize].id.clone(),
            times,
            total,
        })
        .collect();
    out.sort_by(|a, b| b.times.cmp(&a.times).then(a.idol_id.cmp(&b.idol_id)));
    out.truncate(limit as usize);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;

    fn snap() -> Snapshot {
        load_snapshot(&format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR")))
            .expect("bundle DB")
    }

    #[test]
    fn co_occurrence_is_ordered_and_bounded() {
        let s = snap();
        // 披露回数の多い曲を 1 つ選ぶ
        let mut counts: HashMap<u32, u32> = HashMap::new();
        for it in &s.setlist_items { *counts.entry(it.song).or_insert(0) += 1; }
        let (&top, _) = counts.iter().max_by_key(|(_, &n)| n).unwrap();
        let song_id = s.songs[top as usize].id.clone();

        let t = std::time::Instant::now();
        let got = co_occurring_songs(&s, &song_id, 10);
        println!("STATS 共起 {:?} → {}件", t.elapsed(), got.len());

        assert!(!got.is_empty(), "よく演奏される曲に共起が無いのはおかしい");
        assert!(got.len() <= 10);
        // 降順に並んでいる
        for w in got.windows(2) { assert!(w[0].together >= w[1].together); }
        // 自分自身は入らない
        assert!(got.iter().all(|c| c.song_id != song_id));
        // 分母は「一緒に来た回数」以上
        assert!(got.iter().all(|c| c.performances >= c.together));
    }

    #[test]
    fn singers_are_ordered_and_have_a_denominator() {
        let s = snap();
        // 出演者が紐づいている披露を 1 つ選ぶ
        let idx = (0..s.setlist_items.len())
            .find(|&i| s.performers_by_item[i].len() >= 2)
            .expect("出演者つきの披露があるはず");
        let song_id = s.songs[s.setlist_items[idx].song as usize].id.clone();

        let got = singers_for_song(&s, &song_id, &[], 10);
        assert!(!got.is_empty());
        for w in got.windows(2) { assert!(w[0].times >= w[1].times); }
        assert!(got.iter().all(|t| t.total >= t.times), "分母が回数を下回っている");
    }

    #[test]
    fn candidates_narrow_the_result() {
        let s = snap();
        let idx = (0..s.setlist_items.len())
            .find(|&i| s.performers_by_item[i].len() >= 2)
            .unwrap();
        let song_id = s.songs[s.setlist_items[idx].song as usize].id.clone();
        let all = singers_for_song(&s, &song_id, &[], 50);
        let one = vec![all[0].idol_id.clone()];
        let narrowed = singers_for_song(&s, &song_id, &one, 50);
        assert_eq!(narrowed.len(), 1);
        assert_eq!(narrowed[0].idol_id, all[0].idol_id);
    }

    #[test]
    fn unknown_ids_return_nothing_instead_of_panicking() {
        let s = snap();
        assert!(co_occurring_songs(&s, "存在しない曲", 5).is_empty());
        assert!(singers_for_song(&s, "存在しない曲", &[], 5).is_empty());
    }

    #[test]
    fn results_are_deterministic() {
        let s = snap();
        let mut counts: HashMap<u32, u32> = HashMap::new();
        for it in &s.setlist_items { *counts.entry(it.song).or_insert(0) += 1; }
        let (&top, _) = counts.iter().max_by_key(|(_, &n)| n).unwrap();
        let id = s.songs[top as usize].id.clone();
        assert_eq!(co_occurring_songs(&s, &id, 10), co_occurring_songs(&s, &id, 10));
    }
}
