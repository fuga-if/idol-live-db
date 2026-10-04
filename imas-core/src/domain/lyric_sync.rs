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
/// `base_start..base_end` が親字、`open` が「《」、`close` が「》」の次。
/// `marker` は親字の頭を示す「｜」の位置 (書いてあるときだけ。画面では出さない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricRuby {
    pub base_start: u32,
    pub base_end: u32,
    pub open: u32,
    pub close: u32,
    pub marker: Option<u32>,
}

fn is_ideograph(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' | '\u{F900}'..='\u{FAFF}' | '々' | '〆' | 'ヶ')
}

/// 行の中の振り仮名。本文は青空文庫と同じ記法で書く (Worker の lyrics_ruby.ts が取り込み時に直す):
/// - `五輪咲《ごりん》` … 親字は「《」の直前から遡って続く漢字のまとまり
/// - `｜ダミー《だみ》` … 漢字のまとまりでないときは「｜」で親字の頭を示す
///
/// 括弧 （） () は振り仮名に使わない (被せ・コーラスの印)。閉じない「《」と、親字の無い「《」は無視する。
pub fn ruby_spans(text: &str) -> Vec<LyricRuby> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut segment_start = 0usize;
    for j in 0..chars.len() {
        if chars[j] != '》' {
            continue;
        }
        // 閉じの直前の「《」(いちばん内側) と組にする。歌詞が《》を引用の記号にも使っていて
        // 「《地球《ちきゅう》》」のように重なっても、内側だけを振り仮名として読む。
        let Some(p) = chars[segment_start..j].iter().rposition(|&c| c == '《') else { continue };
        let open = segment_start + p;
        let marker = chars[segment_start..open].iter().rposition(|&c| c == '｜').map(|m| segment_start + m);
        let base_start = match marker {
            Some(m) => m + 1,
            None => {
                let mut k = open;
                while k > segment_start && is_ideograph(chars[k - 1]) {
                    k -= 1;
                }
                k
            }
        };
        if base_start < open && open + 1 < j {
            out.push(LyricRuby {
                base_start: base_start as u32,
                base_end: open as u32,
                open: open as u32,
                close: (j + 1) as u32,
                marker: marker.map(|m| m as u32),
            });
            segment_start = j + 1;
        }
    }
    out
}

/// 行の中の「振り仮名にできる括弧」と「いまの振り仮名」1 つずつ。区切り編集の画面が並べる。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricRubyChoice {
    /// 開きの記号 (「（」「(」か「《」) の位置。
    pub open: u32,
    /// いま振り仮名 (《》) か。false なら括弧。
    pub is_ruby: bool,
    /// 括弧の中の文字 (読み)。
    pub reading: String,
    /// 親字の頭に選べる位置。近い順 (1 文字、2 文字…)。空白・閉じ記号・前の振り仮名は越えない。
    pub bases: Vec<u32>,
    /// いまの (括弧なら既定の) 親字の頭。漢字の直後でない括弧は `None` (選んでもらう)。
    pub base: Option<u32>,
}

/// 親字の頭に選べる候補を、遡って何文字まで出すか。
const RUBY_BASE_CHOICES_MAX: usize = 16;

fn is_kana(c: char) -> bool {
    matches!(c, '\u{3041}'..='\u{309F}' | '\u{30A0}'..='\u{30FF}')
}

fn ends_base_search(c: char) -> bool {
    c.is_whitespace() || matches!(c, '》' | '）' | ')' | '《' | '（' | '(' | '｜' | '「' | '」' | '、' | '。')
}

/// `open` から遡って親字の頭に選べる位置 (近い順)。`skip` は飛ばす「｜」の位置。
fn ruby_base_choices(chars: &[char], open: usize, skip: Option<usize>) -> Vec<u32> {
    let mut out = Vec::new();
    let mut k = open;
    while k > 0 && out.len() < RUBY_BASE_CHOICES_MAX {
        k -= 1;
        if Some(k) == skip {
            continue;
        }
        if ends_base_search(chars[k]) {
            break;
        }
        out.push(k as u32);
    }
    out
}

/// 区切り編集で並べる振り仮名の候補。いまの振り仮名と、振り仮名にできる括弧 (中身がかなだけで閉じていて、
/// 直前に文字があるもの) を位置の順に返す。漢字の直後なら漢字のまとまりを既定の親字にする。
/// 当て字 (漢字でない親字) は `bases` から頭を選んでもらう。
pub fn ruby_choices(text: &str) -> Vec<LyricRubyChoice> {
    let chars: Vec<char> = text.chars().collect();
    let rubies = ruby_spans(text);
    let inside_ruby = |k: usize| rubies.iter().any(|r| (r.open as usize) <= k && k < r.close as usize);
    let mut out: Vec<LyricRubyChoice> = rubies
        .iter()
        .map(|r| LyricRubyChoice {
            open: r.open,
            is_ruby: true,
            reading: chars[r.open as usize + 1..r.close as usize - 1].iter().collect(),
            bases: ruby_base_choices(&chars, r.open as usize, r.marker.map(|m| m as usize)),
            base: Some(r.base_start),
        })
        .collect();
    for (k, &c) in chars.iter().enumerate() {
        if !is_open(c) || k == 0 || inside_ruby(k) {
            continue;
        }
        let Some(len) = chars[k + 1..].iter().position(|&d| is_close(d) || is_open(d)) else { continue };
        // 読みはかなだけ (被せ・コーラスの括弧まで候補に並べない)。
        if len == 0 || !is_close(chars[k + 1 + len]) || !chars[k + 1..k + 1 + len].iter().all(|&d| is_kana(d)) {
            continue;
        }
        let bases = ruby_base_choices(&chars, k, None);
        if bases.is_empty() {
            continue;
        }
        let mut start = k;
        while start > 0 && is_ideograph(chars[start - 1]) {
            start -= 1;
        }
        out.push(LyricRubyChoice {
            open: k as u32,
            is_ruby: false,
            reading: chars[k + 1..k + 1 + len].iter().collect(),
            bases,
            base: (start < k).then_some(start as u32),
        });
    }
    out.sort_by_key(|c| c.open);
    out
}

/// 括弧で書いた脇の字 (被せ・コーラス・歌わない字) の範囲。括弧ごと、スカラー位置で `start..end`。
/// 画面は一段小さく薄く出す。括弧の対応が取れない行は何も返さない (記号として使っている行を壊さない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricAside {
    pub start: u32,
    pub end: u32,
}

pub fn aside_spans(text: &str) -> Vec<LyricAside> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut start = 0usize;
    for (i, &c) in chars.iter().enumerate() {
        if is_open(c) {
            if depth == 0 {
                start = i;
            }
            depth += 1;
        } else if is_close(c) {
            if depth == 0 {
                return Vec::new();
            }
            depth -= 1;
            if depth == 0 {
                out.push(LyricAside { start: start as u32, end: (i + 1) as u32 });
            }
        }
    }
    if depth != 0 {
        return Vec::new();
    }
    out
}

/// 行の本文の範囲 `start..end` を、`split_overlay` の `main` (括弧の外) の中の範囲に置き直す。
/// 範囲がまるごと括弧の中 (被せ) なら `None`。括弧の対応が取れず分けない行はそのまま返す。
/// 歌詞プレイヤーが、メインの行の中でコールの掛かる語に印を付けるのに使う。
pub fn main_range(text: &str, start: u32, end: u32) -> Option<LyricAside> {
    let chars: Vec<char> = text.chars().collect();
    let (start, end) = (start as usize, (end as usize).min(chars.len()));
    if start >= end {
        return None;
    }
    if split_overlay(text).overlay.is_none() {
        return Some(LyricAside { start: start as u32, end: end as u32 });
    }
    // 括弧の外に残る字だけを数える (括弧そのものと中身は main に入らない)。
    let mut depth = 0usize;
    let mut kept = vec![false; chars.len()];
    for (i, &c) in chars.iter().enumerate() {
        if is_open(c) {
            depth += 1;
        } else if is_close(c) {
            depth = depth.saturating_sub(1);
        } else if depth == 0 {
            kept[i] = true;
        }
    }
    if !kept[start..end].iter().any(|&k| k) {
        return None;
    }
    let before = |k: usize| kept[..k].iter().filter(|&&x| x).count() as u32;
    Some(LyricAside { start: before(start), end: before(end) })
}

/// 各スカラーが被せの括弧の内側か。括弧の対応が取れない行は全部 false。
fn inside_overlay_brackets(text: &str) -> Vec<bool> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = vec![false; chars.len()];
    let mut depth = 0usize;
    for (i, &c) in chars.iter().enumerate() {
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
    // 振り仮名 (《》) は括弧ではないので本文に残る (画面が振り仮名として描く)。
    for c in text.chars() {
        if is_open(c) {
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

/// 行の途中で歌う人が変わるところ。`at` (行の本文のスカラー位置) から後ろを `singers` が歌う。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricPartBreak {
    pub at: u32,
    pub singers: Vec<String>,
}

/// 行の中の、同じ人が歌うひと続き (`start..end`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricPartSegment {
    pub start: u32,
    pub end: u32,
    pub singers: Vec<String>,
}

/// 行を歌う人ごとのひと続きに割る。行の頭は `singers`、区切りから後ろはその区切りの人。
/// 行の外・昇順でない区切りは捨てる (保存側で弾くが、古いデータでも壊さない)。
pub fn part_segments(len: u32, singers: &[String], breaks: &[LyricPartBreak]) -> Vec<LyricPartSegment> {
    let mut out = vec![LyricPartSegment { start: 0, end: len, singers: singers.to_vec() }];
    for b in breaks {
        let last = out.last_mut().expect("never empty");
        if b.at <= last.start || b.at >= len {
            continue;
        }
        last.end = b.at;
        out.push(LyricPartSegment { start: b.at, end: len, singers: b.singers.clone() });
    }
    out
}

/// `at` に区切りを置く / 外す。置くときは、その位置で歌っている人を引き継ぐ (あとで付け替える)。
pub fn part_toggle_break(len: u32, singers: &[String], breaks: &[LyricPartBreak], at: u32) -> Vec<LyricPartBreak> {
    if at == 0 || at >= len {
        return breaks.to_vec();
    }
    if breaks.iter().any(|b| b.at == at) {
        return breaks.iter().filter(|b| b.at != at).cloned().collect();
    }
    let current = part_segments(len, singers, breaks)
        .into_iter()
        .find(|s| s.start <= at && at < s.end)
        .map(|s| s.singers)
        .unwrap_or_default();
    let mut out = breaks.to_vec();
    out.push(LyricPartBreak { at, singers: current });
    out.sort_by_key(|b| b.at);
    out
}

/// 塗り替えたあとの、行の頭の歌う人と区切り。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricPartPaint {
    pub singers: Vec<String>,
    pub breaks: Vec<LyricPartBreak>,
}

/// 字の範囲 `start..end` に `idols` (筆。複数人を一度に塗れる) を塗る / 外す
/// (範囲の字がみな筆の全員入りなら外す、そうでなければ足す)。
/// 区切りは塗った結果から作り直す (歌う人が変わる字に置く)。並びは `order` (原唱者の順) にそろえる。
/// タイミング編集で、歌う人を選んでから歌詞の語をタップ・なぞって塗るのに使う。
pub fn part_paint(
    len: u32,
    singers: &[String],
    breaks: &[LyricPartBreak],
    start: u32,
    end: u32,
    idols: &[String],
    order: &[String],
) -> LyricPartPaint {
    let n = len as usize;
    let (start, end) = ((start as usize).min(n), (end as usize).min(n));
    let mut per_char: Vec<Vec<String>> = vec![Vec::new(); n];
    for seg in part_segments(len, singers, breaks) {
        for k in seg.start as usize..seg.end as usize {
            per_char[k] = seg.singers.clone();
        }
    }
    if start < end && !idols.is_empty() {
        let all_have = per_char[start..end].iter().all(|who| idols.iter().all(|i| who.contains(i)));
        let rank = |id: &String| order.iter().position(|o| o == id).unwrap_or(usize::MAX);
        for who in &mut per_char[start..end] {
            if all_have {
                who.retain(|w| !idols.contains(w));
            } else {
                for idol in idols {
                    if !who.contains(idol) {
                        who.push(idol.clone());
                    }
                }
                who.sort_by_key(|id| rank(id));
            }
        }
    }
    let mut out = LyricPartPaint { singers: per_char.first().cloned().unwrap_or_default(), breaks: Vec::new() };
    for k in 1..n {
        if per_char[k] != per_char[k - 1] {
            out.breaks.push(LyricPartBreak { at: k as u32, singers: per_char[k].clone() });
        }
    }
    if n == 0 {
        out.singers = singers.to_vec();
    }
    out
}

/// 行を歌う人をぜんぶ (出てくる順、重複なし)。行の脇の色の帯と、ロック画面に出す。
pub fn part_union(singers: &[String], breaks: &[LyricPartBreak]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for id in singers.iter().chain(breaks.iter().flat_map(|b| b.singers.iter())) {
        if !out.contains(id) {
            out.push(id.clone());
        }
    }
    out
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
    fn ruby_is_written_with_double_angle_brackets() {
        assert_eq!(
            ruby_spans("見本字《みほんじ》の行"),
            vec![LyricRuby { base_start: 0, base_end: 3, open: 3, close: 9, marker: None }]
        );
        // ｜で親字の頭を示す
        assert_eq!(
            ruby_spans("あの｜ダミー《だみ》"),
            vec![LyricRuby { base_start: 3, base_end: 6, open: 6, close: 10, marker: Some(2) }]
        );
        // 括弧は振り仮名ではない・閉じない《は無視
        assert!(ruby_spans("見本（みほん）").is_empty());
        assert!(ruby_spans("見本《みほん").is_empty());
        // 前の振り仮名の後ろから親字を探す
        assert_eq!(ruby_spans("一《いち》二《に》")[1].base_start, 5);
        // 《》を引用の記号にも使っている行: 内側だけが振り仮名
        assert_eq!(
            ruby_spans("《地球《ちきゅう》》"),
            vec![LyricRuby { base_start: 1, base_end: 3, open: 3, close: 9, marker: None }]
        );
        assert!(ruby_spans("《Kick Off！》").is_empty());
    }

    #[test]
    fn ruby_stays_in_main_text_and_brackets_are_overlay() {
        let split = split_overlay("見本字《みほんじ》の行（追いかけ）");
        assert_eq!(split.main, "見本字《みほんじ》の行");
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

    #[test]
    fn ruby_choices_lists_rubies_and_brackets() {
        // 記0憶1抱2《3イ4ダ5》6の7S8T9A10R11（12ほ13し14）15
        let c = ruby_choices("記憶抱《イダ》のSTAR（ほし）");
        assert_eq!(c.len(), 2);
        assert_eq!(c[0], LyricRubyChoice { open: 3, is_ruby: true, reading: "イダ".into(), bases: vec![2, 1, 0], base: Some(0) });
        assert_eq!(c[1].open, 12);
        assert!(!c[1].is_ruby);
        assert_eq!(c[1].reading, "ほし");
        assert_eq!(c[1].base, None);
        assert_eq!(c[1].bases, vec![11, 10, 9, 8, 7]); // 前の「》」は越えない
        // 漢字の直後なら漢字のまとまりが既定、｜は候補から外す
        let k = ruby_choices("あ｜記憶抱《イダ》 見本（みほん）");
        assert_eq!(k[0].bases, vec![4, 3, 2, 0]);
        assert_eq!(k[0].base, Some(2));
        assert_eq!(k[1].base, Some(10));
        // 中身の無い括弧・行頭の括弧は出さない
        assert!(ruby_choices("（あ）と（）").is_empty());
        // かな以外の混じる括弧 (被せ・コーラス) は候補にしない
        assert!(ruby_choices("行です3(追いかけ) 夢（Hi!）").is_empty());
    }

    #[test]
    fn aside_spans_cover_brackets() {
        assert_eq!(aside_spans("調子（で）いい(Hi!)"), vec![LyricAside { start: 2, end: 5 }, LyricAside { start: 7, end: 12 }]);
        assert_eq!(aside_spans("見本《みほん》"), vec![]);
        assert_eq!(aside_spans("壊れ（た"), vec![]);
    }


    #[test]
    fn main_range_maps_into_main_text() {
        // 囲0い1出2す3（4追5い6）7ご8制9圧10
        assert_eq!(main_range("囲い出す（追い）ご制圧", 8, 11), Some(LyricAside { start: 4, end: 7 }));
        assert_eq!(main_range("囲い出す（追い）ご制圧", 5, 7), None);
        assert_eq!(main_range("ご制圧", 0, 3), Some(LyricAside { start: 0, end: 3 }));
    }


    #[test]
    fn part_segments_and_breaks() {
        let a = vec!["a".to_string()];
        let br = |at: u32, who: &str| LyricPartBreak { at, singers: vec![who.to_string()] };
        let segs = part_segments(6, &a, &[br(2, "b"), br(2, "x"), br(9, "y"), br(4, "c")]);
        assert_eq!(segs.iter().map(|s| (s.start, s.end)).collect::<Vec<_>>(), vec![(0, 2), (2, 4), (4, 6)]);
        assert_eq!(segs[1].singers, vec!["b".to_string()]);
        // 置くとその位置の人を引き継ぎ、もう一度で外れる
        let on = part_toggle_break(6, &a, &[br(4, "c")], 2);
        assert_eq!(on, vec![br(2, "a"), br(4, "c")]);
        assert_eq!(part_toggle_break(6, &a, &on, 2), vec![br(4, "c")]);
        assert_eq!(part_toggle_break(6, &a, &[], 0), vec![]);
        assert_eq!(part_union(&a, &[br(2, "b"), br(4, "a")]), vec!["a".to_string(), "b".to_string()]);
    }


    #[test]
    fn part_paint_adds_and_removes() {
        let order: Vec<String> = ["a", "b"].iter().map(|s| s.to_string()).collect();
        // 頭 2 字だけ b を足す → 頭は a,b、2 から a
        let b = vec!["b".to_string()];
        let p = part_paint(5, &["a".to_string()], &[], 0, 2, &b, &order);
        assert_eq!(p.singers, vec!["a".to_string(), "b".to_string()]);
        assert_eq!(p.breaks, vec![LyricPartBreak { at: 2, singers: vec!["a".to_string()] }]);
        // 同じ範囲をもう一度で外れ、区切りも消える
        let q = part_paint(5, &p.singers, &p.breaks, 0, 2, &b, &order);
        assert_eq!(q, LyricPartPaint { singers: vec!["a".to_string()], breaks: vec![] });
        // 空の行に途中だけ塗る
        let r = part_paint(4, &[], &[], 2, 4, &["a".to_string()], &order);
        assert_eq!(r, LyricPartPaint { singers: vec![], breaks: vec![LyricPartBreak { at: 2, singers: vec!["a".to_string()] }] });
        // 全員を一度に塗る → もう一度で全員外れる
        let all = part_paint(3, &["a".to_string()], &[], 0, 3, &order, &order);
        assert_eq!(all.singers, order);
        assert!(part_paint(3, &all.singers, &all.breaks, 0, 3, &order, &order).singers.is_empty());
    }

}
