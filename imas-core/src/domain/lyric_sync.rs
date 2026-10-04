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

/// 時刻のある行 1 本ぶんの帯 (タイミング編集のタイムライン・ここ好きの山の土台)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricSpan {
    /// 表示順の添字。
    pub index: u32,
    pub start_ms: i64,
    /// 次の行の始まり (最後の行は始まり + 8 秒、曲の長さで切る)。
    pub end_ms: i64,
}

/// 被せの行 1 本が続くとみなす長さの上限 (次の被せが来なければここで消す)。
const OVERLAY_SPAN_MAX_MS: i64 = 6_000;

/// 行の本文を「メイン」と「被せ」(括弧の中) に分けたもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricOverlaySplit {
    /// 括弧の外。行まるごと括弧なら空。
    pub main: String,
    /// 括弧の中 (括弧は外す)。複数あれば全角空白で繋ぐ。無ければ `None`。
    pub overlay: Option<String>,
}

/// 振り仮名 (ルビ) 1 つ。添字は行の中の Unicode スカラー位置。
/// `base_start..base_end` が親字 (漢字)、`open..close` が括弧ごとの振り仮名 (`close` は閉じ括弧の次)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricRuby {
    pub base_start: u32,
    pub base_end: u32,
    pub open: u32,
    pub close: u32,
}

fn is_ideograph(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' | '\u{F900}'..='\u{FAFF}' | '々' | '〆' | 'ヶ')
}

fn is_kana(c: char) -> bool {
    matches!(c, '\u{3041}'..='\u{309F}' | '\u{30A1}'..='\u{30FF}')
}

/// 行の中の振り仮名の括弧。歌詞サイトの本文は「五輪咲（ごりん）」のように、漢字の直後の括弧で
/// 読みを書くことがある。被せ (「夢を（夢を）」) と見分ける規則:
/// - 開き括弧の**直前が漢字** (空白を挟まない)
/// - 括弧の中が**かなだけ** (空白は可、かなが 1 字以上)
///
/// 親字は、開き括弧の直前から遡って続く漢字のまとまり。入れ子・閉じない括弧は振り仮名にしない。
pub fn ruby_spans(text: &str) -> Vec<LyricRuby> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if is_open(chars[i]) && i > 0 && is_ideograph(chars[i - 1]) {
            let mut j = i + 1;
            let mut kana = 0;
            let mut ok = true;
            while j < chars.len() && !is_close(chars[j]) {
                let c = chars[j];
                if is_kana(c) {
                    kana += 1;
                } else if c != ' ' && c != '\u{3000}' {
                    ok = false;
                    break;
                }
                j += 1;
            }
            if ok && kana > 0 && j < chars.len() {
                let mut base_start = i - 1;
                while base_start > 0 && is_ideograph(chars[base_start - 1]) {
                    base_start -= 1;
                }
                out.push(LyricRuby { base_start: base_start as u32, base_end: i as u32, open: i as u32, close: (j + 1) as u32 });
                i = j + 1;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// 各スカラーが (振り仮名でない) 括弧の内側か。括弧の対応が取れない行は全部 false。
fn inside_overlay_brackets(text: &str) -> Vec<bool> {
    let chars: Vec<char> = text.chars().collect();
    let ruby = ruby_spans(text);
    let in_ruby = |i: usize| ruby.iter().any(|r| (r.open as usize..r.close as usize).contains(&i));
    let mut out = vec![false; chars.len()];
    let mut depth = 0usize;
    for (i, &c) in chars.iter().enumerate() {
        if in_ruby(i) {
            continue;
        }
        if is_open(c) {
            depth += 1;
        } else if is_close(c) {
            if depth == 0 {
                return vec![false; chars.len()];
            }
            depth -= 1;
        } else if depth > 0 {
            out[i] = true;
        }
    }
    if depth != 0 {
        return vec![false; chars.len()];
    }
    out
}

fn is_open(c: char) -> bool {
    c == '(' || c == '（'
}
fn is_close(c: char) -> bool {
    c == ')' || c == '）'
}

/// 行の本文を、括弧の外 (メイン) と中 (被せ) に分ける。
///
/// 歌詞の括弧は被せ・追いかけ・コーラスの印 (「夢を（夢を）」)。括弧の対応が取れない行は
/// 分けない (記号として括弧を使っている行を壊さない)。
pub fn split_overlay(text: &str) -> LyricOverlaySplit {
    let unsplit = LyricOverlaySplit { main: text.to_string(), overlay: None };
    let mut depth = 0usize;
    let mut main = String::new();
    let mut parts: Vec<String> = vec![];
    let mut current = String::new();
    // 振り仮名の括弧は被せではないので、そのまま本文に残す (画面が振り仮名として描く)。
    let ruby = ruby_spans(text);
    let in_ruby = |i: usize| ruby.iter().any(|r| (r.open as usize..r.close as usize).contains(&i));
    for (i, c) in text.chars().enumerate() {
        if depth == 0 && in_ruby(i) {
            main.push(c);
        } else if is_open(c) {
            if depth > 0 {
                current.push(c);
            }
            depth += 1;
        } else if is_close(c) {
            if depth == 0 {
                return unsplit;
            }
            depth -= 1;
            if depth == 0 {
                let part = current.trim().to_string();
                if !part.is_empty() {
                    parts.push(part);
                }
                current.clear();
            } else {
                current.push(c);
            }
        } else if depth > 0 {
            current.push(c);
        } else {
            main.push(c);
        }
    }
    if depth != 0 || parts.is_empty() {
        return unsplit;
    }
    LyricOverlaySplit { main: main.trim().to_string(), overlay: Some(parts.join("\u{3000}")) }
}

/// 被せの行か。指定 (`layer` = `"overlay"` / `"main"`) があればそれに従い、
/// 無ければ「行まるごと括弧」なら被せとみなす。
pub fn is_overlay_line(text: &str, layer: Option<&str>) -> bool {
    match layer {
        Some("overlay") => true,
        Some("main") => false,
        _ => {
            let split = split_overlay(text);
            split.overlay.is_some() && split.main.is_empty()
        }
    }
}

/// いま光らせる被せの行の添字 (`starts` は被せの行だけ時刻を入れ、他は `None`)。
pub fn active_overlay(starts: &[Option<i64>], position_ms: i64) -> Option<u32> {
    capped_spans(starts, 0, OVERLAY_SPAN_MAX_MS)
        .into_iter()
        .filter(|sp| sp.start_ms <= position_ms && position_ms < sp.end_ms)
        .last()
        .map(|sp| sp.index)
}

/// 帯の長さを `cap_ms` で切ったもの (コール・被せ)。
fn capped_spans(starts: &[Option<i64>], duration_ms: i64, cap_ms: i64) -> Vec<LyricSpan> {
    line_spans(starts, duration_ms)
        .into_iter()
        .map(|sp| LyricSpan { end_ms: sp.end_ms.min(sp.start_ms + cap_ms), ..sp })
        .collect()
}

/// 被せの行の帯 (タイミング編集の被せの段)。
pub fn overlay_spans(starts: &[Option<i64>], duration_ms: i64) -> Vec<LyricSpan> {
    capped_spans(starts, duration_ms, OVERLAY_SPAN_MAX_MS)
}

/// コール 1 つが続くとみなす長さの上限。コールは短いので、次のコールまで伸ばすと
/// 間奏の間ずっと出っぱなしになる。
const CALL_SPAN_MAX_MS: i64 = 3_000;

/// コールの帯。行と同じく時刻順で、長さは次のコールまで (最長 3 秒)。
pub fn call_spans(starts: &[Option<i64>], duration_ms: i64) -> Vec<LyricSpan> {
    capped_spans(starts, duration_ms, CALL_SPAN_MAX_MS)
}

/// いま出すコールの添字。帯 ([`call_spans`]) の中にいるときだけ。間が空いたら `None`。
pub fn active_call(starts: &[Option<i64>], position_ms: i64) -> Option<u32> {
    call_spans(starts, 0)
        .into_iter()
        .filter(|sp| sp.start_ms <= position_ms && position_ms < sp.end_ms)
        .last()
        .map(|sp| sp.index)
}

/// 時刻のある行を時刻順に並べ、それぞれの帯 (始まり〜次の行の始まり) にする。
/// 曲の長さが分からなければ `duration_ms <= 0` で渡す (切らない)。
pub fn line_spans(starts: &[Option<i64>], duration_ms: i64) -> Vec<LyricSpan> {
    let mut timed: Vec<(i64, usize)> = starts
        .iter()
        .enumerate()
        .filter_map(|(i, s)| s.map(|s| (s, i)))
        .collect();
    timed.sort();
    (0..timed.len())
        .map(|k| {
            let (start, index) = timed[k];
            let mut end = timed.get(k + 1).map(|(s, _)| *s).unwrap_or(start + LAST_LINE_SPAN_MS);
            if duration_ms > 0 {
                end = end.min(duration_ms);
            }
            LyricSpan { index: index as u32, start_ms: start, end_ms: end.max(start) }
        })
        .collect()
}

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
    let spans = line_spans(starts, duration_ms);
    let count_of = |i: u32| counts.get(i as usize).copied().unwrap_or(0);
    if spans.iter().all(|sp| count_of(sp.index) == 0) {
        return empty;
    }
    let n = buckets as usize;
    let mut raw = vec![0f32; n];
    for sp in &spans {
        let count = count_of(sp.index);
        if count == 0 || sp.end_ms <= sp.start_ms {
            continue;
        }
        let from = ((sp.start_ms as f64 / duration_ms as f64) * n as f64).floor().max(0.0) as usize;
        let to = ((sp.end_ms as f64 / duration_ms as f64) * n as f64).ceil() as usize;
        for b in raw.iter_mut().take(to.min(n)).skip(from.min(n)) {
            *b = b.max(count as f32);
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
    let peak_ms = spans
        .iter()
        .filter(|sp| sp.start_ms < duration_ms)
        .fold(None::<(i64, u32)>, |best, sp| {
            let c = count_of(sp.index);
            match best {
                Some((_, bc)) if bc >= c => best,
                _ if c > 0 => Some((sp.start_ms, c)),
                _ => best,
            }
        })
        .map(|(s, _)| s);
    LyricLikeHeat { levels: smoothed.iter().map(|v| v / max).collect(), peak_ms }
}

/// 「同時」のコールが、掛かっている歌詞と同じ文字か (一緒に歌う・叫ぶだけのコール)。
///
/// そういうコールは行として並べると歌詞と同じ文字が 2 回出るので、画面は行を出さずに
/// 歌詞のその部分へ印を付ける。比べるときは括弧・空白・記号・大文字小文字・カナの別・
/// 伸ばし (ー・〜) を無視する。追っかけ (`after`) は別の文字を返すものなので対象外。
pub fn call_echoes_lyric(anchor_text: &str, call_text: &str, timing: &str) -> bool {
    timing == "over" && same_words(anchor_text, call_text)
}

/// 行の中のコールが、掛かっている歌詞と同じ文字か。[`call_echoes_lyric`] に加えて、
/// 掛かっている所が歌詞の (振り仮名でない) 括弧の中 = 歌詞にもう被せとして書いてある所なら、
/// 追っかけでも同じ文字を 2 回出さない (「（勿論さ！）」に「(勿論さ！)」のコール)。
pub fn call_echoes_line(line_text: &str, start: u32, end: u32, call_text: &str, timing: &str) -> bool {
    let chars: Vec<char> = line_text.chars().collect();
    let (start, end) = (start as usize, end as usize);
    if start >= end || end > chars.len() {
        return false;
    }
    let anchor: String = chars[start..end].iter().collect();
    if !same_words(&anchor, call_text) {
        return false;
    }
    if timing == "over" {
        return true;
    }
    let inside = inside_overlay_brackets(line_text);
    // 括弧そのものや空白を範囲に含めても、文字の部分が括弧の中にあれば被せとみなす。
    chars[start..end]
        .iter()
        .enumerate()
        .filter(|(_, c)| c.is_alphanumeric())
        .all(|(k, _)| inside[start + k])
}

fn same_words(anchor_text: &str, call_text: &str) -> bool {
    let fold = |t: &str| -> String {
        let bytes = crate::domain::text_search_index::prepare_needle(t);
        String::from_utf8_lossy(&bytes)
            .chars()
            .filter(|c| c.is_alphanumeric() && !matches!(c, 'ー' | '〜' | '～'))
            .collect()
    };
    let anchor = fold(anchor_text);
    !anchor.is_empty() && anchor == fold(call_text)
}

/// パート分け (誰が歌うか) を付ける曲か。原唱者が 2 人以上のときだけ (ソロ曲は 1 人なので要らない)。
pub fn parts_applicable(original_artist_count: u32) -> bool {
    original_artist_count >= 2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn over_call_with_the_same_words_echoes_the_lyric() {
        assert!(call_echoes_lyric("サンプル行です", "(サンプル行です)", "over"));
        assert!(call_echoes_lyric("Let's go", "（LET'S GO！）", "over"));
        assert!(call_echoes_lyric("ハイ", "はーい", "over"));
        assert!(!call_echoes_lyric("サンプル行です", "(サンプル行です)", "after"));
        assert!(!call_echoes_lyric("サンプル", "Hi!", "over"));
        assert!(!call_echoes_lyric("", "", "over"));
    }

    #[test]
    fn ruby_is_kana_in_brackets_right_after_kanji() {
        // 五輪咲（ごりん）駆動
        let r = ruby_spans("五輪咲（ごりん）駆動");
        assert_eq!(r, vec![LyricRuby { base_start: 0, base_end: 3, open: 3, close: 8 }]);
        // 被せ: 直前が漢字でない / 中に漢字がある
        assert!(ruby_spans("夢を（ゆめを）").is_empty());
        assert!(ruby_spans("光 空（勿論さ！）").is_empty());
        assert!(ruby_spans("限界へ走る (手伸ばせ)").is_empty());
        // 空白入りの読みも振り仮名
        assert_eq!(ruby_spans("五輪（ごり　ん）").len(), 1);
    }

    #[test]
    fn ruby_brackets_stay_in_main_text() {
        let split = split_overlay("五輪咲（ごりん）駆動の100万馬力で");
        assert_eq!(split.overlay, None);
        let split = split_overlay("五輪咲（ごりん）駆動（追いかけ）");
        assert_eq!(split.main, "五輪咲（ごりん）駆動");
        assert_eq!(split.overlay.as_deref(), Some("追いかけ"));
    }

    #[test]
    fn call_on_bracketed_lyric_with_same_words_echoes_even_after() {
        let line = "あるかい？（勿論さ！）";
        // 「勿論さ！」の範囲 (6..10)
        assert!(call_echoes_line(line, 6, 10, "(勿論さ！)", "after"));
        // 括弧ごと選んでいても同じ
        assert!(call_echoes_line(line, 5, 11, "(勿論さ！)", "after"));
        // 括弧の外で追っかけは別物
        assert!(!call_echoes_line("勿論さ！", 0, 4, "(勿論さ！)", "after"));
        assert!(call_echoes_line("勿論さ！", 0, 4, "(勿論さ！)", "over"));
        // 振り仮名の括弧は被せではない
        assert!(!call_echoes_line("五輪咲（ごりん）", 4, 7, "ごりん", "after"));
    }

    #[test]
    fn parts_only_for_songs_with_two_or_more_singers() {
        assert!(!parts_applicable(0));
        assert!(!parts_applicable(1));
        assert!(parts_applicable(2));
    }

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

    #[test]
    fn line_spans_sorted_by_time_and_capped() {
        let spans = line_spans(&[Some(5000), None, Some(1000)], 9000);
        assert_eq!(spans, vec![
            LyricSpan { index: 2, start_ms: 1000, end_ms: 5000 },
            LyricSpan { index: 0, start_ms: 5000, end_ms: 9000 },
        ]);
        assert_eq!(line_spans(&[Some(0)], 0)[0].end_ms, 8000);
    }

    #[test]
    fn calls_are_short_and_disappear_in_gaps() {
        let starts = [Some(1000), Some(2000), Some(10_000)];
        let spans = call_spans(&starts, 0);
        assert_eq!(spans[1].end_ms, 5000);
        assert_eq!(active_call(&starts, 1500), Some(0));
        assert_eq!(active_call(&starts, 4000), Some(1));
        assert_eq!(active_call(&starts, 6000), None);
        assert_eq!(active_call(&starts, 500), None);
    }

    #[test]
    fn split_overlay_cases() {
        let s = split_overlay("夢を（夢を）見てた(Yeah)");
        assert_eq!(s.main, "夢を見てた");
        assert_eq!(s.overlay.as_deref(), Some("夢を\u{3000}Yeah"));
        assert_eq!(split_overlay("（ラララ）").main, "");
        // 対応が取れない括弧は分けない。
        assert_eq!(split_overlay("笑顔)").overlay, None);
        assert_eq!(split_overlay("(笑顔").overlay, None);
        assert_eq!(split_overlay("括弧なし").overlay, None);
    }

    #[test]
    fn overlay_line_rule_and_override() {
        assert!(is_overlay_line("（ラララ）", None));
        assert!(!is_overlay_line("夢を（夢を）", None));
        assert!(!is_overlay_line("（ラララ）", Some("main")));
        assert!(is_overlay_line("ふつうの行", Some("overlay")));
    }

    #[test]
    fn overlay_disappears_after_cap() {
        let starts = [None, Some(1000), None];
        assert_eq!(active_overlay(&starts, 1500), Some(1));
        assert_eq!(active_overlay(&starts, 8000), None);
    }
}
