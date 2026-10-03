//! 曲送り (前の曲・次の曲) とプレイリストの並びの規則。
//!
//! プレイリストは端末ローカル唯一データ (`playlists` / `playlist_items`)。並びは曲の id だけで持つ。
//! 鳴らすのは Apple Music (iOS の ApplicationMusicPlayer / Android の MusicKit) で、
//! ここは「どこへ送るか」「何を足すか」だけを決める。

/// 「前の曲」で、曲の頭へ戻すだけにする境目 (ms)。これより進んでいれば頭出し (音楽アプリの慣習)。
pub const RESTART_THRESHOLD_MS: i64 = 3_000;

/// 「前の曲」を押したときに鳴らす曲の添字。今の曲の頭出しなら `index` をそのまま返す。
pub fn previous_index(index: u32, position_ms: i64) -> u32 {
    if index == 0 || position_ms > RESTART_THRESHOLD_MS {
        index
    } else {
        index - 1
    }
}

/// 「次の曲」の添字。最後の曲なら `None` (先頭へは戻らない)。
pub fn next_index(index: u32, len: u32) -> Option<u32> {
    let next = index.checked_add(1)?;
    (next < len).then_some(next)
}

/// プレイリストに曲を足した後の並び。既にある曲は足さない (同じ曲を 2 回入れない)。
/// 足す側の中の重複も 1 つにまとめる。並びは既存の後ろに、足した順で付ける。
pub fn append_songs(existing: &[String], adding: &[String]) -> Vec<String> {
    let mut out = existing.to_vec();
    for id in adding {
        if !out.contains(id) {
            out.push(id.clone());
        }
    }
    out
}

/// 曲を 1 つ動かした後の並び (`from` の曲を `to` の位置へ)。範囲外なら元のまま。
pub fn move_song(ids: &[String], from: u32, to: u32) -> Vec<String> {
    let (from, to) = (from as usize, to as usize);
    let mut out = ids.to_vec();
    if from >= out.len() || to >= out.len() {
        return out;
    }
    let id = out.remove(from);
    out.insert(to, id);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn previous_restarts_when_past_threshold_or_first() {
        assert_eq!(previous_index(2, 3_001), 2);
        assert_eq!(previous_index(2, 3_000), 1);
        assert_eq!(previous_index(2, 0), 1);
        assert_eq!(previous_index(0, 0), 0);
    }

    #[test]
    fn next_stops_at_end() {
        assert_eq!(next_index(0, 3), Some(1));
        assert_eq!(next_index(2, 3), None);
        assert_eq!(next_index(0, 0), None);
        assert_eq!(next_index(u32::MAX, u32::MAX), None);
    }

    #[test]
    fn append_skips_duplicates() {
        assert_eq!(append_songs(&ids(&["a", "b"]), &ids(&["b", "c", "c"])), ids(&["a", "b", "c"]));
    }

    #[test]
    fn move_song_reorders_and_ignores_out_of_range() {
        assert_eq!(move_song(&ids(&["a", "b", "c"]), 0, 2), ids(&["b", "c", "a"]));
        assert_eq!(move_song(&ids(&["a", "b", "c"]), 2, 0), ids(&["c", "a", "b"]));
        assert_eq!(move_song(&ids(&["a", "b"]), 5, 0), ids(&["a", "b"]));
    }
}
