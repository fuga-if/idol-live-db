//! ブランド (brand) 詳細ページの DTO。

use super::common::{Ref, SeoBlock, StatTile};

web_dto! {
    /// `/brands/<id>/` の中身。
    pub struct BrandPage {
        pub schema_version: u32,
        pub id: String,
        pub path: String,
        pub name: String,
        pub short_name: Option<String>,
        pub theme_key: String,
        /// そのブランドの数の帯 (ライブ / 楽曲 / アイドル / ユニット)。押すと一覧へ。
        ///
        /// トップの件数タイルと同じ形。**一覧を作っていない組み合わせは
        /// そもそも並ばない** (`other` はアイドルだけ) ので、リンク切れにならない。
        pub stat_tiles: Vec<StatTile>,
        pub idols: Vec<Ref>,
        pub units: Vec<Ref>,
        pub recent_events: Vec<Ref>,
        pub top_songs: Vec<Ref>,
        pub seo: SeoBlock,
    }
}
