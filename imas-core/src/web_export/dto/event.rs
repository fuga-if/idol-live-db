//! ライブ (event) 詳細ページの DTO。

use super::common::{AppOpen, DateBadge, Ref, SeoBlock, StatTile};

web_dto! {
    /// `/events/<id>/` の中身 (`events/<key>.json`)。
    pub struct EventPage {
        pub schema_version: u32,
        pub id: String,
        pub path: String,
        pub name: String,
        pub name_kana: Option<String>,
        pub theme_key: String,
        pub brand: Option<Ref>,
        /// 合同ライブの相手ブランド (`events.joint_brand_ids` を分割して引いたもの)。
        pub joint_brands: Vec<Ref>,
        /// `live` / `festival` / `release_event` / `other` / `radio` / `stream`。
        pub kind: String,
        /// 種別チップに出す日本語表記。
        pub kind_label: String,
        /// 開催期間を曜日つきで 1 本にしたもの (`2026-09-19 (土) 〜 2026-09-20 (日)`)。
        /// 日付が無ければ `None`。
        pub date_display: Option<String>,
        /// `first_date >= todayJst`。判定は `event_grouping::group_events_by_year` を
        /// 1 要素で呼んだ結果で、**`>=` をここに書かない** (規則を二重に持たないため)。
        pub is_upcoming: bool,
        pub ticket: TicketInfo,
        /// 数の帯 (公演 / のべ曲数 / 異なり曲数 / 出演者)。**0 は落としてある**
        /// (開催前は曲数が全部 0 で、並べても「まだ無い」以上のことを言わない)。
        pub stat_tiles: Vec<StatTile>,
        pub shows: Vec<ShowSummary>,
        /// `event_attendance` が `None` を返しうるので `Option`。
        /// v1 の Web は公演ごとの出演者だけを出し、欠席マトリクスは描かない。
        pub cast: Option<EventCast>,
        /// 円盤。Bundle DB では常に空。
        pub releases: Vec<ReleaseInfo>,
        /// 公演会場の重複排除 (初出順)。
        pub venues: Vec<Ref>,
        pub app: AppOpen,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// チケット情報 (列をそのまま写す)。
    #[derive(Eq)]
    pub struct TicketInfo {
        pub open_date: Option<String>,
        pub deadline: Option<String>,
        pub lottery_date: Option<String>,
        pub url: Option<String>,
    }
}

web_dto! {
    /// 公演 1 件の要約 (ライブ詳細・会場詳細・トップの「最近の公演」で使い回す)。
    ///
    /// **並べる場所によって見出しが変わる。** ライブ詳細の中では公演名が見出しで、
    /// ライブの外 (トップ・会場) ではライブ名が見出しになり、公演名は [`Self::show_label`]
    /// として副題へ回る。どちらの文脈かは JSON を作る側 (`emit::events::ShowContext`) が
    /// 決めていて、TS は来た形を置くだけ。
    #[derive(Eq)]
    pub struct ShowSummary {
        #[serde(rename = "ref")]
        pub reference: Ref,
        /// 行の見出し (文脈によって公演名かライブ名)。
        pub title: String,
        /// 公演名からライブ名と重なる部分を落としたもの (`DAY1`)。ライブ名を見出しにする
        /// 文脈で副題に置く。ライブ詳細の中 (見出しが公演名) では `None`、
        /// 公演名がライブ名そのものでも `None` (同じ名前を 2 行続けない)。
        /// 規則は披露履歴の `placeDisplay` と同じ `distinguishing_show_name`。
        pub show_label: Option<String>,
        pub date: String,
        /// 行の左端に置く日付ブロック。
        pub date_badge: DateBadge,
        /// `shows.venue_label` (会場マスタに紐付かない自由記述もある)。
        /// **会場詳細の中では `None`** (全行その会場なので繰り返さない)。
        pub venue_label: Option<String>,
        pub hall: Option<String>,
        /// `17:30 開演`。
        pub start_time_display: Option<String>,
        pub setlist_count: u32,
    }
}

web_dto! {
    /// 出演者。**公演ごとに、出た人と役割を結合済みで持つ。**
    ///
    /// 以前は「アイドル id の並行配列 3 本」(`presence` / `lead` / `guest`) だった。
    /// 描画側が毎ページ id → 実体の結合と主演/ゲスト判定をやり直すことになり、
    /// 「そのまま描ける形まで作り込む」という DTO の方針から外れていた。
    #[derive(Eq)]
    pub struct EventCast {
        /// 公演の並びは `shows_by_event` (date ASC, sort_order ASC) のまま。
        pub shows: Vec<EventCastShow>,
    }
}

web_dto! {
    /// 公演 1 本ぶんの出演者。
    #[derive(Eq)]
    pub struct EventCastShow {
        pub show: Ref,
        pub performers: Vec<EventCastMember>,
    }
}

web_dto! {
    /// 出演者 1 人と、その公演での役割。
    #[derive(Eq)]
    pub struct EventCastMember {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub is_lead: bool,
        pub is_guest: bool,
    }
}

web_dto! {
    /// 円盤 (Blu-ray / DVD / CD)。
    #[derive(Eq)]
    pub struct ReleaseInfo {
        pub id: String,
        pub title: String,
        pub kind: Option<String>,
        /// 種別の表示名。種別が無いものは「リリース」。
        pub kind_label: String,
        pub release_date: Option<String>,
        pub url: Option<String>,
    }
}
