//! ユニット (unit) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use super::common::TagChipDto;

web_dto! {
    /// `/units/<id>/` の中身。
    pub struct UnitPage {
        pub schema_version: u32,
        pub id: String,
        pub path: String,
        pub name: String,
        pub name_kana: Option<String>,
        /// 別名 (`units.name_alt`)。
        pub name_alt: Option<String>,
        pub theme_key: String,
        /// 常設ユニットか (false = ライブ限定などの期間限定)。
        pub is_permanent: bool,
        /// コミュニティが付けたタグ (多い順)。焼き込み。
        pub tags: Vec<TagChipDto>,
        pub brand: Option<Ref>,
        pub members: Vec<Ref>,
        pub songs: Vec<Ref>,
        pub app: AppOpen,
        pub seo: SeoBlock,
    }
}
