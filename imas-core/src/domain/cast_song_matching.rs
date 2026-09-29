//! 出演者の顔ぶれで歌える曲を探す。
//!
//! # なぜ要るか
//!
//! 「この 16 人の公演なら何が歌えるか」は、曲一覧の絞り込み (`list_songs --idol_id`) では
//! 出せない。あれは「その人が入っている曲」を返すので、**残りの原唱者がその日いるか**を
//! 見ていない。セトリを組むときに欲しいのは逆で、「原唱者が全員そろっている曲」。
//!
//! あわせて**あと何人足りないか**も返す。`max_missing` を 1 にすると「1 人呼べば歌える曲」が
//! 出るので、「この曲をやるには誰が要るか」という向きにも使える。足りない人を返さずに
//! 0 人の曲だけ返すと、編成を動かす判断ができない。
//!
//! # 歌えるかどうかは原唱者で見る
//!
//! 実際のライブでは原唱者以外もカバーする (主演公演では歌唱が原唱どおりなのは 2 割)。
//! それでもここが原唱者を見るのは、**カバーは誰でも歌えてしまい絞り込みにならない**から。
//! 「その顔ぶれの持ち歌」を出すのがこの関数の役目で、カバーまで含めた可能性は呼び手が広げる。

use crate::domain::snapshot::Snapshot;
use crate::domain::song_list_queries::is_hidden_variant;
use std::collections::HashSet;

/// 当たった 1 曲。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CastSongHit {
    pub song: u32,
    /// 原唱者 (idols の添字)。`song_artists` の並びを保つ。
    pub artists: Vec<u32>,
    /// 原唱者のうち、渡した顔ぶれにいない人。空なら その日だけで成立する。
    pub missing: Vec<u32>,
    pub performances: u32,
}

/// 顔ぶれで歌える曲。
///
/// - `cast` … 出演者 (idols の添字)
/// - `max_missing` … 原唱者が何人まで欠けてよいか。0 なら完全にそろう曲だけ
/// - `min_artists` / `max_artists` … 原唱者の人数で絞る (全体曲を外したいときに使う)
///
/// 並びは 欠員の少ない順 → 披露回数の多い順 → 曲 id 順 (同数を決定的に)。
/// 派生曲 (`(◯◯ Ver.)` 等) は外す — 一覧が同じ曲の版違いで埋まって読めなくなる。
pub fn songs_for_cast(
    snap: &Snapshot,
    cast: &[u32],
    max_missing: u32,
    min_artists: Option<u32>,
    max_artists: Option<u32>,
    limit: usize,
) -> Vec<CastSongHit> {
    let present: HashSet<u32> = cast.iter().copied().collect();

    let mut hits: Vec<CastSongHit> = (0..snap.songs.len() as u32)
        .filter(|&song| !is_hidden_variant(&snap.songs[song as usize]))
        .filter_map(|song| {
            let artists: Vec<u32> = snap.artists_by_song[song as usize]
                .iter()
                .filter(|l| l.role == "original")
                .map(|l| l.idol)
                .collect();
            if artists.is_empty() {
                return None;
            }
            let n = artists.len() as u32;
            if min_artists.is_some_and(|m| n < m) || max_artists.is_some_and(|m| n > m) {
                return None;
            }
            let missing: Vec<u32> =
                artists.iter().copied().filter(|a| !present.contains(a)).collect();
            if missing.len() as u32 > max_missing {
                return None;
            }
            Some(CastSongHit {
                song,
                artists,
                missing,
                performances: snap.performance_counts[song as usize],
            })
        })
        .collect();

    hits.sort_by(|a, b| {
        a.missing
            .len()
            .cmp(&b.missing.len())
            .then(b.performances.cmp(&a.performances))
            .then(snap.songs[a.song as usize].id.cmp(&snap.songs[b.song as usize].id))
    });
    hits.truncate(limit);
    hits
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn idx(snap: &Snapshot, ids: &[&str]) -> Vec<u32> {
        ids.iter().map(|id| snap.idol_index_by_id[*id]).collect()
    }

    #[test]
    fn 顔ぶれで完全にそろう曲が出る() {
        let s = bundle_snapshot();
        let cast = idx(s, &["ml_伊吹翼", "ml_春日未来", "ml_最上静香"]);
        let hits = songs_for_cast(s, &cast, 0, Some(2), Some(5), 50);
        assert!(!hits.is_empty());
        for h in &hits {
            assert!(h.missing.is_empty(), "欠員 0 で頼んだのに欠けている");
            for a in &h.artists {
                assert!(cast.contains(a), "顔ぶれ外の原唱者が混ざっている");
            }
        }
        // ストロベリーポップムーンの 2 曲はこの 3 人ちょうど。
        let titles: Vec<&str> =
            hits.iter().map(|h| s.songs[h.song as usize].title.as_str()).collect();
        assert!(titles.contains(&"ABSOLUTE RUN!!!"), "{titles:?}");
        assert!(titles.contains(&"Be proud"), "{titles:?}");
    }

    #[test]
    fn 欠員を許すと候補が増え誰が足りないかが分かる() {
        let s = bundle_snapshot();
        let cast = idx(s, &["ml_伊吹翼", "ml_春日未来", "ml_最上静香"]);
        let strict = songs_for_cast(s, &cast, 0, Some(2), Some(5), 200);
        let loose = songs_for_cast(s, &cast, 1, Some(2), Some(5), 200);
        assert!(loose.len() > strict.len(), "欠員 1 を許しても増えない");
        // 欠員ありの行は「誰が足りないか」を必ず持つ。
        let with_missing: Vec<_> = loose.iter().filter(|h| !h.missing.is_empty()).collect();
        assert!(!with_missing.is_empty());
        for h in with_missing {
            assert_eq!(h.missing.len(), 1);
            assert!(!cast.contains(&h.missing[0]));
        }
    }

    #[test]
    fn 人数で全体曲を外せる() {
        let s = bundle_snapshot();
        let cast: Vec<u32> = (0..s.idols.len() as u32).collect(); // 全員
        let small = songs_for_cast(s, &cast, 0, None, Some(5), 500);
        for h in &small {
            assert!(h.artists.len() <= 5, "{} 人の曲が混ざった", h.artists.len());
        }
    }

    #[test]
    fn 並びは欠員の少ない順で次に披露回数() {
        let s = bundle_snapshot();
        let cast = idx(s, &["ml_伊吹翼", "ml_春日未来", "ml_最上静香"]);
        let hits = songs_for_cast(s, &cast, 1, Some(2), Some(5), 50);
        let keys: Vec<(usize, i64)> =
            hits.iter().map(|h| (h.missing.len(), -(h.performances as i64))).collect();
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted, "{keys:?}");
    }
}
