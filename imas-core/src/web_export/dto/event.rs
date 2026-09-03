//! ライブ (event) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use serde::{Deserialize, Serialize};

/// `/events/<id>/` の中身 (`events/<key>.json`)。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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
    pub event_type: String,
    pub first_date: Option<String>,
    pub last_date: Option<String>,
    /// `first_date >= todayJst`。判定は `event_grouping::group_events_by_year` を
    /// 1 要素で呼んだ結果で、**`>=` をここに書かない** (規則を二重に持たないため)。
    pub is_upcoming: bool,
    pub ticket: TicketInfo,
    pub stats: EventStats,
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

/// チケット情報 (列をそのまま写す)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct TicketInfo {
    pub open_date: Option<String>,
    pub deadline: Option<String>,
    pub lottery_date: Option<String>,
    pub url: Option<String>,
}

/// `event_detail_queries::event_stats` の写し。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct EventStats {
    pub show_count: u32,
    pub total_songs: u32,
    pub unique_songs: u32,
    pub cast_count: u32,
}

/// 公演 1 件の要約 (ライブ詳細・会場詳細・トップの「最近の公演」で使い回す)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct ShowSummary {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub date: String,
    /// `short_year_month::short_year_month(date)` の結果。
    pub short_date: String,
    /// `shows.venue_label` (会場マスタに紐付かない自由記述もある)。
    pub venue_label: Option<String>,
    pub venue: Option<Ref>,
    pub hall: Option<String>,
    pub start_time: Option<String>,
    pub setlist_count: u32,
    pub stream_platform: Option<String>,
    /// ライブ名 (会場ページなど、ライブの外から公演を並べるときに要る)。
    pub event: Option<Ref>,
}

/// 出演者マトリクス。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct EventCast {
    /// このライブのブランドに属するアイドル (表の行)。
    pub brand_idols: Vec<Ref>,
    pub presence_by_show: Vec<ShowIdolIds>,
    pub lead_by_show: Vec<ShowIdolIds>,
    pub guest_by_show: Vec<ShowIdolIds>,
}

/// 公演 1 件ぶんのアイドル id 列。
///
/// `HashMap` をそのまま serde しないのは、反復順が非決定でバイト一致の再現性を
/// 壊すため (T9)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct ShowIdolIds {
    pub show_id: String,
    pub idol_ids: Vec<String>,
}

/// 円盤 (Blu-ray / DVD / CD)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct ReleaseInfo {
    pub id: String,
    pub title: String,
    pub kind: Option<String>,
    /// 種別の表示名。種別が無いものは「リリース」。
    pub kind_label: String,
    pub release_date: Option<String>,
    pub url: Option<String>,
}
