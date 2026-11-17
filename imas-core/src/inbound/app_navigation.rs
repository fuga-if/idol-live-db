//! アプリの行き先一覧 (タブバー / サイドバー) の FFI 面。ロジックは domain::app_navigation。
//!
//! 1 ユーザー操作 = 1 呼び出し: ルート画面を組む時点で 1 回だけ呼ぶ。

use crate::domain::app_navigation::{self, AppDestination, ChatTabOffer, NavItem, NavSection};

/// タブバーとサイドバーに並べる行き先を、見出しごとに返す (既定のタブバー)。
///
/// `chat_connected`: ChatGPT とつないでいるか。つないでいる人にだけチャットを出す。
#[uniffi::export]
pub fn app_navigation_sections(lyrics_available: bool, chat_connected: bool) -> Vec<NavSection> {
    app_navigation::app_navigation(lyrics_available, chat_connected)
}

/// ユーザーが選んだタブバー (計測キーの並び。空なら既定) で、行き先を見出しごとに返す。
/// 先頭 (見出しなし) がタブバー、タブから外した主な画面は「そのほか」。
#[uniffi::export]
pub fn app_navigation_sections_with_tabs(
    lyrics_available: bool,
    chat_connected: bool,
    tab_keys: Vec<String>,
) -> Vec<NavSection> {
    app_navigation::app_navigation_with_tabs(lyrics_available, chat_connected, &tabs_from_keys(&tab_keys))
}

/// タブバーに選べる行き先 (いま出せるものすべて)。
#[uniffi::export]
pub fn tab_bar_choices(lyrics_available: bool, chat_connected: bool) -> Vec<NavItem> {
    app_navigation::tab_bar_choices(lyrics_available, chat_connected)
}

/// 選んだタブバーを出せる形に整えて、計測キーの並びで返す (保存する値)。空なら既定。
#[uniffi::export]
pub fn normalize_tab_bar_keys(lyrics_available: bool, chat_connected: bool, tab_keys: Vec<String>) -> Vec<String> {
    app_navigation::normalize_tab_bar(&tabs_from_keys(&tab_keys), lyrics_available, chat_connected)
        .into_iter()
        .map(|d| d.analytics_key().to_string())
        .collect()
}

/// いまのタブバー (計測キーの並び。空なら既定) に、チャットをどう入れられるか。
/// ChatGPT とつないだときに 1 回訊くのに使う。
#[uniffi::export]
pub fn chat_tab_offer(lyrics_available: bool, tab_keys: Vec<String>) -> ChatTabOffer {
    app_navigation::chat_tab_offer(&tabs_from_keys(&tab_keys), lyrics_available)
}

/// チャットを入れたタブバー (保存する値)。`replace_key` の枠と入れ替える。None なら空きに足す。
#[uniffi::export]
pub fn tab_bar_keys_with_chat(lyrics_available: bool, tab_keys: Vec<String>, replace_key: Option<String>) -> Vec<String> {
    let replace = replace_key.as_deref().and_then(AppDestination::from_key);
    app_navigation::tab_bar_with_chat(&tabs_from_keys(&tab_keys), replace, lyrics_available)
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
