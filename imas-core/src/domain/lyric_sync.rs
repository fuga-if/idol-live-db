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

/// 「ここ好き」の山 (シークバーに重ねる)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricLikeHeat {
    /// 曲を等分した各区間の高さ (0.0〜1.0)。山が無ければ空。
    pub levels: Vec<f32>,
    /// いちばん好かれている行の歌い出し (ms)。おすすめ地点。
    pub peak_ms: Option<i64>,
}

/// 最後の行がどこまで続くとみなすか (次の行が無いので長さが分からない)。
const LAST_LINE_SPAN_MS: i64 = 8_000;

/// 行ごとの「ここ好き」人数を、曲の時間軸の山にする。
///
/// 区間の高さは「その時刻に歌われている行の人数」。行の長さで割らない —
/// 長い行ほど薄まると、好かれているのに山が低く見える。隣と平して角を取り、最大で割る。
/// 時刻の無い行の人数は置き場所が無いので数えない。
pub fn like_heat(starts: &[Option<i64>], counts: &[u32], duration_ms: i64, buckets: u32) -> LyricLikeHeat {
    let empty = LyricLikeHeat { levels: vec![], peak_ms: None };
    if duration_ms <= 0 || buckets == 0 {
        return empty;
    }
    // 時刻のある行を時刻順に。
    let mut timed: Vec<(i64, u32)> = starts
        .iter()
        .zip(counts.iter().chain(std::iter::repeat(&0)))
        .filter_map(|(s, c)| s.map(|s| (s, *c)))
        .collect();
    timed.sort_by_key(|(s, _)| *s);
    if timed.iter().all(|(_, c)| *c == 0) {
        return empty;
    }
    let n = buckets as usize;
    let mut raw = vec![0f32; n];
    for (i, (start, count)) in timed.iter().enumerate() {
        if *count == 0 {
            continue;
        }
        let end = timed
            .get(i + 1)
            .map(|(s, _)| *s)
            .unwrap_or(start + LAST_LINE_SPAN_MS)
            .min(duration_ms);
        if end <= *start {
            continue;
        }
        let from = ((*start as f64 / duration_ms as f64) * n as f64).floor().max(0.0) as usize;
        let to = ((end as f64 / duration_ms as f64) * n as f64).ceil() as usize;
        for b in raw.iter_mut().take(to.min(n)).skip(from.min(n)) {
            *b = b.max(*count as f32);
        }
    }
    let smoothed: Vec<f32> = (0..n)
        .map(|i| {
            let prev = if i > 0 { raw[i - 1] } else { raw[i] };
            let next = if i + 1 < n { raw[i + 1] } else { raw[i] };
            (prev + 2.0 * raw[i] + next) / 4.0
        })
        .collect();
    let max = smoothed.iter().cloned().fold(0f32, f32::max);
    if max <= 0.0 {
        return empty;
    }
    // おすすめ地点: 人数が最大の行 (同数なら早い方) の歌い出し。
    let peak_ms = timed
        .iter()
        .filter(|(s, _)| *s < duration_ms)
        .fold(None::<(i64, u32)>, |best, &(s, c)| match best {
            Some((_, bc)) if bc >= c => best,
            _ if c > 0 => Some((s, c)),
            _ => best,
        })
        .map(|(s, _)| s);
    LyricLikeHeat { levels: smoothed.iter().map(|v| v / max).collect(), peak_ms }
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

    #[test]
    fn like_heat_puts_peak_on_most_liked_line() {
        // 0-10s: 1 人 / 10-20s: 3 人 / 20s-: 時刻なしの行は数えない。
        let starts = [Some(0), Some(10_000), None];
        let counts = [1, 3, 9];
        let heat = like_heat(&starts, &counts, 40_000, 4);
        assert_eq!(heat.peak_ms, Some(10_000));
        assert_eq!(heat.levels.len(), 4);
        let top = heat.levels.iter().cloned().fold(0f32, f32::max);
        assert!((top - 1.0).abs() < 1e-6);
        assert_eq!(heat.levels.iter().position(|v| *v == top), Some(1));
        // 最後の行の後ろ (18s 以降) は低い。
        assert!(heat.levels[3] < heat.levels[1]);
    }

    #[test]
    fn like_heat_empty_without_likes_or_duration() {
        assert_eq!(like_heat(&[Some(0)], &[0], 10_000, 8).levels, Vec::<f32>::new());
        assert_eq!(like_heat(&[Some(0)], &[2], 0, 8).peak_ms, None);
    }
}
