//! 詳細画面のタブ (`ImasTabs`、DESIGN_SYSTEM §2.2)。
//!
//! 曲・アイドル・ユニット・ライブの詳細は「頭 → タブ → タブの中身」の形で、
//! **どの実体にどのタブを何の順で出すか**と、**中身が無いときに出さないタブ**の線を
//! ここで決める。語は各 OS の画面と同じ (iOS: `SongDetailTab` / `IdolDetailView` /
//! `UnitDetailTab` / `EventDetailView`。まだ Swift 側は写しを持っている)。
//!
//! 出面 (Web) は書き込みが無いので、コミュニティ (タグ・お気に入り・ペンライト) に何も
//! 無い実体ではコミュニティのタブを出さない。アプリは投稿の入口として常に出す。

/// タブ 1 つ。`key` は URL の `#tab-<key>` と各 OS の識別子、`label` は画面の語。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DetailTab {
    pub key: &'static str,
    pub label: &'static str,
}

pub const SONG_INFO: DetailTab = DetailTab { key: "info", label: "情報・歌唱" };
pub const SONG_LYRICS: DetailTab = DetailTab { key: "lyrics", label: "歌詞" };
pub const SONG_HISTORY: DetailTab = DetailTab { key: "history", label: "披露履歴" };
pub const IDOL_LIVE: DetailTab = DetailTab { key: "live", label: "ライブ" };
pub const IDOL_SONGS: DetailTab = DetailTab { key: "songs", label: "楽曲" };
pub const IDOL_PROFILE: DetailTab = DetailTab { key: "profile", label: "プロフィール" };
pub const UNIT_SONGS: DetailTab = DetailTab { key: "songs", label: "楽曲" };
pub const UNIT_MEMBERS: DetailTab = DetailTab { key: "members", label: "メンバー" };
pub const EVENT_SHOWS: DetailTab = DetailTab { key: "shows", label: "公演・セトリ" };
pub const EVENT_CAST: DetailTab = DetailTab { key: "cast", label: "出演" };
pub const EVENT_INFO: DetailTab = DetailTab { key: "info", label: "情報" };
pub const COMMUNITY: DetailTab = DetailTab { key: "community", label: "コミュニティ" };

/// 曲: 情報・歌唱 / 歌詞 / 披露履歴 / コミュニティ。
/// 歌詞は出していない間も (アプリへの案内を載せるので) タブ自体は残す。
pub fn song_detail_tabs(has_community: bool) -> Vec<DetailTab> {
    with_community(vec![SONG_INFO, SONG_LYRICS, SONG_HISTORY], has_community)
}

/// アイドル: ライブ / 楽曲 / プロフィール / コミュニティ。
pub fn idol_detail_tabs(has_community: bool) -> Vec<DetailTab> {
    with_community(vec![IDOL_LIVE, IDOL_SONGS, IDOL_PROFILE], has_community)
}

/// ユニット: 楽曲 / メンバー / コミュニティ。アプリにある呼称表は出面に材料が無い。
pub fn unit_detail_tabs(has_community: bool) -> Vec<DetailTab> {
    with_community(vec![UNIT_SONGS, UNIT_MEMBERS], has_community)
}

/// ライブ: 公演・セトリ / 出演 / 情報。出演者が無ければ「出演」を、
/// 映像・音源もチケットも無ければ「情報」を出さない。
pub fn event_detail_tabs(has_cast: bool, has_info: bool) -> Vec<DetailTab> {
    let mut tabs = vec![EVENT_SHOWS];
    if has_cast {
        tabs.push(EVENT_CAST);
    }
    if has_info {
        tabs.push(EVENT_INFO);
    }
    tabs
}

fn with_community(mut tabs: Vec<DetailTab>, has_community: bool) -> Vec<DetailTab> {
    if has_community {
        tabs.push(COMMUNITY);
    }
    tabs
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(tabs: &[DetailTab]) -> Vec<&'static str> {
        tabs.iter().map(|t| t.key).collect()
    }

    #[test]
    fn song_tabs_follow_app_order_and_drop_empty_community() {
        assert_eq!(keys(&song_detail_tabs(true)), ["info", "lyrics", "history", "community"]);
        assert_eq!(keys(&song_detail_tabs(false)), ["info", "lyrics", "history"]);
        assert_eq!(song_detail_tabs(true).iter().map(|t| t.label).collect::<Vec<_>>(), ["情報・歌唱", "歌詞", "披露履歴", "コミュニティ"]);
    }

    #[test]
    fn idol_and_unit_tabs() {
        assert_eq!(keys(&idol_detail_tabs(true)), ["live", "songs", "profile", "community"]);
        assert_eq!(keys(&idol_detail_tabs(false)), ["live", "songs", "profile"]);
        assert_eq!(keys(&unit_detail_tabs(true)), ["songs", "members", "community"]);
        assert_eq!(keys(&unit_detail_tabs(false)), ["songs", "members"]);
    }

    #[test]
    fn event_tabs_drop_cast_and_info_when_nothing_to_show() {
        assert_eq!(keys(&event_detail_tabs(true, true)), ["shows", "cast", "info"]);
        assert_eq!(keys(&event_detail_tabs(false, true)), ["shows", "info"]);
        assert_eq!(keys(&event_detail_tabs(true, false)), ["shows", "cast"]);
        assert_eq!(keys(&event_detail_tabs(false, false)), ["shows"]);
    }

    #[test]
    fn keys_are_unique_within_a_page() {
        for tabs in [song_detail_tabs(true), idol_detail_tabs(true), unit_detail_tabs(true), event_detail_tabs(true, true)] {
            let mut k = keys(&tabs);
            k.sort_unstable();
            k.dedup();
            assert_eq!(k.len(), tabs.len());
        }
    }
}
