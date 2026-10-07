//! 手応え (公演の閲覧) と公演の奥付の FFI 面。規則は [`crate::domain::contribution_feedback`]。

use crate::domain::contribution_feedback::{ShowCreditInput, ShowCreditLine, ShowViewDecision};

/// 公演ページを開いたときに閲覧を送るか (1 端末 1 週 1 公演 1 回)。保存は OS が行う。
#[uniffi::export]
pub fn show_view_decision(
    stored_week: String,
    reported: Vec<String>,
    show_id: String,
    now_epoch_seconds: i64,
) -> ShowViewDecision {
    crate::domain::contribution_feedback::show_view_decision(&stored_week, &reported, &show_id, now_epoch_seconds)
}

/// 公演ページ末尾の奥付の行 (セトリ → 歌唱者。誰も関わっていない役割は出さない)。
#[uniffi::export]
pub fn show_credit_lines(setlist: ShowCreditInput, performers: ShowCreditInput) -> Vec<ShowCreditLine> {
    crate::domain::contribution_feedback::show_credit_lines(&setlist, &performers)
}

/// 曲の歌詞の奥付 (歌詞入力)。投稿で公開された人がいなければ None。
#[uniffi::export]
pub fn lyrics_credit_line(input: ShowCreditInput) -> Option<ShowCreditLine> {
    crate::domain::contribution_feedback::lyrics_credit_line(&input)
}
