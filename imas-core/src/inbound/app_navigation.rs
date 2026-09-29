//! アプリの行き先一覧 (タブバー / サイドバー) の FFI 面。ロジックは domain::app_navigation。
//!
//! 1 ユーザー操作 = 1 呼び出し: ルート画面を組む時点で 1 回だけ呼ぶ。

use crate::domain::app_navigation::{self, NavSection};

/// タブバーとサイドバーに並べる行き先を、見出しごとに返す。
#[uniffi::export]
pub fn app_navigation_sections(lyrics_available: bool) -> Vec<NavSection> {
    app_navigation::app_navigation(lyrics_available)
}
