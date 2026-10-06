//! 歌詞の投稿 (ユーザーが一次ソースから入力した歌詞を送る) の入力規則。
//!
//! 歌詞は 2026-10-06 に取り込み元の問題で全削除した。再開は「CD の歌詞カードなどを見て
//! 利用者が入力する」投稿だけで行う。ここは投稿画面が使う規則で、両 OS は
//! [`check_submission`] を入力のたびに通して、整えた本文・行数・注意・送信の可否を出す。
//!
//! - **入力元を必ず選ぶ** ([`LyricSourceKind`])。公表された歌詞 (CD の歌詞カード・公式) だけ。
//!   歌詞サイトは選択肢に無い。聴き取りの書き起こしも受け付けない (公表された歌詞と同じである
//!   保証が無く、作詞者の意に反する改変になりうるため。2026-10-06 オーナー判断)。
//! - **「歌詞サイトから転載していない」の確認が要る。** 確認なしでは送れない。
//! - 上限 (文字数・行数) はサーバ (`imas-live-api` の `routes/lyric_submissions.ts`) と同じ数。
//!   文字数はサーバの `.length` に合わせて UTF-16 で数える。
//! - 作詞・作曲のクレジット行や、本文が 2 回続けて入っているのは、ページを丸ごと貼ったときの
//!   形なので注意を出す (送信は止めない。曲によっては正しい形もありうるため)。

/// 1 曲の本文の上限 (UTF-16)。長い全体曲でも 3,000 字ほど。
pub const MAX_CHARS: u32 = 8000;
/// 1 曲の行数の上限 (空行を含む)。
pub const MAX_LINES: u32 = 400;

/// 歌詞を何を見て入力したか。サーバへは [`source_key`] の文字列で送る。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum LyricSourceKind {
    /// CD のブックレット・歌詞カード。
    Booklet,
    /// 公式サイトや公式の動画に載っている歌詞。
    Official,
}

/// 選択肢の並び (画面はこの順に出す)。
pub const SOURCE_KINDS: [LyricSourceKind; 2] = [LyricSourceKind::Booklet, LyricSourceKind::Official];

pub fn source_key(kind: LyricSourceKind) -> &'static str {
    match kind {
        LyricSourceKind::Booklet => "booklet",
        LyricSourceKind::Official => "official",
    }
}

pub fn source_label(kind: LyricSourceKind) -> &'static str {
    match kind {
        LyricSourceKind::Booklet => "CD の歌詞カード",
        LyricSourceKind::Official => "公式サイト・公式動画",
    }
}

pub fn source_detail(kind: LyricSourceKind) -> &'static str {
    match kind {
        LyricSourceKind::Booklet => "ブックレットや歌詞カードを見ながら入力した",
        LyricSourceKind::Official => "公式に公開されている歌詞を見ながら入力した",
    }
}

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
}

pub fn blocks_submit(issue: &LyricSubmissionIssue) -> bool {
    matches!(
        issue,
        LyricSubmissionIssue::Empty | LyricSubmissionIssue::TooLong { .. } | LyricSubmissionIssue::TooManyLines { .. }
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
    /// 入力元・確認・本文がそろって送れるか。
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

pub fn check_submission(text: &str, source: Option<LyricSourceKind>, attested_no_copy: bool) -> LyricSubmissionCheck {
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
    let can_submit = source.is_some() && attested_no_copy && !issues.iter().any(blocks_submit);
    LyricSubmissionCheck { normalized, line_count, char_count, issues, can_submit }
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
        let c = check_submission(" \n\n", Some(LyricSourceKind::Booklet), true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::Empty]);
        assert!(!c.can_submit);
        assert_eq!(c.line_count, 0);
    }

    #[test]
    fn source_and_attestation_are_both_required() {
        let text = "きらめく\nステージ";
        assert!(!check_submission(text, None, true).can_submit);
        assert!(!check_submission(text, Some(LyricSourceKind::Official), false).can_submit);
        let ok = check_submission(text, Some(LyricSourceKind::Official), true);
        assert!(ok.can_submit);
        assert_eq!((ok.line_count, ok.char_count), (2, 9));
    }

    #[test]
    fn limits_are_counted_on_the_normalized_text() {
        let long = "あ".repeat(MAX_CHARS as usize + 1);
        let c = check_submission(&long, Some(LyricSourceKind::Booklet), true);
        assert!(c.issues.contains(&LyricSubmissionIssue::TooLong { max: MAX_CHARS }));
        assert!(!c.can_submit);

        let many = vec!["ら"; MAX_LINES as usize + 1].join("\n");
        let c = check_submission(&many, Some(LyricSourceKind::Booklet), true);
        assert!(c.issues.contains(&LyricSubmissionIssue::TooManyLines { max: MAX_LINES }));

        // 行末の空白は数えない
        let c = check_submission(&format!("{}   ", "あ".repeat(MAX_CHARS as usize)), Some(LyricSourceKind::Booklet), true);
        assert!(c.can_submit);
    }

    #[test]
    fn credit_lines_and_doubled_body_warn_without_blocking() {
        let c = check_submission("作詞：だれか\n作曲: だれか\nうたう", Some(LyricSourceKind::Booklet), true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::CreditLines]);
        assert!(c.can_submit);
        // 歌詞の中の「作詞家」は行頭でも区切りが続かないので拾わない
        assert!(check_submission("作詞家になりたい", Some(LyricSourceKind::Booklet), true).issues.is_empty());

        let half = "一\n二\n三\n四";
        let c = check_submission(&format!("{half}\n\n{half}"), Some(LyricSourceKind::Booklet), true);
        assert_eq!(c.issues, vec![LyricSubmissionIssue::Doubled]);
        assert!(c.can_submit);
    }

    #[test]
    fn source_keys_match_the_server() {
        let keys: Vec<_> = SOURCE_KINDS.iter().map(|k| source_key(*k)).collect();
        assert_eq!(keys, ["booklet", "official"]);
    }
}
