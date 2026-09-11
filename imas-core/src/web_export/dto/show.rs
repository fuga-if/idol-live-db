//! 公演 (show) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};

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
        /// この公演で着られた衣装 (進行順)。記録が無ければ空。
        pub costumes: Vec<ShowCostume>,
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
        /// この披露で着ていた衣装。記録が無ければ空。
        pub costumes: Vec<SetlistCostume>,
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

web_dto! {
    /// 公演で着られた衣装 1 着。
    ///
    /// **画像は無い。** 版権物を配らない方針なので、名前と出典だけで見分ける。
    #[derive(Eq)]
    pub struct ShowCostume {
        pub id: String,
        pub name: String,
        /// 誰のための衣装か (ユニット名・アイドル名)。共通衣装なら `None`。
        pub attribution: Option<String>,
        pub description: Option<String>,
        /// 出典 (公式)。
        pub source_url: Option<String>,
        /// どこで着たか (「1・5 曲目」「公演のどこか」)。
        ///
        /// **文にするのは Rust の仕事。** 曲番号の列を持たせて出面で繋ぐと、
        /// 区切りも「どこかで着た」の言い方も画面ごとに割れる。
        pub where_label: String,
        /// 着ていた人の 1 行。共通衣装なら `None` (「全員」とは書かない)。
        pub wearers_label: Option<String>,
    }
}

web_dto! {
    /// セトリ行に添える衣装。
    #[derive(Eq)]
    pub struct SetlistCostume {
        pub id: String,
        pub name: String,
        /// 誰のための衣装か。共通衣装なら `None`。
        pub attribution: Option<String>,
        /// その曲でこの衣装を着ていた人。共通衣装なら `None`。
        pub wearers_label: Option<String>,
    }
}
