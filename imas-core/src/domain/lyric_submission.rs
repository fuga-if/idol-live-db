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
    /// 半角カナが入っている (表記どおりではない。全角で入れてもらう)。
    HalfwidthKana,
    /// 歌詞カードの読み仮名 (ルビ) を読み取ったらしい行がある ([`ruby_like_lines`])。
    RubyLikeLines { lines: Vec<String> },
}

pub fn blocks_submit(issue: &LyricSubmissionIssue) -> bool {
    matches!(
        issue,
        LyricSubmissionIssue::Empty
            | LyricSubmissionIssue::TooLong { .. }
            | LyricSubmissionIssue::TooManyLines { .. }
            | LyricSubmissionIssue::HalfwidthKana
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
        LyricSubmissionIssue::HalfwidthKana => "半角カナは使えません。全角で入力してください。".into(),
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
/// 字そのものは変えない (歌詞を勝手に直さない)。
pub fn normalize(text: &str) -> String {
    let unified = text.replace("\r\n", "\n").replace('\r', "\n");
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
    // 半角カタカナと半角の句読点・濁点 (U+FF61〜U+FF9F)。
    if normalized.chars().any(|c| ('\u{FF61}'..='\u{FF9F}').contains(&c)) {
        issues.push(LyricSubmissionIssue::HalfwidthKana);
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
            "半角カナは使わないでください。",
            "行の区切りは歌詞カードに合わせ、まとまりの間には空行を 1 つ入れてください。",
            "歌詞カードの写真やスクリーンショットから文字を読み取れます。読み取った歌詞は、表記どおりになっているか必ず見直してください。",
            "歌詞カードに振られている読み仮名 (当て読み) は、親字《よみ》の形で入れてください (例: 視界《せかい》)。親字が漢字の並びの途中から始まるときは ｜ で区切ります (例: 赤い｜衝動《しょうどう》)。（）は被せの歌詞に使うので、読み仮名には使わないでください。",
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
    fn halfwidth_kana_blocks_submission() {
        let c = check_submission("ｱｲﾄﾞﾙ", true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::HalfwidthKana]);
        assert!(!c.can_submit);
        assert!(check_submission("アイドル ABC ａｂｃ", true).can_submit);
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
