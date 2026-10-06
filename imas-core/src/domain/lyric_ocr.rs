//! 歌詞カードの文字認識 (OCR) の結果を、歌詞の行に並べ直す。
//!
//! 認識そのものは端末の OS (iOS は Vision、Android は ML Kit) が端末の中で行い、
//! 文字列と枠 (左上原点) の片の並びをここへ渡す。OS の返す順番は段組みや縦書きで崩れるので、
//! 枠の位置だけから読み順を作り直す。手順は `tools/lyrics/src/Layout.swift` (CLI) と同じ:
//!
//! 1. 縦書き / 横書きを判定する (2 文字以上の片の、文字数で重み付けした多数決)。
//! 2. 本文より明らかに小さい片 (ルビ) を外す。
//! 3. 段組みを 1 軸で切る (横書きは左右の段、縦書きは上下の段)。
//! 4. 段の中で行をまとめ、横書きは上→下、縦書きは右→左に並べる。行送りが広く空いた所に空行を入れる。
//!
//! 認識した字は足しも直しもしない (歌詞を AI や規則で書き換えない)。結果は入力欄に入れて本人が見直す。

/// 認識した文字列 1 片と、その枠 (左上原点。単位は画素でも 0〜1 でもよいが 1 枚の中で揃える)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct OcrPiece {
    pub text: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricOcrLayout {
    /// 並べ直した本文 (行は `\n`、まとまりの間は空行)。
    pub text: String,
    /// 縦書きと判定したか。
    pub vertical: bool,
    /// ルビとして外した片の数。
    pub dropped_ruby: u32,
}

const RUBY_RATIO: f64 = 0.62;
const GUTTER_CHAR_UNITS: f64 = 3.0;
const LINE_TOLERANCE_CHAR_UNITS: f64 = 0.7;
const SPACE_GAP_CHAR_UNITS: f64 = 0.8;
/// 行送りが中央値のこの倍を超えたら、まとまりの切れ目として空行を入れる。
const PARAGRAPH_GAP_RATIO: f64 = 1.6;

struct Piece<'a> {
    text: &'a str,
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
    chars: usize,
}

impl Piece<'_> {
    fn char_size(&self, vertical: bool) -> f64 {
        if vertical { self.max_x - self.min_x } else { self.max_y - self.min_y }
    }
    /// 読み進む向きの座標。
    fn along(&self, vertical: bool) -> f64 {
        if vertical { self.min_y } else { self.min_x }
    }
    fn along_end(&self, vertical: bool) -> f64 {
        if vertical { self.max_y } else { self.max_x }
    }
    /// 次の行へ移る向きの座標 (中心)。
    fn across(&self, vertical: bool) -> f64 {
        if vertical { (self.min_x + self.max_x) / 2.0 } else { (self.min_y + self.max_y) / 2.0 }
    }
}

fn detect_vertical(pieces: &[Piece]) -> bool {
    let (mut v, mut h) = (0usize, 0usize);
    for p in pieces.iter().filter(|p| p.chars >= 2) {
        let (w, ht) = (p.max_x - p.min_x, p.max_y - p.min_y);
        if ht > w * 1.2 {
            v += p.chars;
        } else if w > ht * 1.2 {
            h += p.chars;
        }
    }
    v > h
}

/// 文字数で重み付けした文字の大きさの中央値 (長い片の大きさを信頼する)。
fn median_char_size(pieces: &[&Piece], vertical: bool) -> f64 {
    let mut samples: Vec<f64> = Vec::new();
    for p in pieces {
        let s = p.char_size(vertical);
        samples.extend(std::iter::repeat_n(s, p.chars.clamp(1, 40)));
    }
    if samples.is_empty() {
        return 1.0;
    }
    samples.sort_by(f64::total_cmp);
    samples[samples.len() / 2]
}

/// 段組みの谷 (片の無い帯) で切る。横書きは x、縦書きは y。小さい座標の段が先。
fn split_blocks<'a, 'b>(pieces: Vec<&'b Piece<'a>>, vertical: bool, gutter: f64) -> Vec<Vec<&'b Piece<'a>>> {
    if pieces.len() < 2 {
        return if pieces.is_empty() { Vec::new() } else { vec![pieces] };
    }
    let mut spans: Vec<(f64, f64)> = pieces
        .iter()
        .map(|p| if vertical { (p.min_y, p.max_y) } else { (p.min_x, p.max_x) })
        .collect();
    spans.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut cuts: Vec<f64> = Vec::new();
    let mut reach = spans[0].1;
    for &(lo, hi) in &spans[1..] {
        if lo - reach >= gutter {
            cuts.push((lo + reach) / 2.0);
        }
        reach = reach.max(hi);
    }
    let mut buckets: Vec<Vec<&Piece>> = vec![Vec::new(); cuts.len() + 1];
    for p in pieces {
        let center = if vertical { (p.min_y + p.max_y) / 2.0 } else { (p.min_x + p.max_x) / 2.0 };
        let idx = cuts.iter().take_while(|&&c| center > c).count();
        buckets[idx].push(p);
    }
    buckets.retain(|b| !b.is_empty());
    buckets
}

/// 段の中の行を作る。戻り値は (行の文字列, 行送り方向の位置) の並び。
fn build_lines(mut pieces: Vec<&Piece>, vertical: bool, median: f64) -> Vec<(String, f64)> {
    let tolerance = (median * LINE_TOLERANCE_CHAR_UNITS).max(f64::EPSILON);
    pieces.sort_by(|a, b| {
        let (av, bv) = (a.across(vertical), b.across(vertical));
        let primary = if vertical { bv.total_cmp(&av) } else { av.total_cmp(&bv) };
        primary.then(a.along(vertical).total_cmp(&b.along(vertical)))
    });
    let mut groups: Vec<Vec<&Piece>> = Vec::new();
    let mut anchor = 0.0;
    for p in pieces {
        let v = p.across(vertical);
        match groups.last_mut() {
            Some(g) if (v - anchor).abs() <= tolerance => {
                g.push(p);
                // 少し傾いた写真に追随するため、基準は行の平均に寄せる。
                anchor = g.iter().map(|q| q.across(vertical)).sum::<f64>() / g.len() as f64;
            }
            _ => {
                groups.push(vec![p]);
                anchor = v;
            }
        }
    }
    groups
        .into_iter()
        .map(|mut g| {
            g.sort_by(|a, b| a.along(vertical).total_cmp(&b.along(vertical)));
            let mut text = String::new();
            let mut prev_end: Option<f64> = None;
            for p in &g {
                if let Some(end) = prev_end {
                    if p.along(vertical) - end > median * SPACE_GAP_CHAR_UNITS {
                        text.push(' ');
                    }
                }
                text.push_str(p.text.trim());
                prev_end = Some(p.along_end(vertical));
            }
            let across = g.iter().map(|q| q.across(vertical)).sum::<f64>() / g.len() as f64;
            (text, across)
        })
        .collect()
}

/// 行送りの中央値より大きく空いた所に空行を入れて、段の行を文字列にする。
fn join_with_paragraphs(lines: &[(String, f64)]) -> Vec<String> {
    let mut pitches: Vec<f64> = lines.windows(2).map(|w| (w[1].1 - w[0].1).abs()).collect();
    pitches.sort_by(f64::total_cmp);
    // 下側の中央値。行が少ないと (2 つの間隔なら) 上側を取って切れ目を見落とすため。
    let median_pitch = pitches.get(pitches.len().saturating_sub(1) / 2).copied().unwrap_or(0.0);
    let mut out = Vec::new();
    for (i, (text, across)) in lines.iter().enumerate() {
        if i > 0 && median_pitch > 0.0 && (across - lines[i - 1].1).abs() > median_pitch * PARAGRAPH_GAP_RATIO {
            out.push(String::new());
        }
        out.push(text.clone());
    }
    out
}

pub fn layout(pieces: &[OcrPiece]) -> LyricOcrLayout {
    let parsed: Vec<Piece> = pieces
        .iter()
        .filter(|p| !p.text.trim().is_empty() && p.width > 0.0 && p.height > 0.0)
        .map(|p| Piece {
            text: p.text.as_str(),
            min_x: p.x,
            min_y: p.y,
            max_x: p.x + p.width,
            max_y: p.y + p.height,
            chars: p.text.trim().chars().count(),
        })
        .collect();
    let vertical = detect_vertical(&parsed);
    if parsed.is_empty() {
        return LyricOcrLayout { text: String::new(), vertical, dropped_ruby: 0 };
    }

    let all: Vec<&Piece> = parsed.iter().collect();
    let median = median_char_size(&all, vertical);
    let (body, ruby): (Vec<&Piece>, Vec<&Piece>) =
        all.into_iter().partition(|p| p.char_size(vertical) >= RUBY_RATIO * median);
    // 全部が小さいと出たら中央値の取り方が悪い。外さずに全部を本文にする。
    let (body, dropped) = if body.is_empty() { (ruby, 0) } else { (body, ruby.len() as u32) };

    let body_median = median_char_size(&body, vertical);
    let gutter = (body_median * GUTTER_CHAR_UNITS).max(f64::EPSILON);
    let mut out: Vec<String> = Vec::new();
    for block in split_blocks(body, vertical, gutter) {
        let lines = build_lines(block, vertical, body_median);
        if lines.is_empty() {
            continue;
        }
        if !out.is_empty() {
            out.push(String::new());
        }
        out.extend(join_with_paragraphs(&lines));
    }
    LyricOcrLayout { text: out.join("\n"), vertical, dropped_ruby: dropped }
}

/// 歌詞カードの読み取りの使い方の 1 手順。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricOcrStep {
    pub title: String,
    pub detail: String,
}

/// 歌詞カードの読み取りの使い方 (投稿画面の読み取りボタンの下に出す)。
pub fn steps() -> Vec<LyricOcrStep> {
    let s = |title: &str, detail: &str| LyricOcrStep { title: title.into(), detail: detail.into() };
    vec![
        s(
            "「歌詞カードを撮る」で撮る",
            "撮影画面の右上の「自動」を押すと、シャッターを押したときだけ撮れます。何ページも続けて撮れ、撮った順に入ります。スクリーンショットや写真は「写真から読む」で選べます。",
        ),
        s(
            "歌詞の部分が画面いっぱいに入るように、真上から撮る",
            "明るい所で、影や光の反射が入らないようにすると読み取りがよくなります。縦書きの歌詞カードは読み取りが苦手です。",
        ),
        s(
            "読み取った歌詞を見直して送る",
            "読み取った文字は入力欄に入ります。歌詞カードと見比べて、記号や改行まで表記どおりに直してから送ってください。",
        ),
    ]
}

/// 入力欄に読み取った本文を足す。空なら置き換え、書きかけなら空行を挟んで後ろに足す
/// (歌詞カードを何枚かに分けて撮る使い方)。
pub fn append_to_draft(draft: &str, recognized: &str) -> String {
    let recognized = recognized.trim_matches('\n');
    let draft = draft.trim_end();
    match (draft.is_empty(), recognized.is_empty()) {
        (_, true) => draft.to_string(),
        (true, false) => recognized.to_string(),
        (false, false) => format!("{draft}\n\n{recognized}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(text: &str, x: f64, y: f64, w: f64, h: f64) -> OcrPiece {
        OcrPiece { text: text.into(), x, y, width: w, height: h }
    }

    #[test]
    fn horizontal_lines_are_read_top_to_bottom_with_paragraph_breaks() {
        // OS が返す順番はばらばらでも、位置から並べる。3 行目の前だけ大きく空いている。
        let pieces = vec![
            p("ステージ", 10.0, 50.0, 120.0, 30.0),
            p("きらめく", 10.0, 10.0, 120.0, 30.0),
            p("走り出す", 10.0, 150.0, 120.0, 30.0),
            p("夢へ", 10.0, 190.0, 60.0, 30.0),
        ];
        let r = layout(&pieces);
        assert!(!r.vertical);
        assert_eq!(r.text, "きらめく\nステージ\n\n走り出す\n夢へ");
    }

    #[test]
    fn a_break_is_found_even_with_only_three_lines() {
        let pieces = vec![
            p("一", 10.0, 10.0, 30.0, 30.0),
            p("二", 10.0, 50.0, 30.0, 30.0),
            p("三", 10.0, 170.0, 30.0, 30.0),
        ];
        assert_eq!(layout(&pieces).text, "一\n二\n\n三");
    }

    #[test]
    fn pieces_on_one_line_are_joined_left_to_right_with_a_space_for_wide_gaps() {
        let pieces = vec![p("Hello", 200.0, 10.0, 150.0, 30.0), p("きらめく", 10.0, 12.0, 120.0, 30.0)];
        assert_eq!(layout(&pieces).text, "きらめく Hello");
        let tight = vec![p("ステー", 10.0, 10.0, 90.0, 30.0), p("ジ", 105.0, 10.0, 30.0, 30.0)];
        assert_eq!(layout(&tight).text, "ステージ");
    }

    #[test]
    fn two_columns_are_read_left_column_first() {
        let pieces = vec![
            p("右の一", 400.0, 10.0, 90.0, 30.0),
            p("左の一", 10.0, 10.0, 90.0, 30.0),
            p("右の二", 400.0, 50.0, 90.0, 30.0),
            p("左の二", 10.0, 50.0, 90.0, 30.0),
        ];
        assert_eq!(layout(&pieces).text, "左の一\n左の二\n\n右の一\n右の二");
    }

    #[test]
    fn vertical_columns_are_read_right_to_left_and_small_ruby_is_dropped() {
        let pieces = vec![
            p("ひだりの列", 10.0, 10.0, 30.0, 150.0),
            p("みぎの列だ", 60.0, 10.0, 30.0, 150.0),
            p("るび", 92.0, 10.0, 12.0, 24.0),
        ];
        let r = layout(&pieces);
        assert!(r.vertical);
        assert_eq!(r.dropped_ruby, 1);
        assert_eq!(r.text, "みぎの列だ\nひだりの列");
    }

    #[test]
    fn empty_input_and_blank_pieces_give_empty_text() {
        assert_eq!(layout(&[]).text, "");
        assert_eq!(layout(&[p("  ", 0.0, 0.0, 10.0, 10.0)]).text, "");
    }

    #[test]
    fn steps_explain_the_manual_shutter_and_review() {
        let all = format!("{:?}", steps());
        assert_eq!(steps().len(), 3);
        assert!(all.contains("「自動」") && all.contains("見直して"));
    }

    #[test]
    fn append_keeps_the_draft_and_separates_pages_with_a_blank_line() {
        assert_eq!(append_to_draft("", "\nあ\nい\n"), "あ\nい");
        assert_eq!(append_to_draft("あ\n", "う"), "あ\n\nう");
        assert_eq!(append_to_draft("あ", ""), "あ");
    }
}
