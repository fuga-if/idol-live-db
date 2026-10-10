//! 歌詞の投稿 (ユーザーが一次ソースから入力した歌詞を送る) の入力規則。
//!
//! 歌詞は 2026-10-06 に取り込み元の問題で全削除した。再開は「CD の歌詞カードなどを見て
//! 利用者が入力する」投稿だけで行う。ここは投稿画面が使う規則で、両 OS は
//! [`check_submission`] を入力のたびに通して、整えた本文・行数・注意・送信の可否を出す。
//!
//! - **投稿ガイドライン ([`guideline`]) への同意が要る。** 入力元 (歌詞カード・公式) は書かせない。
//!   どこから写したかは確かめようがなく、プチリリと同じく規約で縛る (2026-10-06 オーナー判断)。
//!   聴き取りの書き起こし・歌詞サイトからの転載はガイドラインで禁じる。
//! - 上限 (文字数・行数) はサーバ (`imas-live-api` の `routes/lyric_submissions.ts`) と同じ数。
//!   文字数はサーバの `.length` に合わせて UTF-16 で数える。
//! - 作詞・作曲のクレジット行や、本文が 2 回続けて入っているのは、ページを丸ごと貼ったときの
//!   形なので注意を出す (送信は止めない。曲によっては正しい形もありうるため)。
//! - 半角カナ (U+FF61〜U+FF9F) は整えるときに全角へ直す ([`fold_halfwidth_kana`])。表記どおりの
//!   歌詞に半角カナは無く、入ってくるのは入力や読み取りの癖なので、弾かずに直す (2026-10-11 オーナー判断)。

/// 1 曲の本文の上限 (UTF-16)。長い全体曲でも 3,000 字ほど。
pub const MAX_CHARS: u32 = 8000;
/// 1 曲の行数の上限 (空行を含む)。
pub const MAX_LINES: u32 = 400;

/// 投稿の前に知らせること。`blocks_submit` が真のものは送信を止める。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum LyricSubmissionIssue {
    /// 本文が空。
    Empty,
    /// 文字数が上限を超えた。
    TooLong { max: u32 },
    /// 行数が上限を超えた。
    TooManyLines { max: u32 },
    /// 「作詞：」のようなクレジットの行がある。
    CreditLines,
    /// 本文の後半が前半の繰り返しになっている (ページを 2 回貼ったときの形)。
    Doubled,
    /// 歌詞カードの読み仮名 (ルビ) を読み取ったらしい行がある ([`ruby_like_lines`])。
    RubyLikeLines { lines: Vec<String> },
}

pub fn blocks_submit(issue: &LyricSubmissionIssue) -> bool {
    matches!(
        issue,
        LyricSubmissionIssue::Empty
            | LyricSubmissionIssue::TooLong { .. }
            | LyricSubmissionIssue::TooManyLines { .. }
    )
}

pub fn issue_message(issue: &LyricSubmissionIssue) -> String {
    match issue {
        LyricSubmissionIssue::Empty => "歌詞を入力してください。".into(),
        LyricSubmissionIssue::TooLong { max } => format!("{max} 字までです。"),
        LyricSubmissionIssue::TooManyLines { max } => format!("{max} 行までです。"),
        LyricSubmissionIssue::CreditLines => {
            "作詞・作曲などのクレジットは本文に入れないでください。曲の情報から出します。".into()
        }
        LyricSubmissionIssue::Doubled => "同じ歌詞が 2 回続けて入っているようです。".into(),
        LyricSubmissionIssue::RubyLikeLines { lines } => format!(
            "読み仮名 (ルビ) を読み取ったらしい行があります: {}。歌詞カードに振られた読み仮名なら、親字《よみ》の形 (例: 視界《せかい》) で本文に入れ直してから、この行を消してください。",
            lines.iter().map(|l| format!("「{l}」")).collect::<Vec<_>>().join("")
        ),
    }
}

/// 入力を整えて調べた結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct LyricSubmissionCheck {
    /// 送る本文 (改行を揃え、行末の空白と前後の空行を落とし、空行の連続を 1 つにしたもの)。
    pub normalized: String,
    /// 整えた本文の行数 (空行を含む)。
    pub line_count: u32,
    /// 整えた本文の文字数 (UTF-16)。
    pub char_count: u32,
    pub issues: Vec<LyricSubmissionIssue>,
    /// ガイドラインへの同意と本文がそろって送れるか。
    pub can_submit: bool,
}

/// 改行を `\n` に揃え、行末の空白を落とし、空行の連続を 1 つに、前後の空行を除く。
/// 半角カナは全角にする ([`fold_halfwidth_kana`])。それ以外の字は変えない (歌詞を勝手に直さない)。
pub fn normalize(text: &str) -> String {
    let unified = fold_halfwidth_kana(&text.replace("\r\n", "\n").replace('\r', "\n"));
    let mut out: Vec<&str> = Vec::new();
    for line in unified.split('\n') {
        let line = line.trim_end();
        if line.is_empty() && out.last().is_none_or(|l| l.is_empty()) {
            continue;
        }
        out.push(line);
    }
    while out.last().is_some_and(|l| l.is_empty()) {
        out.pop();
    }
    out.join("\n")
}

/// 半角カナと半角の句読点・カギ括弧・中黒・長音・濁点 (U+FF61〜U+FF9F) を全角にする。
/// 濁点・半濁点は前の字と合わせて 1 字にし (`ｶﾞ` → `ガ`、`ﾊﾟ` → `パ`、`ｳﾞ` → `ヴ`)、
/// 合わせられないときは単独の `゛` `゜` にする。範囲外の字 (英数字・全角英数・記号) は触らない。
/// サーバ (`routes/lyric_submissions.ts` の `foldHalfwidthKana`) も同じ規則で直す。
pub fn fold_halfwidth_kana(text: &str) -> String {
    use unicode_normalization::char::{compose, decompose_compatible};
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        if !('\u{FF61}'..='\u{FF9F}').contains(&c) {
            out.push(c);
            continue;
        }
        let mut full = None;
        decompose_compatible(c, |d| full = Some(d));
        let full = full.unwrap_or(c);
        if let Some(standalone) = match full {
            '\u{3099}' => Some('゛'),
            '\u{309A}' => Some('゜'),
            _ => None,
        } {
            match out.pop() {
                Some(prev) => match compose(prev, full) {
                    Some(joined) => out.push(joined),
                    None => {
                        out.push(prev);
                        out.push(standalone);
                    }
                },
                None => out.push(standalone),
            }
        } else {
            out.push(full);
        }
    }
    out
}

const CREDIT_PREFIXES: [&str; 6] = ["作詞", "作曲", "編曲", "歌手", "歌：", "唄："];

fn is_credit_line(line: &str) -> bool {
    let line = line.trim_start();
    CREDIT_PREFIXES.iter().any(|p| {
        line.strip_prefix(p)
            .is_some_and(|rest| rest.starts_with(['：', ':', ' ', '　']) || p.ends_with('：'))
    })
}

/// 空行を除いた行の並びの後半が前半と同じか (4 行以上あるときだけ見る)。
fn is_doubled(lines: &[&str]) -> bool {
    let body: Vec<&str> = lines.iter().copied().filter(|l| !l.trim().is_empty()).collect();
    if body.len() < 8 || body.len() % 2 != 0 {
        return false;
    }
    let (a, b) = body.split_at(body.len() / 2);
    a == b
}

pub fn check_submission(text: &str, agreed_to_guideline: bool) -> LyricSubmissionCheck {
    let normalized = normalize(text);
    let lines: Vec<&str> = if normalized.is_empty() { Vec::new() } else { normalized.split('\n').collect() };
    let line_count = lines.len() as u32;
    let char_count = normalized.encode_utf16().count() as u32;

    let mut issues = Vec::new();
    if normalized.is_empty() {
        issues.push(LyricSubmissionIssue::Empty);
    }
    if char_count > MAX_CHARS {
        issues.push(LyricSubmissionIssue::TooLong { max: MAX_CHARS });
    }
    if line_count > MAX_LINES {
        issues.push(LyricSubmissionIssue::TooManyLines { max: MAX_LINES });
    }
    if lines.iter().any(|l| is_credit_line(l)) {
        issues.push(LyricSubmissionIssue::CreditLines);
    }
    if is_doubled(&lines) {
        issues.push(LyricSubmissionIssue::Doubled);
    }
    let ruby = ruby_like_lines(&normalized);
    if !ruby.is_empty() {
        issues.push(LyricSubmissionIssue::RubyLikeLines {
            lines: ruby.iter().map(|&i| lines[i as usize].trim().to_string()).collect(),
        });
    }
    let can_submit = agreed_to_guideline && !issues.iter().any(blocks_submit);
    LyricSubmissionCheck { normalized, line_count, char_count, issues, can_submit }
}

fn is_kana(c: char) -> bool {
    ('\u{3041}'..='\u{309F}').contains(&c) || ('\u{30A1}'..='\u{30FC}').contains(&c)
}

fn has_kanji(line: &str) -> bool {
    line.chars().any(|c| ('\u{4E00}'..='\u{9FFF}').contains(&c) || ('\u{3400}'..='\u{4DBF}').contains(&c))
}

/// 読み仮名 (ルビ) を読み取ったらしい行の番号 (0 始まり)。歌詞カードを読み取ると、漢字の上の
/// 小さな読み仮名が 1 行として入ることがある。かなだけの短い行 (6 字まで) で、隣の行に漢字が
/// あるものを拾う。歌詞にも短いかなの行はあるので、消すかは本人に任せる (注意を出すだけ)。
pub fn ruby_like_lines(text: &str) -> Vec<u32> {
    let lines: Vec<&str> = text.split('\n').collect();
    let short_kana = |l: &str| {
        let t = l.trim();
        (1..=6).contains(&t.chars().count()) && t.chars().all(is_kana)
    };
    // 隣の行 (同じようなかなの短い行は飛ばす。空行は越えない) に漢字があるか。
    let neighbor_has_kanji = |i: usize| {
        let prev = lines[..i].iter().rev().find(|l| !short_kana(l));
        let next = lines[i + 1..].iter().find(|l| !short_kana(l));
        prev.is_some_and(|l| has_kanji(l)) || next.is_some_and(|l| has_kanji(l))
    };
    (0..lines.len())
        .filter(|&i| short_kana(lines[i]) && neighbor_has_kanji(i))
        .map(|i| i as u32)
        .collect()
}

fn is_ideograph(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' | '\u{F900}'..='\u{FAFF}' | '々' | '〆' | 'ヶ')
}

/// 選んだ範囲 (Unicode スカラーの位置 `start..end`) に読み仮名を付けた本文を返す。
/// 書き方は 親字《よみ》。親字が漢字だけで、直前が漢字でなければ ｜ は付けない
/// (親字は《の直前に続く漢字が自動で選ばれるため)。それ以外は親字の頭に ｜ を置く。
/// 範囲が空・改行を含む・読みが空のときは本文をそのまま返す。
pub fn wrap_ruby(text: &str, start: u32, end: u32, reading: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let (start, end) = (start as usize, end as usize);
    let reading = reading.trim();
    if start >= end || end > chars.len() || reading.is_empty() || reading.contains(['\n', '《', '》']) {
        return text.to_string();
    }
    let base = &chars[start..end];
    if base.contains(&'\n') {
        return text.to_string();
    }
    let needs_marker = !base.iter().all(|&c| is_ideograph(c)) || (start > 0 && is_ideograph(chars[start - 1]));
    let mut out: String = chars[..start].iter().collect();
    if needs_marker {
        out.push('｜');
    }
    out.extend(base);
    out.push('《');
    out.push_str(reading);
    out.push('》');
    out.extend(&chars[end..]);
    out
}

/// 歌詞の中の読み仮名 1 つ。親字の文字列と、本文の中で何番目 (0 始まり) に出てくる親字か
/// で場所を表す。画面は記法 (《》・｜) を見せず、本文とこの一覧を分けて持つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct RubyMark {
    pub base: String,
    pub reading: String,
    pub nth: u32,
}

/// 記法の入った本文を、記法の無い本文と読み仮名の一覧に分けたもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct RubySplit {
    pub plain: String,
    pub marks: Vec<RubyMark>,
}

/// `needle` が `chars` の `pos` より前に何回出てくるか (重ならずに数える)。
fn occurrences_before(chars: &[char], needle: &[char], pos: usize) -> usize {
    let mut count = 0;
    let mut i = 0;
    while i + needle.len() <= pos {
        if chars[i..i + needle.len()] == *needle {
            count += 1;
            i += needle.len();
        } else {
            i += 1;
        }
    }
    count
}

/// `needle` の `nth` 番目 (0 始まり、重ならずに数える) の位置。
fn nth_position(chars: &[char], needle: &[char], nth: usize) -> Option<usize> {
    if needle.is_empty() {
        return None;
    }
    let mut seen = 0;
    let mut i = 0;
    while i + needle.len() <= chars.len() {
        if chars[i..i + needle.len()] == *needle {
            if seen == nth {
                return Some(i);
            }
            seen += 1;
            i += needle.len();
        } else {
            i += 1;
        }
    }
    None
}

/// 記法 (親字《よみ》・｜親字《よみ》) の入った本文を、記法の無い本文と読み仮名の一覧に分ける。
pub fn ruby_split(text: &str) -> RubySplit {
    let mut plain_lines: Vec<String> = Vec::new();
    // (本文の頭からの位置, 親字, 読み)
    let mut found: Vec<(usize, String, String)> = Vec::new();
    let mut offset = 0usize;
    for line in text.split('\n') {
        let chars: Vec<char> = line.chars().collect();
        let spans = crate::domain::lyric_sync::ruby_spans(line);
        let mut plain = String::new();
        let mut plain_len = 0usize;
        let mut k = 0usize;
        for span in &spans {
            let (base_start, base_end) = (span.base_start as usize, span.base_end as usize);
            let (open, close) = (span.open as usize, span.close as usize);
            let marker = span.marker.map(|m| m as usize);
            for (j, &c) in chars.iter().enumerate().take(base_start).skip(k) {
                if Some(j) != marker {
                    plain.push(c);
                    plain_len += 1;
                }
            }
            let base: String = chars[base_start..base_end].iter().collect();
            let reading: String = chars[open + 1..close - 1].iter().collect();
            found.push((offset + plain_len, base.clone(), reading));
            plain.push_str(&base);
            plain_len += base_end - base_start;
            k = close;
        }
        for &c in &chars[k.min(chars.len())..] {
            plain.push(c);
            plain_len += 1;
        }
        offset += plain_len + 1;
        plain_lines.push(plain);
    }
    let plain = plain_lines.join("\n");
    let all: Vec<char> = plain.chars().collect();
    let marks = found
        .into_iter()
        .map(|(pos, base, reading)| {
            let needle: Vec<char> = base.chars().collect();
            RubyMark { nth: occurrences_before(&all, &needle, pos) as u32, base, reading }
        })
        .collect();
    RubySplit { plain, marks }
}

/// 選んだ範囲 (スカラーの位置) と読みから読み仮名を作る。範囲が空・改行をまたぐ・読みが空なら None。
pub fn ruby_mark_at(plain: &str, start: u32, end: u32, reading: &str) -> Option<RubyMark> {
    let chars: Vec<char> = plain.chars().collect();
    let (start, end) = (start as usize, end as usize);
    let reading = reading.trim();
    if start >= end || end > chars.len() || reading.is_empty() || reading.contains(['\n', '《', '》', '｜']) {
        return None;
    }
    let base = &chars[start..end];
    if base.iter().any(|&c| c == '\n' || c == '《' || c == '》' || c == '｜') {
        return None;
    }
    Some(RubyMark {
        base: base.iter().collect(),
        reading: reading.to_string(),
        nth: occurrences_before(&chars, base, start) as u32,
    })
}

/// 本文を書き換えたあと、読み仮名の場所 (何番目の出現か) を付け直す。書き換えは 1 か所のまとまり
/// (前後の変わらない部分に挟まれた範囲) と見なし、親字がその前にあれば同じ位置、後ろにあれば
/// ずれた位置で数え直す (前後の一致は前から先に取るので、末尾への打ち足しに強い。打ち足した文字が
/// 元の頭と同じ字で始まると前に寄せて読むことがある)。書き換えた範囲に親字が掛かったものは元の数え方のまま残す (見つからなければ
/// 画面が「見つかりません」と出す)。同じ字を前に打ち足すと別の字に付く、を防ぐ。
pub fn ruby_rebase(old_plain: &str, new_plain: &str, marks: &[RubyMark]) -> Vec<RubyMark> {
    let old: Vec<char> = old_plain.chars().collect();
    let new: Vec<char> = new_plain.chars().collect();
    let prefix = old.iter().zip(&new).take_while(|(a, b)| a == b).count();
    let max_suffix = old.len().min(new.len()) - prefix;
    let suffix = old.iter().rev().zip(new.iter().rev()).take(max_suffix).take_while(|(a, b)| a == b).count();
    let (old_edit_end, new_edit_end) = (old.len() - suffix, new.len() - suffix);
    marks
        .iter()
        .map(|mark| {
            let needle: Vec<char> = mark.base.chars().collect();
            let Some(start) = nth_position(&old, &needle, mark.nth as usize) else { return mark.clone() };
            let end = start + needle.len();
            let moved = if end <= prefix {
                Some(start)
            } else if start >= old_edit_end {
                Some(start - old_edit_end + new_edit_end)
            } else {
                None
            };
            match moved {
                Some(pos) if new.get(pos..pos + needle.len()) == Some(&needle[..]) => {
                    RubyMark { nth: occurrences_before(&new, &needle, pos) as u32, ..mark.clone() }
                }
                _ => mark.clone(),
            }
        })
        .collect()
}

/// その読み仮名の親字が、今の本文にまだあるか (歌詞を打ち直すと消えることがある)。
pub fn ruby_mark_found(plain: &str, mark: &RubyMark) -> bool {
    let chars: Vec<char> = plain.chars().collect();
    let needle: Vec<char> = mark.base.chars().collect();
    nth_position(&chars, &needle, mark.nth as usize).is_some()
}

/// 本文と読み仮名の一覧を、記法の入った本文に合わせる (送るとき)。親字の見つからない読み仮名・
/// 同じ字に重なる読み仮名は飛ばす。｜ が要るかは [`wrap_ruby`] と同じ決まり。
pub fn ruby_join(plain: &str, marks: &[RubyMark]) -> String {
    let chars: Vec<char> = plain.chars().collect();
    let mut placed: Vec<(usize, usize, &str)> = Vec::new();
    for mark in marks {
        let needle: Vec<char> = mark.base.chars().collect();
        let Some(start) = nth_position(&chars, &needle, mark.nth as usize) else { continue };
        let end = start + needle.len();
        if placed.iter().any(|&(s, e, _)| start < e && s < end) {
            continue;
        }
        placed.push((start, end, mark.reading.as_str()));
    }
    // 後ろから当てる (前の位置がずれないように)。
    placed.sort_by(|a, b| b.0.cmp(&a.0));
    let mut out = plain.to_string();
    for (start, end, reading) in placed {
        out = wrap_ruby(&out, start as u32, end as u32, reading);
    }
    out
}

/// 指定の行を消す (ルビらしい行を本人が消すとき)。前後の空行の並びは整え直す。
pub fn remove_lines(text: &str, indices: &[u32]) -> String {
    let kept: Vec<&str> = text
        .split('\n')
        .enumerate()
        .filter(|(i, _)| !indices.contains(&(*i as u32)))
        .map(|(_, l)| l)
        .collect();
    normalize(&kept.join("\n"))
}

/// その曲に歌詞を投稿できるか。掲載の方針 (アイマス系ブランドの非カバー曲だけ) と同じ線で切る。
/// カバーは `song_type` だけでなく名義 (「〇〇カバー」) でも見る (song_type だけでは取りこぼす)。
/// JASRAC・NexTone の管理と歌詞の配信の可否は、公開前に運営が確かめる。
pub fn submission_allowed(brand_id: &str, song_type: Option<&str>, singer_label: Option<&str>) -> bool {
    brand_id != "other" && song_type != Some("cover") && !singer_label.is_some_and(|s| s.contains("カバー"))
}

/// 投稿ガイドラインの 1 塊 (読みもの画面の見出し・段落・箇条書き・補足)。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum LyricGuideBlock {
    Heading { text: String },
    Paragraph { text: String },
    Bullets { items: Vec<String> },
    Note { text: String },
}

/// 投稿ガイドライン。両 OS の読みもの画面はこれを並べるだけ。
pub fn guideline() -> Vec<LyricGuideBlock> {
    use LyricGuideBlock::*;
    let h = |t: &str| Heading { text: t.into() };
    let p = |t: &str| Paragraph { text: t.into() };
    let b = |items: &[&str]| Bullets { items: items.iter().map(|s| s.to_string()).collect() };
    vec![
        h("投稿できる曲"),
        p("アイドルマスターシリーズのオリジナル曲で、歌詞が CD の歌詞カードや公式サイトで公表されているものです。歌詞は JASRAC と NexTone の許諾のもとで配信するため、どちらかが管理していて、歌詞の配信が認められている曲に限ります。管理の状況は、公開の前に運営が確かめます。"),
        h("投稿できないもの"),
        b(&[
            "歌詞サイトや、ほかのアプリ・サービスから写した歌詞",
            "聴き取って書き起こした歌詞",
            "歌詞が公表されていない曲 (発売前の曲を含む)",
            "歌のない曲 (インストゥルメンタル)",
            "歌詞の翻訳や、読み仮名だけの歌詞",
            "替え歌、カバー曲、ほかのシリーズの曲",
            "歌詞ではない文 (作詞・作曲などのクレジット、コール、感想)",
        ]),
        h("入力のしかた"),
        b(&[
            "CD の歌詞カードや公式の表記どおりに入力してください。記号 (… や ♡ など)、全角と半角、大文字と小文字も表記に合わせます。",
            "空白と改行は、できるだけ歌詞カードのとおりにしてください。行の区切りは歌詞カードに合わせ、まとまりの間には空行を 1 つ入れます。",
            "歌詞カードの写真やスクリーンショットから文字を読み取れます。読み取った歌詞は、表記どおりになっているか必ず見直してください。",
            "歌詞カードに振られている読み仮名 (当て読み) は、親字《よみ》の形で入れてください (例: 視界《せかい》)。親字は《の直前に続く漢字が自動で選ばれます。親字にかな・カタカナ・英字が入るときや、続く漢字の途中から振るときは、親字の頭に ｜ を置きます (例: ｜ステージ《ぶたい》、月｜夜《よ》)。（）は被せの歌詞に使うので、読み仮名には使わないでください。",
            "歌詞カードに無い読み仮名は付けないでください。コールやパート分けも本文に入れず、歌詞の公開後に付けてください。",
        ]),
        h("公開まで"),
        p("まだ歌詞の無い曲なら、送った歌詞はすぐに公開されます。運営があとから歌詞カードや公式の表記と照らし合わせ、表記どおりでないもの、許諾の状況が変わった曲、このガイドラインに合わないと分かった歌詞は、直したり公開をやめたりします。すでに歌詞のある曲に送った歌詞は、直しの提案として運営が確かめます。"),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_unifies_breaks_and_blank_runs_without_touching_letters() {
        let text = "\r\n\n  あいう　 \r\nかきく\n\n\n\nさしす\n\n";
        assert_eq!(normalize(text), "  あいう\nかきく\n\nさしす");
    }

    #[test]
    fn empty_text_cannot_be_sent() {
        let c = check_submission(" \n\n", true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::Empty]);
        assert!(!c.can_submit);
        assert_eq!(c.line_count, 0);
    }

    #[test]
    fn agreement_to_the_guideline_is_required() {
        let text = "きらめく\nステージ";
        assert!(!check_submission(text, false).can_submit);
        let ok = check_submission(text, true);
        assert!(ok.can_submit);
        assert_eq!((ok.line_count, ok.char_count), (2, 9));
    }

    #[test]
    fn limits_are_counted_on_the_normalized_text() {
        let long = "あ".repeat(MAX_CHARS as usize + 1);
        let c = check_submission(&long, true);
        assert!(c.issues.contains(&LyricSubmissionIssue::TooLong { max: MAX_CHARS }));
        assert!(!c.can_submit);

        let many = vec!["ら"; MAX_LINES as usize + 1].join("\n");
        let c = check_submission(&many, true);
        assert!(c.issues.contains(&LyricSubmissionIssue::TooManyLines { max: MAX_LINES }));

        // 行末の空白は数えない
        let c = check_submission(&format!("{}   ", "あ".repeat(MAX_CHARS as usize)), true);
        assert!(c.can_submit);
    }

    #[test]
    fn credit_lines_and_doubled_body_warn_without_blocking() {
        let c = check_submission("作詞：だれか\n作曲: だれか\nうたうよ、きらめくステージ", true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::CreditLines]);
        assert!(c.can_submit);
        // 歌詞の中の「作詞家」は行頭でも区切りが続かないので拾わない
        assert!(check_submission("作詞家になりたい", true).issues.is_empty());

        let half = "一\n二\n三\n四";
        let c = check_submission(&format!("{half}\n\n{half}"), true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::Doubled]);
        assert!(c.can_submit);
    }

    #[test]
    fn ruby_like_lines_are_flagged_and_can_be_removed() {
        let text = "護る為なら総てを捧げる\nせかい\nあか\n僕の視界は赫く染まった\n\nねえ\nきらきら";
        // 「ねえ」は隣が「きらきら」で漢字が無いので拾わない
        assert_eq!(ruby_like_lines(text), vec![1, 2]);
        let c = check_submission(text, true);
        assert!(c.issues.contains(&LyricSubmissionIssue::RubyLikeLines { lines: vec!["せかい".into(), "あか".into()] }));
        assert!(c.can_submit);
        assert_eq!(remove_lines(text, &[1, 2]), "護る為なら総てを捧げる\n僕の視界は赫く染まった\n\nねえ\nきらきら");
    }

    #[test]
    fn wrap_ruby_adds_the_marker_only_when_needed() {
        assert_eq!(wrap_ruby("僕の視界は", 2, 4, "せかい"), "僕の視界《せかい》は");
        assert_eq!(wrap_ruby("月夜に", 1, 2, "世"), "月｜夜《世》に");
        assert_eq!(wrap_ruby("あのステージへ", 2, 6, "ぶたい"), "あの｜ステージ《ぶたい》へ");
        // 選択が空・読みが空・改行をまたぐときはそのまま
        assert_eq!(wrap_ruby("夜", 0, 0, "よ"), "夜");
        assert_eq!(wrap_ruby("夜", 0, 1, " "), "夜");
        assert_eq!(wrap_ruby("夜\n朝", 0, 3, "よ"), "夜\n朝");
    }

    #[test]
    fn ruby_split_and_join_round_trip_without_showing_the_notation() {
        let text = "僕の視界《せかい》は\n月｜夜《世》の｜ステージ《ぶたい》\n視界《しかい》";
        let split = ruby_split(text);
        assert_eq!(split.plain, "僕の視界は\n月夜のステージ\n視界");
        assert_eq!(
            split.marks,
            vec![
                RubyMark { base: "視界".into(), reading: "せかい".into(), nth: 0 },
                RubyMark { base: "夜".into(), reading: "世".into(), nth: 0 },
                RubyMark { base: "ステージ".into(), reading: "ぶたい".into(), nth: 0 },
                RubyMark { base: "視界".into(), reading: "しかい".into(), nth: 1 },
            ]
        );
        assert_eq!(ruby_join(&split.plain, &split.marks), text);
    }

    #[test]
    fn ruby_marks_follow_edits_and_report_lost_bases() {
        let mark = ruby_mark_at("赫く染まった赫い", 6, 7, "あか").unwrap();
        assert_eq!(mark, RubyMark { base: "赫".into(), reading: "あか".into(), nth: 1 });
        // 前に文字を足しても、2 つ目の「赫」に付いたまま
        assert_eq!(ruby_join("世界が赫く染まった赫い", &[mark.clone()]), "世界が赫く染まった赫《あか》い");
        // 2 つ目の「赫」が消えたら見つからない
        assert!(!ruby_mark_found("赫く染まった", &mark));
        assert_eq!(ruby_mark_at("夜", 0, 0, "よ"), None);
        // 重なる読み仮名は後のものを飛ばす
        let marks = [
            RubyMark { base: "視界".into(), reading: "せかい".into(), nth: 0 },
            RubyMark { base: "界".into(), reading: "かい".into(), nth: 0 },
        ];
        assert_eq!(ruby_join("視界", &marks), "視界《せかい》");
    }

    #[test]
    fn ruby_rebase_keeps_marks_on_the_same_characters_after_edits() {
        let marks = vec![RubyMark { base: "赫".into(), reading: "あか".into(), nth: 0 }];
        // 前に同じ字を含む行を打ち足しても、元の「赫」に付いたまま (nth が 1 になる)
        let rebased = ruby_rebase("赫く染まった", "空も赫い\n赫く染まった", &marks);
        assert_eq!(rebased[0].nth, 1);
        assert_eq!(ruby_join("空も赫い\n赫く染まった", &rebased), "空も赫い\n赫《あか》く染まった");
        // 後ろを書き換えても変わらない
        assert_eq!(ruby_rebase("赫く染まった", "赫く染まった空", &marks)[0].nth, 0);
        // 親字そのものを消したら元のまま (画面が「見つかりません」と出す)
        let gone = ruby_rebase("赫く", "く", &marks);
        assert!(!ruby_mark_found("く", &gone[0]));
    }

    #[test]
    fn halfwidth_kana_is_folded_to_fullwidth_instead_of_blocking() {
        let c = check_submission("ｱｲﾄﾞﾙ･ﾏｽﾀｰ｡ ｢ﾊﾟｰﾃｨｰ｣ ｳﾞｫｲｽ", true);
        assert_eq!(c.normalized, "アイドル・マスター。 「パーティー」 ヴォイス");
        assert!(c.issues.is_empty());
        assert!(c.can_submit);
        // 合わせられない濁点は単独の字に。行頭に来ても落とさない
        assert_eq!(fold_halfwidth_kana("ﾞあﾟ"), "゛あ゜");
        assert_eq!(fold_halfwidth_kana("がﾞ"), "が゛");
        // 範囲外 (英数字・全角英数・全角カナ・記号) は触らない
        assert_eq!(fold_halfwidth_kana("アイドル ABC ａｂｃ M@STER ♡…"), "アイドル ABC ａｂｃ M@STER ♡…");
        // 半角の濁点で字数が減るので、上限は直したあとの字で数える
        let c = check_submission(&"ｶﾞ".repeat(MAX_CHARS as usize), true);
        assert_eq!(c.char_count, MAX_CHARS);
        assert!(c.can_submit);
    }

    #[test]
    fn only_original_songs_of_the_series_accept_submissions() {
        assert!(submission_allowed("cg", Some("unit"), Some("CINDERELLA PROJECT")));
        assert!(!submission_allowed("other", Some("unit"), None));
        assert!(!submission_allowed("ml", Some("cover"), None));
        assert!(!submission_allowed("ml", Some("unit"), Some("μ'sカバー")));
    }

    #[test]
    fn guideline_lists_what_cannot_be_posted() {
        let g = guideline();
        assert!(g.contains(&LyricGuideBlock::Heading { text: "投稿できないもの".into() }));
        let all = format!("{g:?}");
        assert!(all.contains("聴き取って書き起こした歌詞") && all.contains("歌詞サイト"));
    }
}
