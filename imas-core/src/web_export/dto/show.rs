//! 公演 (show) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use serde::{Deserialize, Serialize};

/// `/shows/<id>/` の中身。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct ShowPage {
    pub schema_version: u32,
    pub id: String,
    pub path: String,
    pub name: String,
    pub date: String,
    pub short_date: String,
    pub theme_key: String,
    pub event: Ref,
    pub brand: Option<Ref>,
    pub venue_label: Option<String>,
    pub venue: Option<Ref>,
    pub venue_city: Option<String>,
    pub hall: Option<String>,
    pub start_time: Option<String>,
    pub stream_platform: Option<String>,
    /// position 昇順。
    pub setlist: Vec<SetlistRow>,
    /// `show_cast` (sort_order 順)。
    pub cast: Vec<Ref>,
    /// 同一ライブ内の他公演 (前後移動用。自分自身も含む)。
    pub sibling_shows: Vec<Ref>,
    pub app: AppOpen,
    pub seo: SeoBlock,
}

/// セトリの 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SetlistRow {
    pub id: String,
    pub position: i32,
    /// アンコール等の区切り。
    pub section: Option<String>,
    pub notes: Option<String>,
    /// `setlist_items.unit_name`。**この披露限りの表記**で、曲のユニットとは別物。
    pub unit_label: Option<String>,
    pub song: Ref,
    /// 歌唱メンバー。`display_name` は**コアが現任 CV で解決済み**。
    pub performers: Vec<PerformerRef>,
    /// 原唱者 (`song_artists.role = 'original'`)。
    pub original_artists: Vec<Ref>,
    /// `songs.song_type == "cover"`。
    pub is_cover: bool,
}

/// 歌唱メンバー 1 人。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct PerformerRef {
    #[serde(rename = "ref")]
    pub reference: Ref,
    /// 表示名 (CV 名で歌った回など、アイドル名と違うことがある)。
    pub display_name: String,
    pub idol_name: String,
}
