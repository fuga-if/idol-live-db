//! ブランド (brand) 詳細ページの DTO。

use super::common::{NavLink, Ref, SeoBlock};

web_dto! {
    /// `/brands/<id>/` の中身。
    pub struct BrandPage {
        pub schema_version: u32,
        pub id: String,
        pub path: String,
        pub name: String,
        pub short_name: Option<String>,
        pub theme_key: String,
        /// そのブランドの一覧への入口 (ライブ / 楽曲 / アイドル / ユニット)。件数付き。
        ///
        /// 件数タイルを別に持たないのは、ヒーロー直下 100px の間に同じ数字が 2 回
        /// 出ていたため。押せるこちらだけを残す。**一覧を作っていない組み合わせは
        /// そもそも並ばない** (`other` はアイドルだけ) ので、リンク切れにならない。
        pub section_links: Vec<NavLink>,
        pub idols: Vec<Ref>,
        pub units: Vec<Ref>,
        pub recent_events: Vec<Ref>,
        pub top_songs: Vec<Ref>,
        pub seo: SeoBlock,
    }
}
