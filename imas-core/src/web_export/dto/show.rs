//! 公演 (show) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use super::idol::ProfileRow;

web_dto! {
    /// `/shows/<id>/` の中身。
    pub struct ShowPage {
        pub schema_version: u32,
        /// キャラライブか (`shows.performer_type == "character"`)。
        /// 歌唱者の表示モード「公演に合わせる」がこれを見る。
        pub is_character_live: bool,
        pub id: String,
        pub path: String,
        pub name: String,
        /// 公演名からライブ名と重なる部分を落としたもの (`Day2` / `昼公演`)。
        ///
        /// ページの見出しに使う。ライブ名は小見出し (パンくず) が担うので、見出しに
        /// ライブ名を丸ごと繰り返さない。公演名がライブ名そのものなら `None`
        /// (その場合は見出しに公演名をそのまま出し、小見出しを省く)。
        /// 規則は `<title>` や「他の公演」のチップと同じ `distinguishing_show_name`。
        pub short_name: Option<String>,
        pub date: String,
        pub theme_key: String,
        pub event: Ref,
        pub brand: Option<Ref>,
        pub venue_city: Option<String>,
        /// ヒーローに置く「事実の並び」(日程・開演・会場・ホール・配信)。
        /// どの行を出すか・順・見出し・会場へのリンクはここで決めてある。
        /// 曲の `fact_rows` / アイドルの `profile_rows` と同じ形。
        pub fact_rows: Vec<ProfileRow>,
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
        /// 現任 CV 名。**アイドル名と違うときだけ入る** (CV 不在なら `None`)。
        /// アイドル名は `reference.name`。
        ///
        /// **どちらを出すかは受け手が決めない。** 表示の規則は
        /// `domain::event_detail_queries::performer_display_name` が持ち、
        /// 閲覧者が選んだモードに従って主/副を返す。ここは素材を両方渡すだけで、
        /// 「同じ名前を 2 つ持たせない」判断もその関数 (`Both` の副) に任せる。
        pub cast_name: Option<String>,
    }
}
