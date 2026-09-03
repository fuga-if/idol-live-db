//! 公演 (show) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};

web_dto! {
    /// `/shows/<id>/` の中身。
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
}

web_dto! {
    /// セトリの 1 行。
    #[derive(Eq)]
    pub struct SetlistRow {
        pub id: String,
        /// **公演内で何曲目か (1 始まり)。画面に出す番号はこちら。**
        ///
        /// [`Self::position`] は `setlist_items` 全体を通した並び順の値で、実データでは
        /// 11593 のような大きな数になる。並べ替えの鍵としては正しいが、そのまま番号として
        /// 描くと読めない。どちらを出すかは表示の判断なので、Rust 側で決めておく。
        pub number: u32,
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
}

web_dto! {
    /// 歌唱メンバー 1 人。
    #[derive(Eq)]
    pub struct PerformerRef {
        #[serde(rename = "ref")]
        pub reference: Ref,
        /// 表示名 (CV 名で歌った回など、アイドル名と違うことがある)。
        /// 表示名 (CV 名で歌った回など、アイドル名と違うことがある)。
        /// アイドル名そのものは `reference.name` にある。
        pub display_name: String,
    }
}
