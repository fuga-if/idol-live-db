//! 歌詞の投稿の FFI 面。規則は [`crate::domain::lyric_submission`]。

use crate::domain::lyric_submission::{self as domain, LyricSourceKind, LyricSubmissionCheck, LyricSubmissionIssue};

/// 入力元の選択肢 (この順に出す)。
#[uniffi::export]
pub fn lyric_source_kinds() -> Vec<LyricSourceKind> {
    domain::SOURCE_KINDS.to_vec()
}

/// サーバへ送る入力元の文字列 (`booklet` / `official` / `listening`)。
#[uniffi::export]
pub fn lyric_source_key(kind: LyricSourceKind) -> String {
    domain::source_key(kind).into()
}

/// 入力元の名前 (「CD の歌詞カード」など)。
#[uniffi::export]
pub fn lyric_source_label(kind: LyricSourceKind) -> String {
    domain::source_label(kind).into()
}

/// 入力元の説明 1 行。
#[uniffi::export]
pub fn lyric_source_detail(kind: LyricSourceKind) -> String {
    domain::source_detail(kind).into()
}

/// 入力のたびに通す。整えた本文・行数・文字数・注意・送れるか。
#[uniffi::export]
pub fn lyric_submission_check(text: String, source: Option<LyricSourceKind>, attested_no_copy: bool) -> LyricSubmissionCheck {
    domain::check_submission(&text, source, attested_no_copy)
}

/// 注意の文。
#[uniffi::export]
pub fn lyric_submission_issue_message(issue: LyricSubmissionIssue) -> String {
    domain::issue_message(&issue)
}

/// 送信を止める注意か (止めないものは注意として出すだけ)。
#[uniffi::export]
pub fn lyric_submission_issue_blocks(issue: LyricSubmissionIssue) -> bool {
    domain::blocks_submit(&issue)
}

/// 本文の文字数の上限 (UTF-16)。
#[uniffi::export]
pub fn lyric_submission_max_chars() -> u32 {
    domain::MAX_CHARS
}
