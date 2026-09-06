//! 公演 (show) 詳細ページの DTO。

use super::common::{AppOpen, DateBadge, Ref, SeoBlock, StatTile};
use super::idol::ProfileRow;
use crate::domain::setlist_lineup::Lineup;

web_dto! {
    /// `/shows/<id>/` の中身。
    pub struct ShowPage {
        pub schema_version: u32,
        /// キャラライブか (`shows.performer_type == "character"`)。
        /// 歌唱者の表示モード「公演に合わせる」がこれを見る。
        pub is_character_live: bool,
        pub id: String,
        pub path: String,
        /// ページの見出し。ふつうは**ライブ名** — 公演の主はライブで、`Day2` は見分けでしかない。
        ///
        /// 公演名がライブ名を丸ごと含む稀な形 (`★グランドフィナーレ★(… Live Broadcast)`) では
        /// 公演名そのものが見出しになり、`show_label` は無い。規則は `<title>` と同じ。
        pub heading: String,
        /// 見出しに添える公演の見分け (`Day2` / `昼公演`)。公演名からライブ名と重なる部分を
        /// 落としたもので、規則は「他の公演」のチップと同じ `distinguishing_show_name`。
        /// 公演名がライブ名そのものなら `None`。
        pub show_label: Option<String>,
        /// ヒーローに置く日付ブロック (月日・曜日・年)。
        pub date_badge: DateBadge,
        /// これから開催される公演か (`開催予定` の札)。境界は一覧の年グループと同じ規則。
        pub is_upcoming: bool,
        pub theme_key: String,
        pub event: Ref,
        pub brand: Option<Ref>,
        /// ヒーローに置く「事実の並び」(開演・会場・ホール・所在地・配信)。
        /// 日程は `date_badge` が持つのでここには無い。どの行を出すか・順・見出し・
        /// 会場へのリンクはここで決めてある。曲の `fact_rows` と同じ形。
        pub fact_rows: Vec<ProfileRow>,
        /// 数の帯 (曲数・出演者)。0 は落としてある。
        pub stat_tiles: Vec<StatTile>,
        /// セトリ。区切り (本編 / アンコール / 合同ライブのブロック) ごとの塊で、
        /// 塊の中は position 昇順。塊の切り方と見出しの畳み方は
        /// `domain::setlist_sections` が持つ。
        pub setlist_sections: Vec<SetlistSection>,
        /// `show_cast` (sort_order 順)。
        pub cast: Vec<Ref>,
        /// 同一ライブ内の他公演 (前後移動用。自分自身も含む)。
        pub sibling_shows: Vec<Ref>,
        pub app: AppOpen,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// セトリの 1 区切り。`label` が無いのは区切り無し (本編)。
    ///
    /// 先頭の塊は見出し無しが普通。合同ライブでは見出し付きの塊と無しの塊が交互に来る
    /// ので、2 つ目以降の見出し無しも「前の塊の続き」ではなく別の塊として届く。
    #[derive(Eq)]
    pub struct SetlistSection {
        /// `アンコール` / `LL` など。綴り揺れ (`encore` / `ENCORE`) は畳んである。
        pub label: Option<String>,
        pub rows: Vec<SetlistRow>,
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
        /// 区切り (アンコール) をまたいでも通しで数える。
        pub number: u32,
        pub notes: Option<String>,
        /// `setlist_items.unit_name`。**この披露限りの表記**で、曲のユニットとは別物。
        pub unit_label: Option<String>,
        pub song: Ref,
        /// 歌唱メンバー。`display_name` は**コアが現任 CV で解決済み**。
        pub performers: Vec<PerformerRef>,
        /// 公演の出演者全員で歌う行なら `全員`。
        /// 判定 (出演者 2 人以上・歌唱者と完全一致) は `domain::setlist_lineup::is_full_cast`。
        /// 名前を全部並べる代わりにこの札を出し、名前は畳んでおく。
        pub full_cast_label: Option<String>,
        /// 原唱者 (オリメン) との関係。判定できない行・当たり前の行 (ソロ曲を本人が歌う) ・
        /// 全員曲の部分一致には付かない。規則は `domain::setlist_lineup::lineup_note`。
        pub lineup: Option<LineupNote>,
        /// `songs.song_type == "cover"` (曲そのものがカバー曲)。
        pub is_cover: bool,
    }
}

web_dto! {
    /// 歌唱者と原唱者 (オリメン) の関係の札。
    #[derive(Eq)]
    pub struct LineupNote {
        /// 関係の種類 (`original` / `originalPlus` / `partial` / `cover`)。CSS の見分け用。
        pub kind: Lineup,
        /// `オリメン` / `オリメン+α` / `オリメン 4/5` (何人中何人いるか) / `オリメン不在`。
        pub label: String,
        /// 歌っていない原唱者のうち、**その公演には出ている人**。いなければ `None`。
        /// 公演にいない人は出演者一覧で分かるので並べず、数は `label` が持つ
        /// (規則は `domain::setlist_lineup::absent_in_cast`)。
        pub missing: Option<MissingOriginals>,
    }
}

web_dto! {
    /// 「いたのに歌わなかった」原唱者の並び。言葉 (`不参加`) と人を一緒に運ぶ。
    #[derive(Eq)]
    pub struct MissingOriginals {
        pub label: String,
        /// 原唱者の並び順。空にはならない。
        pub idols: Vec<Ref>,
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
