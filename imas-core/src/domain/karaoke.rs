//! カラオケモード: カラオケ音源に合わせて、手元の歌詞・コール・歌い分けを流す時計と、
//! 「次に自分が歌うまで何秒」「この先 20 秒に誰が歌うか」の計算。
//!
//! # 時計
//!
//! 行とコールの時刻 (`startMs`) は Apple Music の原曲に合わせて記録したもの。カラオケ音源
//! (CD の off vocal) は原曲と同じ尺なので、「曲のどこが今か」さえ決まればそのまま使える。
//! 時計は端末の単調時計に対して `曲の位置 = 合わせた位置 + (今 − 合わせた時刻) × 速さ + 手のずらし`。
//!
//! 合わせ方は 2 つ:
//! - 耳 (ShazamKit): 鳴っている音を照合して曲の位置を聞く。数十秒おきに聞き直して、
//!   小さなずれは半分ずつ寄せ (急に飛ばさない)、大きく外れた値は 2 回続けて同じだったときだけ採る。
//! - 手: 行の歌い出しでタップ (その行の時刻 = 今)。2 回目以降は 2 点の間隔から速さも直す。
//!
//! 手のずらし (左右スワイプ) は「コールを少し早めに見たい」などの好みなので、耳の補正では消さない。
//! タップは「この行が今」という絶対の合わせなので、ずらしも 0 に戻す。

use std::cmp::Ordering;

use crate::domain::lyric_sync;

/// 速さの補正を信じる下限・上限。off vocal は原曲と同じ速さなので、ずれは機械の揺れか
/// カラオケ機のテンポ変更 (数 %) くらい。外れたら打ち間違いとみて速さは変えない。
const RATE_MIN: f64 = 0.9;
const RATE_MAX: f64 = 1.1;
/// 速さを出すのは、タップした行が今の時計の予測にこれ以内で合っていたときだけ
/// (大きく外れたタップは「別の行を叩いた / 前の合わせが違っていた」で、速さの材料にならない)。
const RATE_TAP_AGREE_MS: i64 = 1_500;
/// 速さを 2 点から出すのに要る最短の間隔。近い 2 点だとタップの揺れ (±0.2 秒) が速さに化ける。
const RATE_MIN_SPAN_MS: i64 = 20_000;
/// 耳で聞いた位置と時計の差がこれ以下なら直さない (照合そのものの揺れ)。
const HEARD_KEEP_MS: i64 = 150;
/// これ以下の差は半分ずつ寄せる。これより大きいと外れ値の疑いがあるので確かめる。
const HEARD_EASE_MS: i64 = 2_500;
/// 外れ値を 2 回目で採るときの、1 回目との食い違いの許し。
const HEARD_CONFIRM_MS: i64 = 1_000;
/// 左右スワイプのずらしの上限 (±)。
const NUDGE_LIMIT_MS: i64 = 5_000;
/// 自分の番の数えを出し始める残り時間。
pub const TURN_COUNTDOWN_MS: i64 = 8_000;
/// 数えの四角の数 (残り秒の切り上げ、ここで頭打ち)。
const TURN_SQUARES: u32 = 4;
/// 帯で 1 行が続くとみなす長さの上限 (間奏の前の行が間奏ぶん伸びないように)。
const LANE_LINE_CAP_MS: i64 = 10_000;

/// カラオケの時計。`position` で今の曲の位置 (ms) を出す。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct KaraokeClock {
    /// 合わせた瞬間の曲の位置 (ms、手のずらしを除く)。
    pub song_ms: i64,
    /// 合わせた瞬間の端末の単調時計 (ms)。
    pub mono_ms: i64,
    /// 速さ (1.0 = 原曲どおり)。
    pub rate: f64,
    /// 手で足したずらし (ms)。正なら歌詞が先へ進む。
    pub nudge_ms: i64,
}

/// 手で合わせた点 (速さを出すために前の 1 点を覚えておく)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct KaraokeAnchor {
    pub song_ms: i64,
    pub mono_ms: i64,
}

/// 耳で聞いた結果 1 回分 (外れ値を確かめるために持っておく)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct KaraokeHeard {
    pub song_ms: i64,
    pub mono_ms: i64,
}

/// 耳で聞いた結果をどう扱ったか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum KaraokeHeardChange {
    /// まだ合わせていなかったので、そのまま採った。
    Adopted,
    /// 差が小さいので直さなかった。
    Kept,
    /// 差を半分だけ寄せた。
    Eased,
    /// 大きく外れていたが 2 回続けて同じだったので採った。
    Jumped,
    /// 大きく外れていたので保留した (次に同じ値が来たら採る)。
    Held,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct KaraokeTapOutcome {
    pub clock: KaraokeClock,
    /// 次のタップで速さを出すための点。
    pub anchor: KaraokeAnchor,
    /// 速さを直したか。
    pub rate_changed: bool,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct KaraokeHeardOutcome {
    pub clock: KaraokeClock,
    /// 次の照合で確かめる保留の値。
    pub pending: Option<KaraokeHeard>,
    pub change: KaraokeHeardChange,
}

/// 次に自分が歌う行と、そこまでの時間。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct KaraokeTurn {
    /// 表示順の添字。
    pub index: u32,
    pub in_ms: i64,
    /// 数えの四角のうち点いている数 (0〜4)。
    pub lit: u32,
}

/// 帯 (この先 `window_ms`) の 1 区間。`from`/`to` は帯の左端 0〜右端 1。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct KaraokeLaneSpan {
    pub index: u32,
    pub from: f64,
    pub to: f64,
    pub singers: Vec<String>,
    pub is_mine: bool,
}

fn base_position(clock: &KaraokeClock, now_ms: i64) -> i64 {
    clock.song_ms + ((now_ms - clock.mono_ms) as f64 * clock.rate).round() as i64
}

/// 今の曲の位置 (ms、手のずらし込み)。
pub fn position(clock: &KaraokeClock, now_ms: i64) -> i64 {
    base_position(clock, now_ms) + clock.nudge_ms
}

/// 今の位置を `song_ms` として合わせ直す (止めて再開したとき)。速さとずらしは残す。
pub fn rebase(clock: &KaraokeClock, song_ms: i64, now_ms: i64) -> KaraokeClock {
    KaraokeClock { song_ms, mono_ms: now_ms, ..*clock }
}

/// 手のずらしを `delta_ms` 足す (±5 秒で頭打ち)。
pub fn nudge(clock: &KaraokeClock, delta_ms: i64) -> KaraokeClock {
    KaraokeClock { nudge_ms: (clock.nudge_ms + delta_ms).clamp(-NUDGE_LIMIT_MS, NUDGE_LIMIT_MS), ..*clock }
}

/// 「この行 (`line_start_ms`) が今始まった」とタップしたときの時計。
///
/// 前の点 (`previous_anchor`) から 20 秒以上空いていて、タップが今の時計の予測と 1.5 秒以内で
/// 合っていれば、2 点の間隔から速さを出す。出した速さが 0.9〜1.1 から外れたら速さは前のまま。
/// 呼ぶ側は、止めて再開したとき・耳で時計を動かしたときに前の点を捨てる (間の時間が速さに化けるので)。
pub fn tap(previous: Option<KaraokeClock>, previous_anchor: Option<KaraokeAnchor>,
           line_start_ms: i64, now_ms: i64) -> KaraokeTapOutcome {
    let mut rate = previous.map_or(1.0, |c| c.rate);
    let mut rate_changed = false;
    let agrees = previous.is_some_and(|c| (base_position(&c, now_ms) - line_start_ms).abs() <= RATE_TAP_AGREE_MS);
    if let (Some(a), true) = (previous_anchor, agrees) {
        let mono_span = now_ms - a.mono_ms;
        let song_span = line_start_ms - a.song_ms;
        if mono_span >= RATE_MIN_SPAN_MS && song_span > 0 {
            let r = song_span as f64 / mono_span as f64;
            if (RATE_MIN..=RATE_MAX).contains(&r) {
                rate_changed = (r - rate).abs() > 0.002;
                rate = r;
            }
        }
    }
    KaraokeTapOutcome {
        clock: KaraokeClock { song_ms: line_start_ms, mono_ms: now_ms, rate, nudge_ms: 0 },
        anchor: KaraokeAnchor { song_ms: line_start_ms, mono_ms: now_ms },
        rate_changed,
    }
}

/// 耳で聞いた位置 (`heard_song_ms` が `now_ms` 時点の曲の位置) で時計を直す。
pub fn heard(clock: Option<KaraokeClock>, pending: Option<KaraokeHeard>,
             heard_song_ms: i64, now_ms: i64) -> KaraokeHeardOutcome {
    let Some(clock) = clock else {
        return KaraokeHeardOutcome {
            clock: KaraokeClock { song_ms: heard_song_ms, mono_ms: now_ms, rate: 1.0, nudge_ms: 0 },
            pending: None,
            change: KaraokeHeardChange::Adopted,
        };
    };
    let here = base_position(&clock, now_ms);
    let diff = heard_song_ms - here;
    if diff.abs() <= HEARD_KEEP_MS {
        return KaraokeHeardOutcome { clock, pending: None, change: KaraokeHeardChange::Kept };
    }
    if diff.abs() <= HEARD_EASE_MS {
        return KaraokeHeardOutcome {
            clock: rebase(&clock, here + diff / 2, now_ms),
            pending: None,
            change: KaraokeHeardChange::Eased,
        };
    }
    // 大きく外れた。前回も同じ所を指していたら (前回の値をこの時刻まで進めて食い違いが小さい) 採る。
    if let Some(p) = pending {
        let projected = p.song_ms + ((now_ms - p.mono_ms) as f64 * clock.rate).round() as i64;
        if (heard_song_ms - projected).abs() <= HEARD_CONFIRM_MS {
            return KaraokeHeardOutcome {
                clock: rebase(&clock, heard_song_ms, now_ms),
                pending: None,
                change: KaraokeHeardChange::Jumped,
            };
        }
    }
    KaraokeHeardOutcome {
        clock,
        pending: Some(KaraokeHeard { song_ms: heard_song_ms, mono_ms: now_ms }),
        change: KaraokeHeardChange::Held,
    }
}

/// 行を歌う人 (`singers`) に自分のパート (`mine`) が入っているか。
pub fn is_mine(singers: &[String], mine: &[String]) -> bool {
    singers.iter().any(|s| mine.contains(s))
}

/// 時刻のある行を時刻順に (同じ時刻は表示順)。
fn timed(starts: &[Option<i64>]) -> Vec<(i64, usize)> {
    let mut t: Vec<(i64, usize)> = starts.iter().enumerate().filter_map(|(i, s)| s.map(|s| (s, i))).collect();
    t.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    t
}

/// 次に自分が歌い出す行。いま自分の行を歌っていて、そのまま自分の行が続くあいだは数えない
/// (次の「番」は、誰か別の人の行か 10 秒以上の間を挟んでから)。残りが 8 秒を超えるうちは出さない。
///
/// `starts` はメインの行だけ時刻を入れた並び (被せの行は None)、`singers` は各行を歌う人。
pub fn next_turn(starts: &[Option<i64>], singers: &[Vec<String>], mine: &[String],
                 position_ms: i64) -> Option<KaraokeTurn> {
    if mine.is_empty() {
        return None;
    }
    let mine_at = |i: usize| singers.get(i).is_some_and(|s| is_mine(s, mine));
    let current = lyric_sync::active_line(starts, position_ms);
    let mut prev_mine = current.is_some_and(|i| mine_at(i as usize));
    let mut prev_start = current.and_then(|i| starts[i as usize]);
    for (start, i) in timed(starts) {
        if start <= position_ms {
            continue;
        }
        let m = mine_at(i);
        // 間奏などで 10 秒以上空いたら、同じ人の続きでも新しい入りとして数える。
        let after_gap = prev_start.is_some_and(|p| start - p >= LANE_LINE_CAP_MS);
        prev_start = Some(start);
        if m && (!prev_mine || after_gap) {
            let in_ms = start - position_ms;
            if in_ms > TURN_COUNTDOWN_MS {
                return None;
            }
            let lit = ((in_ms + 999) / 1000).clamp(0, TURN_SQUARES as i64) as u32;
            return Some(KaraokeTurn { index: i as u32, in_ms, lit });
        }
        prev_mine = m;
    }
    None
}

/// この先 `window_ms` に誰が歌うかの帯。歌う人の付いていない行は抜く (帯に隙間が空く)。
/// 1 行は次の行の始まりまで (最長 10 秒)。
pub fn lane(starts: &[Option<i64>], singers: &[Vec<String>], mine: &[String],
            position_ms: i64, window_ms: i64) -> Vec<KaraokeLaneSpan> {
    if window_ms <= 0 {
        return vec![];
    }
    let t = timed(starts);
    let window_end = position_ms + window_ms;
    let mut out = Vec::new();
    for (k, &(start, i)) in t.iter().enumerate() {
        let next = t.get(k + 1).map_or(start + LANE_LINE_CAP_MS, |n| n.0);
        let end = next.min(start + LANE_LINE_CAP_MS);
        if end <= position_ms || start >= window_end {
            continue;
        }
        let who = singers.get(i).cloned().unwrap_or_default();
        if who.is_empty() {
            continue;
        }
        let from = (start.max(position_ms) - position_ms) as f64 / window_ms as f64;
        let to = (end.min(window_end) - position_ms) as f64 / window_ms as f64;
        if to <= from {
            continue;
        }
        out.push(KaraokeLaneSpan { index: i as u32, from, to, is_mine: is_mine(&who, mine), singers: who });
    }
    out.sort_by(|a, b| a.from.partial_cmp(&b.from).unwrap_or(Ordering::Equal));
    out
}

/// 曲名の後ろに付く、カラオケ版・インスト版の札 (突き合わせ用に畳んだ形)。
const KARAOKE_MARKS: [&str; 5] = ["からおけ", "karaoke", "instrumental", "offvocal", "おふぼーかる"];
/// 札に添えて付く飾り (「オリジナル・カラオケ」「Instrumental Ver.」)。札を外した残りから一緒に外す。
const KARAOKE_FILLERS: [&str; 4] = ["おりじなる", "original", "version", "ver"];

/// 当たった曲名が、開いている曲そのものか、そのカラオケ版か。
/// 鍵 (かな・大小・全角半角を畳み、空白と記号を落とす) は Spotify の突き合わせと同じもの。
/// 後ろに付いた余りが札と飾りだけのときに限る。他の語が残れば別の曲・別の版
/// (「Believe my change!」・REM@STER・M@STER VERSION など、尺が違う) とみる。
fn same_or_karaoke_title(song_title: &str, heard_title: &str) -> bool {
    let song = crate::domain::spotify::match_key(song_title);
    let heard = crate::domain::spotify::match_key(heard_title);
    if song.is_empty() {
        return false;
    }
    match heard.strip_prefix(&song) {
        Some("") => true,
        Some(rest) => {
            if !KARAOKE_MARKS.iter().any(|m| rest.contains(m)) {
                return false;
            }
            let mut left = rest.to_string();
            for w in KARAOKE_MARKS.iter().chain(KARAOKE_FILLERS.iter()) {
                left = left.replace(w, "");
            }
            left.is_empty()
        }
        None => false,
    }
}

/// 耳で当たった曲が、開いている曲と同じか (違う曲の位置で時計を動かさない)。
///
/// Apple Music の id か ISRC が一致すれば同じ。どちらも違えば、曲名を畳んで突き合わせる
/// (off vocal は別の id で配信されるので、名前の後ろの「(オリジナル・カラオケ)」等は外して比べる)。
pub fn heard_same_song(song_title: &str, song_apple_music_id: Option<&str>, song_isrc: Option<&str>,
                       heard_title: Option<&str>, heard_apple_music_id: Option<&str>,
                       heard_isrc: Option<&str>) -> bool {
    let same = |a: Option<&str>, b: Option<&str>| match (a, b) {
        (Some(a), Some(b)) => !a.trim().is_empty() && a.trim().eq_ignore_ascii_case(b.trim()),
        _ => false,
    };
    if same(song_apple_music_id, heard_apple_music_id) || same(song_isrc, heard_isrc) {
        return true;
    }
    match heard_title {
        Some(t) => same_or_karaoke_title(song_title, t),
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clock(song: i64, mono: i64) -> KaraokeClock {
        KaraokeClock { song_ms: song, mono_ms: mono, rate: 1.0, nudge_ms: 0 }
    }

    #[test]
    fn position_advances_with_rate_and_nudge() {
        let c = KaraokeClock { song_ms: 10_000, mono_ms: 1_000, rate: 1.1, nudge_ms: 300 };
        assert_eq!(position(&c, 11_000), 10_000 + 11_000 + 300);
    }

    #[test]
    fn first_tap_sets_offset_only() {
        let o = tap(None, None, 15_000, 100_000);
        assert_eq!(o.clock, clock(15_000, 100_000));
        assert!(!o.rate_changed);
        assert_eq!(position(&o.clock, 102_000), 17_000);
    }

    #[test]
    fn second_tap_far_apart_fits_rate() {
        let first = tap(None, None, 15_000, 100_000);
        // 原曲で 30 秒先の行が、実際には 28.57 秒後に来た (速い)。
        let o = tap(Some(first.clock), Some(first.anchor), 45_000, 128_571);
        assert!(o.rate_changed);
        assert!((o.clock.rate - 1.05).abs() < 0.001);
    }

    #[test]
    fn second_tap_close_or_wild_keeps_rate() {
        let first = tap(None, None, 15_000, 100_000);
        let near = tap(Some(first.clock), Some(first.anchor), 20_000, 105_500);
        assert_eq!(near.clock.rate, 1.0);
        // 別の行を叩いた (速さ 2 倍に見える)。
        let wild = tap(Some(first.clock), Some(first.anchor), 75_000, 130_000);
        assert_eq!(wild.clock.rate, 1.0);
        assert!(!wild.rate_changed);
    }

    #[test]
    fn rate_needs_tap_close_to_prediction() {
        // 4 秒先の行をうっかり叩き、25 秒後に正しい行で合わせ直した: 予測から 4 秒外れているので速さは出さない。
        let wrong = tap(Some(clock(0, 0)), None, 4_000, 0);
        let fix = tap(Some(wrong.clock), Some(wrong.anchor), 25_000, 25_000);
        assert_eq!(fix.clock.rate, 1.0);
        // 予測と合っているが速さが 1.1 を超える: 採らない。
        let first = tap(None, None, 0, 0);
        let fast = tap(Some(first.clock), Some(first.anchor), 30_000, 26_000);
        assert_eq!(fast.clock.rate, 1.0);
    }

    #[test]
    fn next_turn_counts_again_after_a_long_gap() {
        // 1 番の最後と 2 番の頭を同じ人が歌い、間に 20 秒の間奏 (marker 行なし)。
        let starts = vec![Some(0), Some(4_000), Some(24_000)];
        let singers = vec![v(&["a"]), v(&["b"]), v(&["b"])];
        let t = next_turn(&starts, &singers, &v(&["b"]), 18_000).unwrap();
        assert_eq!(t.index, 2);
    }

    #[test]
    fn tap_resets_nudge() {
        let c = nudge(&clock(0, 0), 300);
        assert_eq!(tap(Some(c), None, 1_000, 5_000).clock.nudge_ms, 0);
    }

    #[test]
    fn nudge_is_capped() {
        assert_eq!(nudge(&clock(0, 0), 9_000).nudge_ms, 5_000);
        assert_eq!(nudge(&clock(0, 0), -9_000).nudge_ms, -5_000);
    }

    #[test]
    fn heard_adopts_when_unsynced() {
        let o = heard(None, None, 42_000, 9_000);
        assert_eq!(o.change, KaraokeHeardChange::Adopted);
        assert_eq!(position(&o.clock, 10_000), 43_000);
    }

    #[test]
    fn heard_small_diff_is_kept_medium_is_eased() {
        let c = clock(10_000, 0);
        assert_eq!(heard(Some(c), None, 20_100, 10_000).change, KaraokeHeardChange::Kept);
        let o = heard(Some(c), None, 21_000, 10_000);
        assert_eq!(o.change, KaraokeHeardChange::Eased);
        assert_eq!(position(&o.clock, 10_000), 20_500);
    }

    #[test]
    fn heard_keeps_nudge() {
        let c = nudge(&clock(10_000, 0), -400);
        let o = heard(Some(c), None, 21_000, 10_000);
        assert_eq!(o.clock.nudge_ms, -400);
        assert_eq!(position(&o.clock, 10_000), 20_100);
    }

    #[test]
    fn heard_outlier_needs_confirmation() {
        let c = clock(10_000, 0);
        let first = heard(Some(c), None, 60_000, 10_000);
        assert_eq!(first.change, KaraokeHeardChange::Held);
        assert_eq!(first.clock, c);
        // 30 秒後、同じ所を指している (60s + 30s)。
        let second = heard(Some(first.clock), first.pending, 90_200, 40_000);
        assert_eq!(second.change, KaraokeHeardChange::Jumped);
        assert_eq!(position(&second.clock, 40_000), 90_200);
        // 食い違っていればまた保留。
        let other = heard(Some(first.clock), first.pending, 120_000, 40_000);
        assert_eq!(other.change, KaraokeHeardChange::Held);
    }

    fn v(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn next_turn_counts_down_only_near_and_after_a_break() {
        let starts = vec![Some(10_000), Some(14_000), Some(18_000), Some(22_000), Some(26_000)];
        let singers = vec![v(&["a"]), v(&["b"]), v(&["b"]), v(&["a"]), v(&["b"])];
        let mine = v(&["b"]);
        // a を歌っている最中: 4 秒後に b。
        let t = next_turn(&starts, &singers, &mine, 11_600).unwrap();
        assert_eq!(t.index, 1);
        assert_eq!(t.in_ms, 2_400);
        assert_eq!(t.lit, 3);
        // b が続く間は数えず、a を挟んだ次の b。
        let t = next_turn(&starts, &singers, &mine, 15_000);
        assert_eq!(t, None, "次の b は 11 秒後なので出さない");
        let t = next_turn(&starts, &singers, &mine, 23_000).unwrap();
        assert_eq!(t.index, 4);
        // 遠いうちは出さない。
        assert_eq!(next_turn(&starts, &singers, &mine, 0), None);
        assert_eq!(next_turn(&starts, &singers, &[], 11_000), None);
    }

    #[test]
    fn next_turn_lit_caps_at_four() {
        let starts = vec![Some(10_000)];
        let t = next_turn(&starts, &[v(&["a"])], &v(&["a"]), 3_000).unwrap();
        assert_eq!(t.lit, 4);
    }

    #[test]
    fn lane_clips_to_window_and_skips_unassigned() {
        let starts = vec![Some(0), Some(5_000), Some(10_000), None, Some(40_000)];
        let singers = vec![v(&["a"]), v(&[]), v(&["a", "b"]), v(&["c"]), v(&["b"])];
        let spans = lane(&starts, &singers, &v(&["b"]), 2_000, 20_000);
        assert_eq!(spans.len(), 2);
        assert_eq!(spans[0].index, 0);
        assert_eq!(spans[0].from, 0.0);
        assert!((spans[0].to - 0.15).abs() < 1e-9);
        assert!(!spans[0].is_mine);
        // 3 行目は次の行 (40s) までではなく 10 秒で切る → 20s まで。
        assert_eq!(spans[1].index, 2);
        assert!((spans[1].from - 0.4).abs() < 1e-9);
        assert!((spans[1].to - 0.9).abs() < 1e-9);
        assert!(spans[1].is_mine);
    }

    #[test]
    fn same_song_by_id_isrc_or_title() {
        assert!(heard_same_song("Ready!!", Some("123"), None, Some("x"), Some("123"), None));
        assert!(heard_same_song("Ready!!", None, Some("JPXX01"), None, None, Some("jpxx01")));
        assert!(heard_same_song("Ready!!", Some("1"), None, Some("Ready!! (オリジナル・カラオケ)"), Some("2"), None));
        assert!(heard_same_song("Ready!!", None, None, Some("READY!! (Instrumental)"), None, None));
        assert!(heard_same_song("ＲＥＡＤＹ！！", None, None, Some("Ready!! -off vocal-"), None, None));
        assert!(!heard_same_song("Ready!!", Some("1"), None, Some("Ready!! (Remix)"), Some("2"), None));
        assert!(!heard_same_song("Ready!!", Some("1"), None, Some("ほかの曲"), Some("2"), None));
        assert!(!heard_same_song("Believe", None, None, Some("Believe my change! (オリジナル・カラオケ)"), None, None));
        assert!(!heard_same_song("蒼い鳥", None, None, Some("蒼い鳥(REM@STER-A) (Instrumental)"), None, None));
        assert!(!heard_same_song("蒼い鳥", None, None, Some("蒼い鳥 (M@STER VERSION) -off vocal-"), None, None));
        assert!(heard_same_song("Ready!!", None, None, Some("Ready!! (Instrumental Ver.)"), None, None));
        assert!(!heard_same_song("Ready!!", None, None, None, None, None));
        assert!(heard_same_song("M@STERPIECE", None, None, Some("M@STERPIECE"), None, None));
    }
}
