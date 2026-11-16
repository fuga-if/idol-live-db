//! コール表の画像から読んだ中身を、歌詞の投稿とコールガイドの**下書き**にする規則。
//!
//! 画像を読むのは利用者の ChatGPT プラン ([`crate::agent::tools::call_sheet_reader`])。
//! ここはその答えを受けて、次の 3 つを決める。
//!
//! 1. **読んだ字を疑う** ([`read_sheet`]): モデルは画像に無い歌詞を覚えで補うことがある。
//!    端末の文字認識 (OCR) が同じ画像から拾った字と突き合わせ、裏の取れない行に印を付ける。
//! 2. **歌詞の下書き** ([`lyric_text`]): 歌詞の無い曲で、投稿画面の入力欄に入れる本文。
//! 3. **コールの置き場** ([`place`]): 歌詞のある曲で、読んだコールを今の歌詞の
//!    どの行のどの字に掛けるか。コール表と歌詞カードは改行の位置が違うので、行どうしでは
//!    比べず、歌詞全体を 1 本の字の列にして並べ合わせる。
//!
//! どれも下書きまで。送るのは人が画面で確かめてから (歌詞は投稿ガイドラインへの同意、
//! コールは編集画面の「保存」)。ここから直接どこかへ書くことは無い。

use crate::domain::lyric_sync::ruby_spans;
use imas_text_fold::fold_kana;
use serde_json::Value;
use std::collections::HashSet;

/// 1 回に読ませる画像の上限。
pub const MAX_IMAGES: usize = 4;
/// 1 行に付けられるコールの上限 (Worker の `MAX_CALLS_PER_LINE` と同じ)。
const MAX_CALLS_PER_LINE: usize = 20;
/// 1 曲に付けられるコールの上限 (Worker の `MAX_CALLS_PER_SONG` と同じ)。
const MAX_CALLS_PER_SONG: usize = 600;
/// コールの文言の上限 (Worker の `MAX_CALL_TEXT_CHARS` と同じ)。
const MAX_CALL_TEXT_CHARS: usize = 200;
/// 読んだ行の上限 (これより長い答えは切る)。
const MAX_SHEET_LINES: usize = 400;
/// 並べ合わせる字の列の上限 (片側)。超える歌詞は置き場を決めない。
const MAX_ALIGN_CHARS: usize = 3000;
/// OCR の字と重なる割合がこれ未満の行・コールは「裏が取れない」。
const OCR_SUPPORT_MIN: f32 = 0.5;
/// コールの掛かる字のうち、今の歌詞と合った割合がこれ未満なら置かない。
const PLACE_SUPPORT_MIN: f32 = 0.5;

/// 読んだコール 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SheetCall {
    /// コールの文言 (画像に書いてあるとおり)。
    pub text: String,
    /// そのコールが掛かる歌詞の断片 (真上の字。隙間のコールは直前の字)。
    pub anchor: String,
    /// "over" (歌に被せる) か "after" (歌のあとに返す)。
    pub timing: String,
    /// 端末の文字認識で裏が取れなかった (画像と見比べてもらう)。
    pub doubtful: bool,
}

/// 読んだ歌詞 1 行と、その行のコール。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SheetLine {
    pub lyric: String,
    /// この行の前に空行がある (塊の変わり目)。
    pub break_before: bool,
    /// 行頭の手拍子の指示 ("back_beat" / "four_on_floor" / "ppph")。無ければ None。
    pub clap: Option<String>,
    pub calls: Vec<SheetCall>,
    /// 端末の文字認識で裏が取れなかった歌詞の行。
    pub doubtful: bool,
}

/// 画像から読んだ中身。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CallSheetReading {
    pub lines: Vec<SheetLine>,
    /// 端末の文字認識と突き合わせられたか (OCR が空なら false で、印は付かない)。
    pub ocr_checked: bool,
    /// 読んだコールの数。
    pub call_count: u32,
    /// 裏の取れなかった歌詞の行の数。
    pub doubtful_lines: u32,
}

/// 今の歌詞の 1 行 (本文の行だけを、表示順に渡す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ImportTargetLine {
    pub id: String,
    /// 行の本文 (読み仮名の記法が入ったまま)。
    pub text: String,
    pub has_clap: bool,
    pub calls: Vec<ImportExistingCall>,
}

/// 今その行に付いているコール (同じものを二重に足さないために渡す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ImportExistingCall {
    pub start: u32,
    pub end: u32,
    pub text: String,
}

/// 置き場の決まったコール。位置は行の本文の Unicode スカラー単位 (終わりは含まない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PlacedCall {
    pub line_id: String,
    pub start: u32,
    pub end: u32,
    pub anchor_text: String,
    pub text: String,
    pub timing: String,
    pub doubtful: bool,
}

/// 置き場の決まった手拍子。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PlacedClap {
    pub line_id: String,
    pub clap: String,
}

/// 置き場の決まらなかったコール (人が手で付ける)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UnplacedCall {
    pub text: String,
    /// コール表でそのコールがあった歌詞の行。
    pub near: String,
}

/// コールを今の歌詞に当てた結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CallSheetPlacement {
    pub calls: Vec<PlacedCall>,
    pub claps: Vec<PlacedClap>,
    pub unplaced: Vec<UnplacedCall>,
    /// もう同じものが付いていて足さなかった数。
    pub already: u32,
    /// 画面に出すまとめの 1 行。
    pub summary: String,
}

// ---------------------------------------------------------------------------
// 字の畳み方
// ---------------------------------------------------------------------------

/// 並べ合わせ・突き合わせに使う 1 字。字でないもの (空白・記号) は None。
///
/// 全角の英数字は半角へ、大文字は小文字へ、カタカナはひらがなへ畳む。コール表と歌詞カードでは
/// 「！」の幅や空白の入れ方が揃わないので、記号は比べない。
fn norm_char(c: char) -> Option<char> {
    let c = match c {
        '\u{FF01}'..='\u{FF5E}' => char::from_u32(c as u32 - 0xFEE0).unwrap_or(c),
        _ => c,
    };
    if !c.is_alphanumeric() {
        return None;
    }
    Some(fold_kana(c.to_lowercase().next().unwrap_or(c)))
}

fn norm(text: &str) -> Vec<char> {
    text.chars().filter_map(norm_char).collect()
}

/// 隣り合う 2 字の組 (1 字しか無ければその 1 字)。
fn bigrams(chars: &[char]) -> Vec<(char, char)> {
    match chars {
        [] => Vec::new(),
        [only] => vec![(*only, '\0')],
        _ => chars.windows(2).map(|w| (w[0], w[1])).collect(),
    }
}

/// `chars` の 2 字の組のうち、OCR の字にもある割合。
fn support(chars: &[char], ocr: &HashSet<(char, char)>, ocr_single: &HashSet<char>) -> f32 {
    let grams = bigrams(chars);
    if grams.is_empty() {
        return 1.0;
    }
    let hit = grams.iter().filter(|g| if g.1 == '\0' { ocr_single.contains(&g.0) } else { ocr.contains(g) }).count();
    hit as f32 / grams.len() as f32
}

// ---------------------------------------------------------------------------
// 読む
// ---------------------------------------------------------------------------

fn clip(text: &str, max: usize) -> String {
    let one_line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    one_line.chars().take(max).collect()
}

fn parse_clap(value: &Value) -> Option<String> {
    match value.as_str()? {
        c @ ("back_beat" | "four_on_floor" | "ppph") => Some(c.to_string()),
        _ => None,
    }
}

/// モデルの答え (JSON) を読み、端末の文字認識の字 (`ocr_text`) と突き合わせる。
///
/// 答えが読めない・歌詞が 1 行も無いなら None。`ocr_text` が空なら突き合わせず、印は付けない
/// (`ocr_checked` が false になる。画面はその旨を出す)。
pub fn read_sheet(answer: &Value, ocr_text: &str) -> Option<CallSheetReading> {
    let ocr_chars = norm(ocr_text);
    let ocr_checked = !ocr_chars.is_empty();
    let ocr: HashSet<(char, char)> = ocr_chars.windows(2).map(|w| (w[0], w[1])).collect();
    let ocr_single: HashSet<char> = ocr_chars.iter().copied().collect();
    let unsupported = |text: &str| ocr_checked && support(&norm(text), &ocr, &ocr_single) < OCR_SUPPORT_MIN;

    let mut lines = Vec::new();
    for raw in answer["lines"].as_array()?.iter().take(MAX_SHEET_LINES) {
        let lyric = clip(raw["lyric"].as_str().unwrap_or(""), 400);
        if norm(&lyric).is_empty() {
            continue;
        }
        let calls: Vec<SheetCall> = raw["calls"]
            .as_array()
            .map(|a| a.as_slice())
            .unwrap_or(&[])
            .iter()
            .filter_map(|c| {
                let text = clip(c["text"].as_str()?, MAX_CALL_TEXT_CHARS);
                if text.is_empty() {
                    return None;
                }
                let timing = if c["timing"].as_str() == Some("over") { "over" } else { "after" };
                Some(SheetCall {
                    doubtful: unsupported(&text),
                    text,
                    anchor: clip(c["anchor"].as_str().unwrap_or(""), 200),
                    timing: timing.to_string(),
                })
            })
            .take(MAX_CALLS_PER_LINE)
            .collect();
        lines.push(SheetLine {
            doubtful: unsupported(&lyric),
            lyric,
            break_before: raw["break_before"].as_bool().unwrap_or(false) && !lines.is_empty(),
            clap: parse_clap(&raw["clap"]),
            calls,
        });
    }
    if lines.is_empty() {
        return None;
    }
    Some(CallSheetReading {
        call_count: lines.iter().map(|l| l.calls.len() as u32).sum(),
        doubtful_lines: lines.iter().filter(|l| l.doubtful).count() as u32,
        lines,
        ocr_checked,
    })
}

/// 歌詞の投稿画面の入力欄に入れる本文 (1 行ずつ、塊の間は空行)。
pub fn lyric_text(reading: &CallSheetReading) -> String {
    // 文字認識で確かめられていない読み取りは、覚えで補った歌詞と見分けられないので下書きにしない。
    if !reading.ocr_checked {
        return String::new();
    }
    let mut out = String::new();
    // 外した行の前後は塊の切れ目にする (行が抜けたことが入力欄で分かるように)。
    let mut gap = false;
    for line in &reading.lines {
        if line.doubtful {
            gap = true;
            continue;
        }
        if !out.is_empty() {
            out.push('\n');
            if line.break_before || gap {
                out.push('\n');
            }
        }
        gap = false;
        out.push_str(&line.lyric);
    }
    out
}

/// 歌詞の下書きに入る行の数 (文字認識で確かめられた行)。0 なら歌詞の下書きは作れない。
pub fn lyric_line_count(reading: &CallSheetReading) -> u32 {
    if !reading.ocr_checked {
        return 0;
    }
    reading.lines.iter().filter(|l| !l.doubtful).count() as u32
}

// ---------------------------------------------------------------------------
// 置く
// ---------------------------------------------------------------------------

/// 今の歌詞を 1 本の字の列にしたもの。各字が、どの行の何文字目 (スカラー) から来たかを持つ。
struct TargetStream {
    chars: Vec<char>,
    /// (行の番号, 行の中のスカラー位置)
    origin: Vec<(usize, usize)>,
    /// 行ごとの本文のスカラー。
    line_chars: Vec<Vec<char>>,
    /// 行ごとの、読み仮名 (親字の終わり → 《》の終わり)。範囲の終わりを読み仮名の後ろへ延ばすのに使う。
    ruby_ends: Vec<Vec<(usize, usize)>>,
}

fn target_stream(lines: &[ImportTargetLine]) -> TargetStream {
    let mut stream = TargetStream { chars: Vec::new(), origin: Vec::new(), line_chars: Vec::new(), ruby_ends: Vec::new() };
    for (index, line) in lines.iter().enumerate() {
        let chars: Vec<char> = line.text.chars().collect();
        let spans = ruby_spans(&line.text);
        // 読み (《…》) と親字の頭の印 (｜) は歌われる字ではないので、列に入れない。
        let skipped = |at: usize| {
            spans.iter().any(|s| (s.open as usize..s.close as usize).contains(&at) || s.marker == Some(at as u32))
        };
        for (at, &c) in chars.iter().enumerate() {
            if skipped(at) {
                continue;
            }
            if let Some(n) = norm_char(c) {
                stream.chars.push(n);
                stream.origin.push((index, at));
            }
        }
        stream.ruby_ends.push(spans.iter().map(|s| (s.base_end as usize, s.close as usize)).collect());
        stream.line_chars.push(chars);
    }
    stream
}

/// 読んだ歌詞を 1 本の字の列にしたもの。各コールが列のどこに掛かるかを持つ。
struct ReadStream {
    chars: Vec<char>,
    /// (読んだ行の番号, コールの番号, 掛かる場所)。場所は (範囲のある読んだ行, 始まり, 終わり) で、
    /// 範囲が空なら「その位置のあと」。断片がどこにも無ければ None (置かない)。
    calls: Vec<(usize, usize, Option<(usize, usize, usize)>)>,
    /// 読んだ行ごとの、列の中の範囲。
    line_ranges: Vec<(usize, usize)>,
}

/// `needle` を `hay` の `from` 以降から探す。
fn find_from(hay: &[char], needle: &[char], from: usize) -> Option<usize> {
    if needle.is_empty() || needle.len() > hay.len() {
        return None;
    }
    (from.min(hay.len())..=hay.len() - needle.len()).find(|&i| hay[i..i + needle.len()] == *needle)
}

fn read_stream(reading: &CallSheetReading) -> ReadStream {
    let mut stream = ReadStream { chars: Vec::new(), calls: Vec::new(), line_ranges: Vec::new() };
    for (li, line) in reading.lines.iter().enumerate() {
        let base = stream.chars.len();
        let chars = norm(&line.lyric);
        // コールは左から順に並んでいる。同じ断片が 1 行に 2 度出るので、前のコールより後ろから探す。
        let mut cursor = 0usize;
        for (ci, call) in line.calls.iter().enumerate() {
            let anchor = norm(&call.anchor);
            let found = find_from(&chars, &anchor, cursor).or_else(|| find_from(&chars, &anchor, 0));
            let place = match found {
                Some(at) => {
                    cursor = at + anchor.len();
                    Some((li, base + at, base + at + anchor.len()))
                }
                // 断片の無いコールは、行の終わりのあとに返すコールとして扱う。
                None if anchor.is_empty() => Some((li, base + chars.len(), base + chars.len())),
                // 歌の隙間のコールは「直前の歌詞の断片」で来る。行頭なら断片は前の行にあるので、
                // 前の行のその断片のあとに置く。どこにも無ければ置かない。
                None => li.checked_sub(1).and_then(|prev| {
                    let (start, end) = stream.line_ranges[prev];
                    let hay = &stream.chars[start..end];
                    (0..=hay.len().checked_sub(anchor.len())?)
                        .rev()
                        .find(|&i| hay[i..i + anchor.len()] == anchor[..])
                        .map(|i| (prev, start + i + anchor.len(), start + i + anchor.len()))
                }),
            };
            stream.calls.push((li, ci, place));
        }
        stream.chars.extend(chars.iter());
        stream.line_ranges.push((base, stream.chars.len()));
    }
    stream
}

/// 2 本の字の列を並べ合わせ、`read` の各字が `target` のどの字に合ったかを返す (合わなければ None)。
///
/// 全体を 1 度に並べる (改行の位置の違い・片方にしか無い括弧書きを飛ばせるように)。
/// 一致 +2・不一致 -1・飛ばし -1。
fn align(read: &[char], target: &[char]) -> Vec<Option<usize>> {
    const DIAG: u8 = 0;
    const UP: u8 = 1;
    const LEFT: u8 = 2;
    let (n, m) = (read.len(), target.len());
    let mut from = vec![LEFT; (n + 1) * (m + 1)];
    let mut prev: Vec<i32> = (0..=m as i32).map(|j| -j).collect();
    let mut row = vec![0i32; m + 1];
    for i in 1..=n {
        row[0] = -(i as i32);
        from[i * (m + 1)] = UP;
        for j in 1..=m {
            let diag = prev[j - 1] + if read[i - 1] == target[j - 1] { 2 } else { -1 };
            let up = prev[j] - 1;
            let left = row[j - 1] - 1;
            let (best, dir) = if diag >= up && diag >= left {
                (diag, DIAG)
            } else if up >= left {
                (up, UP)
            } else {
                (left, LEFT)
            };
            row[j] = best;
            from[i * (m + 1) + j] = dir;
        }
        std::mem::swap(&mut prev, &mut row);
    }
    let mut map = vec![None; n];
    let (mut i, mut j) = (n, m);
    while i > 0 && j > 0 {
        match from[i * (m + 1) + j] {
            DIAG => {
                if read[i - 1] == target[j - 1] {
                    map[i - 1] = Some(j - 1);
                }
                i -= 1;
                j -= 1;
            }
            UP => i -= 1,
            _ => j -= 1,
        }
    }
    map
}

fn summary(placed: usize, claps: usize, unplaced: usize, already: u32) -> String {
    if placed == 0 && claps == 0 {
        return if already > 0 {
            "読んだコールは、もう全部付いています".into()
        } else {
            "今の歌詞に当てられるコールがありませんでした".into()
        };
    }
    let mut parts = vec![format!("コール {placed} 件を歌詞に当てました")];
    if claps > 0 {
        parts.push(format!("手拍子 {claps} 行"));
    }
    if unplaced > 0 {
        parts.push(format!("{unplaced} 件は場所が決まらず入れていません"));
    }
    if already > 0 {
        parts.push(format!("{already} 件はもう付いていました"));
    }
    parts.join("。")
}

/// 読んだコールを、今の歌詞 (`lines`。本文の行だけ、表示順) に当てる。
///
/// 掛かる字の半分以上が今の歌詞と合ったコールだけを置く。合わないものは `unplaced` に回し、
/// 勝手にそれらしい場所へは置かない。同じ場所に同じ文言がもう付いていれば足さない。
pub fn place(reading: &CallSheetReading, lines: &[ImportTargetLine]) -> CallSheetPlacement {
    let target = target_stream(lines);
    let read = read_stream(reading);
    let mut placement =
        CallSheetPlacement { calls: Vec::new(), claps: Vec::new(), unplaced: Vec::new(), already: 0, summary: String::new() };
    let too_long = read.chars.len() > MAX_ALIGN_CHARS || target.chars.len() > MAX_ALIGN_CHARS;
    let map = if too_long || target.chars.is_empty() { vec![None; read.chars.len()] } else { align(&read.chars, &target.chars) };

    // 読んだ行そのものが今の歌詞に合っているか。たまたま 1 字 (「の」「た」) が合っただけの行に、
    // 幅の無いコールや手拍子を置かない。
    let line_matched: Vec<bool> = read
        .line_ranges
        .iter()
        .map(|&(start, end)| {
            let hit = map[start..end].iter().flatten().count();
            end > start && hit as f32 >= (end - start) as f32 * PLACE_SUPPORT_MIN
        })
        .collect();

    let mut per_line: Vec<usize> = lines.iter().map(|l| l.calls.len()).collect();
    let mut total: usize = per_line.iter().sum();

    for &(li, ci, place) in &read.calls {
        let sheet_line = &reading.lines[li];
        let call = &sheet_line.calls[ci];
        let unplaced = |p: &mut CallSheetPlacement| {
            p.unplaced.push(UnplacedCall { text: call.text.clone(), near: sheet_line.lyric.clone() })
        };
        let Some((home, start, end)) = place else {
            unplaced(&mut placement);
            continue;
        };

        // 掛かる字 (幅があるとき) か、その直前の字 (幅が無いとき) が、今の歌詞のどこに合ったか。
        let matched: Vec<usize> = if end > start {
            map[start..end].iter().flatten().copied().collect()
        } else {
            let (line_start, _) = read.line_ranges[home];
            map[line_start..start].iter().rev().flatten().take(1).copied().collect()
        };
        let enough = if end > start {
            matched.len() as f32 >= (end - start) as f32 * PLACE_SUPPORT_MIN
        } else {
            line_matched[home] && !matched.is_empty()
        };
        if !enough {
            unplaced(&mut placement);
            continue;
        }
        // いちばん多く合った行に置く (行をまたいだら、多いほう)。
        let mut votes: Vec<(usize, usize)> = Vec::new();
        for &t in &matched {
            let line = target.origin[t].0;
            match votes.iter_mut().find(|v| v.0 == line) {
                Some(v) => v.1 += 1,
                None => votes.push((line, 1)),
            }
        }
        let line_index = votes.iter().max_by_key(|v| v.1).map(|v| v.0).unwrap_or(0);
        let line_chars = &target.line_chars[line_index];
        let in_line: Vec<usize> = matched.iter().filter(|&&t| target.origin[t].0 == line_index).map(|&t| target.origin[t].1).collect();
        let (from, to) = if end > start {
            let first = *in_line.iter().min().unwrap_or(&0);
            let mut last = in_line.iter().max().map(|l| l + 1).unwrap_or(first);
            // 親字の終わりで切れたら、読み仮名の後ろまで延ばす (読み仮名を残して切らない)。
            if let Some(&(_, close)) = target.ruby_ends[line_index].iter().find(|r| r.0 == last) {
                last = close;
            }
            (first, last)
        } else {
            // 掛かる字の無いコールは、直前に合った字のあとに返す (読んだ行の終わりなら、合った行のその位置)。
            let mut at = in_line.iter().max().map(|l| l + 1).unwrap_or(line_chars.len());
            if let Some(&(_, close)) = target.ruby_ends[line_index].iter().find(|r| r.0 == at) {
                at = close;
            }
            // あとに続くのが記号や空白だけなら行末まで送る (「左!」の「!」の前で切らない)。
            if line_chars[at..].iter().all(|c| norm_char(*c).is_none()) {
                at = line_chars.len();
            }
            (at, at)
        };
        let timing = if to > from { call.timing.as_str() } else { "after" };

        let existing = &lines[line_index];
        let same = norm(&call.text);
        if existing.calls.iter().any(|e| e.start as usize == from && e.end as usize == to && norm(&e.text) == same)
            || placement.calls.iter().any(|p| {
                p.line_id == existing.id && p.start as usize == from && p.end as usize == to && norm(&p.text) == same
            })
        {
            placement.already += 1;
            continue;
        }
        if per_line[line_index] >= MAX_CALLS_PER_LINE || total >= MAX_CALLS_PER_SONG {
            unplaced(&mut placement);
            continue;
        }
        per_line[line_index] += 1;
        total += 1;
        placement.calls.push(PlacedCall {
            line_id: existing.id.clone(),
            start: from as u32,
            end: to as u32,
            anchor_text: line_chars[from..to].iter().collect(),
            text: call.text.clone(),
            timing: timing.to_string(),
            doubtful: call.doubtful,
        });
    }

    // 手拍子は、読んだ行の頭の字が合った行へ (まだ指定の無い行だけ)。
    for (li, sheet_line) in reading.lines.iter().enumerate() {
        let Some(clap) = &sheet_line.clap else { continue };
        if !line_matched[li] {
            continue;
        }
        let (start, end) = read.line_ranges[li];
        let Some(t) = map[start..end].iter().flatten().next() else { continue };
        let line = &lines[target.origin[*t].0];
        if !line.has_clap && !placement.claps.iter().any(|c| c.line_id == line.id) {
            placement.claps.push(PlacedClap { line_id: line.id.clone(), clap: clap.clone() });
        }
    }

    placement.summary = summary(placement.calls.len(), placement.claps.len(), placement.unplaced.len(), placement.already);
    placement
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sheet() -> Value {
        json!({ "lines": [
            { "lyric": "(Hey！ Hey！) これじゃつまんないね (Hey！ Hey！)", "break_before": false, "clap": null, "calls": [
                { "text": "Hey！ Hey！", "anchor": "Hey！ Hey！", "timing": "over" },
                { "text": "Hey！ Hey！", "anchor": "Hey！ Hey！", "timing": "over" },
            ]},
            { "lyric": "震いに震えた上司の怒号　右から左！", "break_before": true, "clap": "ppph", "calls": [
                { "text": "ボス！", "anchor": "上司", "timing": "after" },
                { "text": "いっせーのっ", "anchor": "どこにも無い字", "timing": "over" },
            ]},
        ]})
    }

    fn target(id: &str, text: &str) -> ImportTargetLine {
        ImportTargetLine { id: id.into(), text: text.into(), has_clap: false, calls: Vec::new() }
    }

    #[test]
    fn 読んだ行とコールを数える() {
        let r = read_sheet(&sheet(), "").unwrap();
        assert_eq!(r.lines.len(), 2);
        assert_eq!(r.call_count, 4);
        assert!(!r.ocr_checked && r.doubtful_lines == 0);
        assert!(r.lines[1].break_before && r.lines[1].clap.as_deref() == Some("ppph"));
        assert!(read_sheet(&json!({ "lines": [] }), "").is_none());
        assert!(read_sheet(&json!({ "lines": [{ "lyric": "！？", "calls": [] }] }), "").is_none());
    }

    #[test]
    fn 文字認識に無い行は疑う() {
        // OCR は 1 行目しか拾っていない (幅と空白が違っても合う)。
        let r = read_sheet(&sheet(), "（Ｈｅｙ! Hey!）これじゃ つまんないね(Hey! Hey!)").unwrap();
        assert!(r.ocr_checked);
        assert!(!r.lines[0].doubtful && r.lines[1].doubtful);
        assert_eq!(r.doubtful_lines, 1);
        assert!(!r.lines[0].calls[0].doubtful && r.lines[1].calls[0].doubtful);
    }

    #[test]
    fn 歌詞の下書きは塊の間に空行() {
        let both = "(Hey! Hey!) これじゃつまんないね (Hey! Hey!) 震いに震えた上司の怒号 右から左!";
        let r = read_sheet(&sheet(), both).unwrap();
        assert_eq!(lyric_text(&r), "(Hey！ Hey！) これじゃつまんないね (Hey！ Hey！)\n\n震いに震えた上司の怒号 右から左！");
        assert_eq!(lyric_line_count(&r), 2);
    }

    #[test]
    fn 確かめられない行は歌詞の下書きに入れない() {
        // 文字認識が 1 行目しか拾っていない: 2 行目は覚えで補ったものと見分けられない。
        let r = read_sheet(&sheet(), "(Hey! Hey!) これじゃつまんないね (Hey! Hey!)").unwrap();
        assert_eq!(lyric_text(&r), "(Hey！ Hey！) これじゃつまんないね (Hey！ Hey！)");
        assert_eq!(lyric_line_count(&r), 1);
        // 文字認識が何も拾えなければ、歌詞の下書きは作らない (コールは別)。
        let unchecked = read_sheet(&sheet(), "").unwrap();
        assert_eq!((lyric_text(&unchecked).as_str(), lyric_line_count(&unchecked)), ("", 0));
    }

    #[test]
    fn 行頭の隙間のコールは前の行の断片のあとに置く() {
        let answer = json!({ "lines": [
            { "lyric": "右から左", "break_before": false, "clap": null, "calls": [] },
            { "lyric": "いつまでも", "break_before": false, "clap": null, "calls": [
                { "text": "ハイ！", "anchor": "左", "timing": "after" },
                { "text": "どこ？", "anchor": "どこにも無い", "timing": "after" },
            ]},
        ]});
        let p = place(&read_sheet(&answer, "").unwrap(), &[target("e", "右から左!"), target("f", "いつまでも")]);
        assert_eq!(p.calls.len(), 1, "{p:?}");
        assert_eq!((p.calls[0].line_id.as_str(), p.calls[0].start, p.calls[0].end), ("e", 5, 5));
        assert_eq!(p.unplaced.len(), 1);
    }

    #[test]
    fn 改行の違う歌詞に当てる() {
        let r = read_sheet(&sheet(), "").unwrap();
        // 歌詞カードは括弧書きを別の行にし、上司に読み仮名がある。
        let lines = vec![
            target("a", "(Hey! Hey!)"),
            target("b", "これじゃつまんないね"),
            target("c", "(Hey! Hey!)"),
            target("d", "震いに震えた上司《ボス》の怒号"),
            target("e", "右から左!"),
        ];
        let p = place(&r, &lines);
        assert_eq!(p.calls.len(), 3, "{p:?}");
        // 同じ断片の 2 つは、1 つ目と 2 つ目の括弧に分かれる。
        assert_eq!((p.calls[0].line_id.as_str(), p.calls[0].anchor_text.as_str()), ("a", "Hey! Hey"));
        assert_eq!(p.calls[1].line_id, "c");
        assert_eq!(p.calls[0].timing, "over");
        // 親字の終わりで切れたら読み仮名の後ろまで。
        assert_eq!((p.calls[2].line_id.as_str(), p.calls[2].anchor_text.as_str()), ("d", "上司《ボス》"));
        // 断片がその行にも前の行にも無いコールは、当て推量で置かない。
        assert_eq!(p.unplaced.len(), 1);
        // 手拍子は読んだ行の頭が合った行へ。
        assert_eq!(p.claps, vec![PlacedClap { line_id: "d".into(), clap: "ppph".into() }]);
    }

    #[test]
    fn 断片の無いコールは行末のあとに返す() {
        let answer = json!({ "lines": [{ "lyric": "右から左", "break_before": false, "clap": null, "calls": [
            { "text": "いっせーのっ", "anchor": "", "timing": "over" },
        ]}]});
        let p = place(&read_sheet(&answer, "").unwrap(), &[target("e", "右から左!")]);
        assert_eq!(p.calls.len(), 1);
        assert_eq!((p.calls[0].start, p.calls[0].end, p.calls[0].timing.as_str()), (5, 5, "after"));
    }

    #[test]
    fn 歌詞と合わないコールは置かない() {
        let r = read_sheet(&sheet(), "").unwrap();
        let p = place(&r, &[target("x", "まったく別の曲の歌詞です")]);
        assert!(p.calls.is_empty() && p.claps.is_empty());
        assert_eq!(p.unplaced.len(), 4);
        assert!(p.summary.contains("ありません"));
    }

    #[test]
    fn 同じコールは二重に足さない() {
        let r = read_sheet(&sheet(), "").unwrap();
        let mut a = target("a", "(Hey! Hey!)");
        a.calls.push(ImportExistingCall { start: 1, end: 9, text: "hey! hey!".into() });
        let lines = vec![a, target("b", "これじゃつまんないね"), target("c", "(Hey! Hey!)")];
        let p = place(&r, &lines);
        assert_eq!(p.already, 1);
        assert!(p.calls.iter().all(|c| c.line_id != "a"));
    }
}
