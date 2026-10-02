//! 歌詞と再生位置の連動 (今どの行か・次に記録する行) と、行ごとの「ここ好き」。
//!
//! # 再生位置はユーザーが記録する
//!
//! 歌詞行の `startMs` は配信元から取れない (Apple Music の同期歌詞は公開 API が無い)。
//! フル再生を聴きながら行をタップして記録してもらい、`PUT /songs/:id/timings` で共有する。
//! 30 秒試聴は曲のどこを切り出したか分からないので、連動はフル再生だけ。
//!
//! # ここ好きは行 ID だけを持つ
//!
//! 歌詞本文は端末に保存できない (JASRAC 許諾の条件、`Models/Lyrics.swift` 冒頭)。
//! 印は `user_marks` の曲 1 行に**行 ID の並び**として入れる。本文は 1 文字も入らない。

/// 行の種別 (`lyric` / `marker` / `blank`)。未知の値は本文として扱う (iOS の `LyricLineKind` と同じ)。
fn is_recordable(kind: &str) -> bool {
    kind != "blank"
}

/// いま歌われている行の添字。再生位置より前に始まる行のうち、**始まりが最も遅い行**。
///
/// 表示順ではなく時刻で選ぶのは、記録の打ち間違いで時刻が前後していても
/// 今の位置に一番近い行を指すため。同じ時刻の行が並んだら後ろの行。
/// 最初の記録より前 (イントロ) は `None`。
pub fn active_line(starts: &[Option<i64>], position_ms: i64) -> Option<u32> {
    let mut best: Option<(i64, usize)> = None;
    for (i, start) in starts.iter().enumerate() {
        let Some(s) = *start else { continue };
        if s > position_ms {
            continue;
        }
        if best.map_or(true, |(b, _)| s >= b) {
            best = Some((s, i));
        }
    }
    best.map(|(_, i)| i as u32)
}

/// 連動できるだけ記録があるか。2 行以上に時刻が入っていれば追従する
/// (1 行だけでは「今どこか」が決まらない)。
pub fn has_timing(starts: &[Option<i64>]) -> bool {
    starts.iter().filter(|s| s.is_some()).count() >= 2
}

/// 記録モードで次にタップしてもらう行。`after` の次から数えて最初の記録対象 (空行以外)。
/// `after` が `None` なら先頭から。もう無ければ `None`。
pub fn next_recordable(kinds: &[String], after: Option<u32>) -> Option<u32> {
    let from = after.map_or(0, |a| a as usize + 1);
    (from..kinds.len())
        .find(|&i| is_recordable(&kinds[i]))
        .map(|i| i as u32)
}

/// 保存値の区切り。行 ID は `ll_<uuid>` なので現れない。
const SEP: char = ',';

/// 保存値 (`user_marks.text_value`) を行 ID の並びに戻す。空要素は捨てる。
pub fn parse_likes(stored: Option<&str>) -> Vec<String> {
    stored
        .unwrap_or("")
        .split(SEP)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect()
}

/// 行の「ここ好き」を付け外しした後の保存値。1 つも無くなれば `None` (行ごと消す)。
pub fn toggle_like(stored: Option<&str>, line_id: &str) -> Option<String> {
    let mut ids = parse_likes(stored);
    if let Some(pos) = ids.iter().position(|id| id == line_id) {
        ids.remove(pos);
    } else if !line_id.is_empty() && !line_id.contains(SEP) {
        ids.push(line_id.to_string());
    }
    if ids.is_empty() {
        None
    } else {
        Some(ids.join(&SEP.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_line_picks_latest_start_not_after_position() {
        let starts = [None, Some(1000), Some(5000), None, Some(9000)];
        assert_eq!(active_line(&starts, 0), None);
        assert_eq!(active_line(&starts, 999), None);
        assert_eq!(active_line(&starts, 1000), Some(1));
        assert_eq!(active_line(&starts, 8999), Some(2));
        assert_eq!(active_line(&starts, 60_000), Some(4));
    }

    #[test]
    fn active_line_tolerates_out_of_order_records() {
        // 3 行目を打ち間違えて 2 行目より前の時刻にした。
        let starts = [Some(1000), Some(5000), Some(4000)];
        assert_eq!(active_line(&starts, 4500), Some(2));
        assert_eq!(active_line(&starts, 6000), Some(1));
        // 同時刻は後ろの行。
        assert_eq!(active_line(&[Some(10), Some(10)], 10), Some(1));
    }

    #[test]
    fn has_timing_needs_two_lines() {
        assert!(!has_timing(&[None, Some(1)]));
        assert!(has_timing(&[Some(0), None, Some(1)]));
    }

    #[test]
    fn next_recordable_skips_blank() {
        let kinds: Vec<String> = ["marker", "lyric", "blank", "lyric"].iter().map(|s| s.to_string()).collect();
        assert_eq!(next_recordable(&kinds, None), Some(0));
        assert_eq!(next_recordable(&kinds, Some(0)), Some(1));
        assert_eq!(next_recordable(&kinds, Some(1)), Some(3));
        assert_eq!(next_recordable(&kinds, Some(3)), None);
    }

    #[test]
    fn likes_round_trip() {
        assert_eq!(parse_likes(None), Vec::<String>::new());
        assert_eq!(parse_likes(Some(" a, ,b ")), vec!["a", "b"]);
        let one = toggle_like(None, "ll_1");
        assert_eq!(one.as_deref(), Some("ll_1"));
        let two = toggle_like(one.as_deref(), "ll_2");
        assert_eq!(two.as_deref(), Some("ll_1,ll_2"));
        assert_eq!(toggle_like(two.as_deref(), "ll_1").as_deref(), Some("ll_2"));
        assert_eq!(toggle_like(Some("ll_2"), "ll_2"), None);
        // 区切りを含む id は入れない (並びが壊れる)。
        assert_eq!(toggle_like(None, "a,b"), None);
    }
}
