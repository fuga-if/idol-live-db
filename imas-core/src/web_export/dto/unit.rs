//! ユニット (unit) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use serde::{Deserialize, Serialize};

/// `/units/<id>/` の中身。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct UnitPage {
    pub schema_version: u32,
    pub id: String,
    pub path: String,
    pub name: String,
    pub name_kana: Option<String>,
    /// 別名 (`units.name_alt`)。
    pub name_alt: Option<String>,
    pub theme_key: String,
    pub monogram: String,
    /// 常設ユニットか (false = ライブ限定などの期間限定)。
    pub is_permanent: bool,
    pub brand: Option<Ref>,
    pub members: Vec<Ref>,
    pub songs: Vec<Ref>,
    pub app: AppOpen,
    pub seo: SeoBlock,
}
