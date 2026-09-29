//! 会場 (venue) 詳細ページの DTO。

use super::common::{AppOpen, EmptyText, Ref, SeoBlock};
use super::idol::ProfileRow;
use super::event::ShowSummary;

web_dto! {
    /// `/venues/<id>/` の中身。
    pub struct VenuePage {
        pub schema_version: u32,
        pub id: String,
        pub path: String,
        pub name: String,
        pub name_kana: Option<String>,
        pub theme_key: String,
        /// 都道府県 (文字列。空のものは一覧では `未分類` に集める)。
        pub prefecture: Option<String>,
        /// 「千葉県 千葉市美浜区」。都道府県と市区町村の連結を TS に書かせない。
        pub location_display: Option<String>,
        pub capacity: Option<i32>,
        pub halls: Vec<HallRow>,
        /// 旧称。
        pub past_names: Vec<VenueNameRow>,
        /// 「基本情報」の行 (所在・収容人数・別名)。曲の `fact_rows` と同じ形。
        pub fact_rows: Vec<ProfileRow>,
        pub events: Vec<Ref>,
        pub shows: Vec<ShowSummary>,
        /// 公演の記録が 1 つも無いときの案内。
        pub shows_empty: Option<EmptyText>,
        pub app: AppOpen,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// ホール (同一会場内の区画)。
    #[derive(Eq)]
    pub struct HallRow {
        pub name: String,
        pub capacity: Option<i32>,
        /// 収容人数の表記 (`9000人`)。人数が無ければ `None`。
        pub capacity_display: Option<String>,
    }
}

web_dto! {
    /// 旧称の 1 行 (命名権で会場名が変わる)。
    #[derive(Eq)]
    pub struct VenueNameRow {
        pub name: String,
        /// 「1999-04-01 〜 2010-03-31」。片側しか無い場合は「〜 2010-03-31」「1999-04-01 〜」。
        /// どちらも無ければ `None` (期間の行を出さない)。
        pub period_display: Option<String>,
    }
}
