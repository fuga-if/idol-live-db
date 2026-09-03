//! ブランド (brand) 詳細ページの DTO。

use super::common::{NavLink, Ref, SeoBlock, StatTile};
use serde::{Deserialize, Serialize};

/// `/brands/<id>/` の中身。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct BrandPage {
    pub schema_version: u32,
    pub id: String,
    pub path: String,
    pub name: String,
    pub short_name: Option<String>,
    pub theme_key: String,
    /// このブランドに属する件数のタイル (ライブ / 楽曲 / アイドル / ユニット)。
    ///
    /// 素の `Counts` を配らないのは、ブランドに紐付かない件数 (会場・セトリ項目) を
    /// 0 で埋めて「web 側がそこを読まない」という口約束に頼る形になるため。
    /// 意味のあるタイルだけを組んで渡す。
    pub stat_tiles: Vec<StatTile>,
    pub idols: Vec<Ref>,
    pub units: Vec<Ref>,
    pub recent_events: Vec<Ref>,
    pub top_songs: Vec<Ref>,
    /// 「このブランドのライブ一覧へ」等の入口。
    pub section_links: Vec<NavLink>,
    pub seo: SeoBlock,
}
