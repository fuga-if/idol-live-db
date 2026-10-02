//! アプリの行き先一覧 (タブバー / サイドバー) の FFI 面。ロジックは domain::app_navigation。
//!
//! 1 ユーザー操作 = 1 呼び出し: ルート画面を組む時点で 1 回だけ呼ぶ。

use crate::domain::app_navigation::{self, AppDestination, NavItem, NavSection};

/// タブバーとサイドバーに並べる行き先を、見出しごとに返す。
#[uniffi::export]
pub fn app_navigation_sections(lyrics_available: bool) -> Vec<NavSection> {
    app_navigation::app_navigation(lyrics_available)
}

/// ユーザーが選んだタブバー (計測キーの並び。空なら既定) で、行き先を見出しごとに返す。
/// 先頭 (見出しなし) がタブバー、タブから外した主な画面と AI チャットは「そのほか」。
#[uniffi::export]
pub fn app_navigation_sections_with_tabs(
    lyrics_available: bool,
    assistant_available: bool,
    tab_keys: Vec<String>,
) -> Vec<NavSection> {
    app_navigation::app_navigation_with_tabs(lyrics_available, assistant_available, &tabs_from_keys(&tab_keys))
}

/// タブバーに選べる行き先 (このビルドで出せるものすべて)。
#[uniffi::export]
pub fn tab_bar_choices(lyrics_available: bool, assistant_available: bool) -> Vec<NavItem> {
    app_navigation::tab_bar_choices(lyrics_available, assistant_available)
}

/// 選んだタブバーを出せる形に整えて、計測キーの並びで返す (保存する値)。空なら既定。
#[uniffi::export]
pub fn normalize_tab_bar_keys(lyrics_available: bool, assistant_available: bool, tab_keys: Vec<String>) -> Vec<String> {
    app_navigation::normalize_tab_bar(&tabs_from_keys(&tab_keys), lyrics_available, assistant_available)
        .into_iter()
        .map(|d| d.analytics_key().to_string())
        .collect()
}

/// タブバーに載せられる数の上限。
#[uniffi::export]
pub fn max_tab_bar_count() -> u32 {
    app_navigation::MAX_TABS as u32
}

fn tabs_from_keys(keys: &[String]) -> Vec<AppDestination> {
    let tabs: Vec<AppDestination> = keys.iter().filter_map(|k| AppDestination::from_key(k)).collect();
    if tabs.is_empty() { app_navigation::default_tab_bar() } else { tabs }
}
