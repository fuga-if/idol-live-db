//! P名刺ページ (`/p/`) が参照用に読む小さな台帳 (`p/catalog.json`)。
//!
//! 名刺の中身 (名前・ひとこと・担当・リンク・公演数) はすべて URL の `#` の後ろに
//! 入っていて、ブラウザが wasm 経由で `imas_core::domain::producer_card` を直接呼んで
//! 読み解く (サーバには何も無い)。この JSON が持つのは、名刺に載っている **id から
//! 名前・色・URL を引くための台帳**だけ (担当アイドルと、今後の公演) と、
//! 「アプリで開く」導線に要る固定文字列。
//!
//! 今後の公演しか載せないのは、`next_show_id` が指すのは常に「次の現場」であり、
//! 過去の公演を指す名刺はそもそも「次の現場」欄を出さない判断にしてあるため
//! (`domain::event_detail_queries::upcoming_shows` と同じ境界)。全公演を載せると
//! この 1 ファイルが数千件規模になり、名刺ページが読むには重すぎる。

use super::common::{Ref, SeoBlock};

web_dto! {
    pub struct CardCatalog {
        pub schema_version: u32,
        /// 担当 (`oshi_idol_ids`) を解決するための全アイドル。
        pub idols: Vec<Ref>,
        /// 担当のブランド (アイドルの id → ブランドの id)。名刺の表で担当をブランドごとに並べるのに
        /// 使う (ページが `CardOshiEntry` に詰めて wasm の `producer_card_face_json` に渡す)。
        /// ブランドの無いアイドルは載せない。
        pub idol_brand_ids: std::collections::BTreeMap<String, String>,
        /// 名刺の表に刷るブランドの略称 (ブランドの id → 略称。「765AS」「学マス」)。
        pub brand_labels: std::collections::BTreeMap<String, String>,
        /// 「次の現場」(`next_show_id`) を解決するための、今日以降の公演。
        pub upcoming_shows: Vec<Ref>,
        /// 「アプリで開いて名刺入れに入れる」導線。
        pub app_store_url: String,
        /// `<この値><#の後ろ>` でカスタムスキームの URL になる (`"imaslivedb://p#"`)。
        /// 値そのものが名刺の読み取り (`decode_producer_card`) が認める prefix と同じもの。
        pub deeplink_prefix: String,
        pub app_open_title: String,
        pub app_open_note: String,
        /// 読み解けない名刺のときに出す文面。
        pub unreadable_text: String,
        /// `/p/` の `<head>`。個人の名刺なので常に noindex
        /// (`Robots::NoindexFollow`)。パンくず・JSON-LD は持たない
        /// (どこにも位置しない、`404.html` と同じ扱い)。
        pub seo: SeoBlock,
    }
}
