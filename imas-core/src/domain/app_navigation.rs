//! **アプリの行き先の一覧 (IA)** をデータで返す層。
//!
//! 狭い画面では下のタブバー、広い画面 (iPad / Mac / Android タブレット) では
//! サイドバーになる。どちらも「どの行き先が・どの順で・どの見出しの下に並ぶか」は
//! 同じ規則から出す。
//!
//! # なぜコアにあるか
//!
//! タブの並びはこれまで iOS の `ContentView` と Android の Scaffold にそれぞれ
//! 書かれていた。サイドバーはタブより行き先が多く (タブバーに載らない
//! 「年表」「みんなの投票」などを足す)、しかも Web のナビとも揃えたい。
//! 並び・所属・出し分けを各 OS で書けば必ず片方だけ直る。
//!
//! # 意図的に持たないもの
//!
//! - アイコン (SF Symbols / Material は OS ごとに別物なので各 OS が行き先から引く)
//! - 画面遷移の実行 (行き先の種類だけを返す)

/// アプリの行き先。タブにもサイドバーにも同じ値を使う。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum AppDestination {
    Schedule,
    Events,
    Songs,
    Idols,
    Produce,
    Stats,
    Timeline,
    Polls,
    CallGuide,
    CommunityActivity,
    TagActivity,
    Games,
    /// AI チャット (試作。出せるビルドだけ)。
    Assistant,
}

impl AppDestination {
    /// 計測キーから行き先を引く (タブバーの並びの保存値を読むのに使う)。知らないキーは None。
    pub fn from_key(key: &str) -> Option<Self> {
        ALL.iter().copied().find(|d| d.analytics_key() == key)
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Schedule => "スケジュール",
            Self::Events => "ライブ",
            Self::Songs => "楽曲",
            Self::Idols => "アイドル",
            Self::Produce => "プロデュース",
            Self::Stats => "調べる",
            Self::Timeline => "年表",
            Self::Polls => "みんなの投票",
            Self::CallGuide => "コールガイド",
            Self::CommunityActivity => "みんなの動き",
            Self::TagActivity => "タグの動き",
            Self::Games => "クイズ・ゲーム",
            Self::Assistant => "AIチャット",
        }
    }

    /// 計測に使う画面名。**表示名で計測しない** (文言を直した瞬間に系列が切れる)。
    pub fn analytics_key(self) -> &'static str {
        match self {
            Self::Schedule => "schedule",
            Self::Events => "events",
            Self::Songs => "songs",
            Self::Idols => "idols",
            Self::Produce => "produce",
            Self::Stats => "stats",
            Self::Timeline => "timeline",
            Self::Polls => "polls",
            Self::CallGuide => "call_guide",
            Self::CommunityActivity => "community_activity",
            Self::TagActivity => "tag_activity",
            Self::Games => "games",
            Self::Assistant => "assistant",
        }
    }
}

/// 行き先 1 つぶん。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct NavItem {
    pub destination: AppDestination,
    pub label: String,
    pub analytics_key: String,
    /// 狭い画面のタブバーにも載るか。false はサイドバーにだけ出る
    /// (狭い画面ではプロデュースの入口カードから辿る)。
    pub in_tab_bar: bool,
    /// ハードウェアキーボードの ⌘ + 数字。タブバーに載るものにだけ 1 から振る。
    pub shortcut_digit: Option<u8>,
}

/// 見出し 1 つぶん。`title` が無いのは先頭の主要な行き先。
/// 見出しは中の行き先と同じ名前にしない (「調べる」の下に「調べる」が並んで読めなくなる)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct NavSection {
    pub title: Option<String>,
    pub items: Vec<NavItem>,
}

/// 行き先すべて (選べる並びの順)。
const ALL: [AppDestination; 13] = [
    AppDestination::Schedule,
    AppDestination::Events,
    AppDestination::Songs,
    AppDestination::Idols,
    AppDestination::Produce,
    AppDestination::Assistant,
    AppDestination::Stats,
    AppDestination::Timeline,
    AppDestination::Polls,
    AppDestination::CallGuide,
    AppDestination::CommunityActivity,
    AppDestination::TagActivity,
    AppDestination::Games,
];

/// タブバーに載せられる数の上限 (iPhone のタブバーは 5 を超えると「その他」に畳まれる)。
pub const MAX_TABS: usize = 5;

/// 既定のタブバー。並びはタブバーの左から。
const PRIMARY: [AppDestination; 5] = [
    AppDestination::Schedule,
    AppDestination::Events,
    AppDestination::Songs,
    AppDestination::Idols,
    AppDestination::Produce,
];

/// サイドバーだけに出る行き先の見出しと並び。
/// 中身はプロデュースの入口カードと同じ画面 (広い画面で 1 段浅く出すだけ)。
const SECONDARY: [(&str, &[AppDestination]); 3] = [
    ("データ", &[AppDestination::Stats, AppDestination::Timeline]),
    (
        "みんな",
        &[
            AppDestination::Polls,
            AppDestination::CallGuide,
            AppDestination::CommunityActivity,
            AppDestination::TagActivity,
        ],
    ),
    ("あそぶ", &[AppDestination::Games]),
];

/// 既定のタブバー。
pub fn default_tab_bar() -> Vec<AppDestination> {
    PRIMARY.to_vec()
}

/// このビルドで出せる行き先か。
fn is_available(d: AppDestination, lyrics_available: bool, assistant_available: bool) -> bool {
    match d {
        AppDestination::CallGuide => lyrics_available,
        AppDestination::Assistant => assistant_available,
        _ => true,
    }
}

/// タブバーに選べる行き先 (このビルドで出せるものすべて)。
pub fn tab_bar_choices(lyrics_available: bool, assistant_available: bool) -> Vec<NavItem> {
    ALL.iter()
        .copied()
        .filter(|&d| is_available(d, lyrics_available, assistant_available))
        .map(|d| item(d, false, None))
        .collect()
}

/// ユーザーが選んだタブバーを、出せる形に整える。
///
/// - 重複と、このビルドで出せない行き先は落とす
/// - プロデュースは必ず載せる (設定・マイページと、タブから外した画面の入口がここにあるため)
/// - [`MAX_TABS`] を超えた分は、プロデュース以外を後ろから落とす
pub fn normalize_tab_bar(
    tabs: &[AppDestination],
    lyrics_available: bool,
    assistant_available: bool,
) -> Vec<AppDestination> {
    let mut out: Vec<AppDestination> = Vec::new();
    for &d in tabs {
        if is_available(d, lyrics_available, assistant_available) && !out.contains(&d) {
            out.push(d);
        }
    }
    if !out.contains(&AppDestination::Produce) {
        out.push(AppDestination::Produce);
    }
    while out.len() > MAX_TABS {
        let drop = out.iter().rposition(|&d| d != AppDestination::Produce).expect("produce 以外がある");
        out.remove(drop);
    }
    out
}

/// アプリの行き先を見出しごとに返す (既定のタブバー)。
///
/// `lyrics_available`: 歌詞を出せるビルドか。出せないビルドではコールガイドを
/// 書く場所そのものが無いので、行き先ごと出さない (プロデュースの入口と同じ根拠)。
pub fn app_navigation(lyrics_available: bool) -> Vec<NavSection> {
    app_navigation_with_tabs(lyrics_available, false, &PRIMARY)
}

/// タブバーから外した主な画面と AI チャットを置く見出し。
pub const OTHERS_TITLE: &str = "そのほか";

/// ユーザーが選んだタブバーで、行き先を見出しごとに返す。
///
/// 先頭 (見出しなし) がタブバー。タブに載せた行き先は下の見出しから外し、
/// タブから外した主な画面 (スケジュール・ライブ・楽曲・アイドル) と AI チャットは
/// 「そのほか」の見出しに並べる (狭い画面ではプロデュースから辿る)。
pub fn app_navigation_with_tabs(
    lyrics_available: bool,
    assistant_available: bool,
    tabs: &[AppDestination],
) -> Vec<NavSection> {
    let tabs = normalize_tab_bar(tabs, lyrics_available, assistant_available);
    let primary = NavSection {
        title: None,
        items: tabs.iter().enumerate().map(|(i, &d)| item(d, true, Some(i as u8 + 1))).collect(),
    };
    let others: Vec<NavItem> = PRIMARY
        .iter()
        .copied()
        .chain(std::iter::once(AppDestination::Assistant))
        .filter(|&d| is_available(d, lyrics_available, assistant_available) && !tabs.contains(&d))
        .map(|d| item(d, false, None))
        .collect();
    let others = (!others.is_empty()).then(|| NavSection { title: Some(OTHERS_TITLE.to_string()), items: others });
    let secondary = SECONDARY.iter().filter_map(|&(title, dests)| {
        let items: Vec<NavItem> = dests
            .iter()
            .copied()
            .filter(|&d| is_available(d, lyrics_available, assistant_available) && !tabs.contains(&d))
            .map(|d| item(d, false, None))
            .collect();
        (!items.is_empty()).then(|| NavSection { title: Some(title.to_string()), items })
    });
    std::iter::once(primary).chain(others).chain(secondary).collect()
}

fn item(destination: AppDestination, in_tab_bar: bool, shortcut_digit: Option<u8>) -> NavItem {
    NavItem {
        destination,
        label: destination.label().to_string(),
        analytics_key: destination.analytics_key().to_string(),
        in_tab_bar,
        shortcut_digit,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn all_items(sections: &[NavSection]) -> Vec<&NavItem> {
        sections.iter().flat_map(|s| s.items.iter()).collect()
    }

    #[test]
    fn tab_bar_is_the_five_primary_tabs_in_order() {
        let nav = app_navigation(true);
        let tabs: Vec<AppDestination> = all_items(&nav)
            .into_iter()
            .filter(|i| i.in_tab_bar)
            .map(|i| i.destination)
            .collect();
        assert_eq!(tabs, PRIMARY.to_vec());
    }

    #[test]
    fn shortcuts_are_one_to_five_on_tabs_only() {
        let nav = app_navigation(true);
        let digits: Vec<Option<u8>> = all_items(&nav).iter().map(|i| i.shortcut_digit).collect();
        assert_eq!(&digits[..5], &[Some(1), Some(2), Some(3), Some(4), Some(5)]);
        assert!(digits[5..].iter().all(Option::is_none));
    }

    #[test]
    fn every_destination_appears_once_when_lyrics_available() {
        let nav = app_navigation(true);
        let items = all_items(&nav);
        assert_eq!(items.len(), 12);
        let mut seen = std::collections::HashSet::new();
        assert!(items.iter().all(|i| seen.insert(i.destination)));
    }

    #[test]
    fn call_guide_is_hidden_without_lyrics() {
        let nav = app_navigation(false);
        assert!(all_items(&nav).iter().all(|i| i.destination != AppDestination::CallGuide));
        // 見出しは残る (みんなの投票などが居る)
        assert!(nav.iter().any(|s| s.title.as_deref() == Some("みんな")));
    }

    #[test]
    fn chosen_tabs_keep_produce_and_cap_at_five() {
        use AppDestination::*;
        let tabs = normalize_tab_bar(&[Songs, Songs, Assistant, Games, Stats, Timeline, Polls], true, true);
        assert_eq!(tabs, vec![Songs, Assistant, Games, Stats, Produce]);
        // 出せない AI は落ちる
        assert_eq!(normalize_tab_bar(&[Assistant, Idols], true, false), vec![Idols, Produce]);
        // 空でもプロデュースだけは残る
        assert_eq!(normalize_tab_bar(&[], true, true), vec![Produce]);
    }

    #[test]
    fn removed_main_tabs_and_assistant_go_to_others() {
        use AppDestination::*;
        let nav = app_navigation_with_tabs(true, true, &[Events, Songs, Stats, Produce]);
        let tabs: Vec<_> = nav[0].items.iter().map(|i| i.destination).collect();
        assert_eq!(tabs, vec![Events, Songs, Stats, Produce]);
        assert_eq!(nav[1].title.as_deref(), Some(OTHERS_TITLE));
        let others: Vec<_> = nav[1].items.iter().map(|i| i.destination).collect();
        assert_eq!(others, vec![Schedule, Idols, Assistant]);
        // タブに載せた統計は「データ」から消える
        assert!(all_items(&nav).iter().filter(|i| i.destination == Stats).count() == 1);
    }

    #[test]
    fn keys_round_trip() {
        for d in ALL {
            assert_eq!(AppDestination::from_key(d.analytics_key()), Some(d));
        }
        assert_eq!(AppDestination::from_key("nope"), None);
    }

    #[test]
    fn analytics_keys_are_stable_for_existing_tabs() {
        // 既存の計測系列 (ContentView.tabName) を切らない。
        let keys: Vec<&str> = PRIMARY.iter().map(|d| d.analytics_key()).collect();
        assert_eq!(keys, ["schedule", "events", "songs", "idols", "produce"]);
    }
}
