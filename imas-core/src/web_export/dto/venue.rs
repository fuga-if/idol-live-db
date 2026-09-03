//! 会場 (venue) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use super::event::ShowSummary;
use serde::{Deserialize, Serialize};

/// `/venues/<id>/` の中身。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct VenuePage {
    pub schema_version: u32,
    pub id: String,
    pub path: String,
    pub name: String,
    pub name_kana: Option<String>,
    pub theme_key: String,
    /// 都道府県 (文字列。空のものは一覧では `未分類` に集める)。
    pub prefecture: Option<String>,
    pub city: Option<String>,
    pub capacity: Option<i32>,
    pub aliases: Vec<String>,
    pub halls: Vec<HallRow>,
    /// 旧称。
    pub past_names: Vec<VenueNameRow>,
    pub events: Vec<Ref>,
    pub shows: Vec<ShowSummary>,
    pub app: AppOpen,
    pub seo: SeoBlock,
}

/// ホール (同一会場内の区画)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct HallRow {
    pub name: String,
    pub capacity: Option<i32>,
}

/// 旧称の 1 行 (命名権で会場名が変わる)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct VenueNameRow {
    pub name: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
}
