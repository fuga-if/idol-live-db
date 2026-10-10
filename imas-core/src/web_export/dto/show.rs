//! 公演 (show) 詳細ページの DTO。

use super::common::{AppOpen, DateBadge, EmptyText, Ref, SeoBlock, StatTile};
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
        /// セトリが 1 曲も無いときの案内。
        pub setlist_empty: Option<EmptyText>,
        /// `show_cast` (sort_order 順)。
        pub cast: Vec<Ref>,
        /// この公演で着られた衣装 (進行順)。記録が無ければ空。
        pub costumes: Vec<ShowCostume>,
        /// 開催前でセトリが無い公演だけ: 過去のセトリから推定した「歌われそうな曲」。
        pub forecast: Option<ShowForecast>,
        /// 同一ライブ内の他公演 (前後移動用。自分自身も含む)。
        pub sibling_shows: Vec<Ref>,
        /// 同じライブの公演をどう行き来させるか (本数で決まる)。
        pub sibling_nav: SiblingNav,
        pub app: AppOpen,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// セトリの機械予測 (`domain::setlist_forecast`。アプリの予想と同じモデル)。
    pub struct ShowForecast {
        pub title: String,
        /// 何をどう並べたかの一言 (機械的な目安であること)。
        pub lede: String,
        pub songs: Vec<ForecastRow>,
        /// 精度についての注記 (出演者未発表など)。
        pub notes: Vec<String>,
    }
}

web_dto! {
    /// 予測の 1 曲。
    pub struct ForecastRow {
        pub rank: u32,
        pub song: Ref,
        /// セトリに入る推定確率 (0〜100 の整数)。
        pub percent: u32,
        /// 理由 (「前日に歌った」など)。表示の優先順。
        pub reasons: Vec<String>,
        /// オリメンは誰で、この公演に出るか (`オリメン 2/3: … · 欠席 …`)。ソロ曲などは無し。
        pub originals: Option<String>,
    }
}

web_dto! {
    /// 同じライブの公演の行き来の形。
    ///
    /// 数本ならヒーローの中の帯 (DAY1 / DAY2 と行き来するのが一番多い操作)。ツアーのように
    /// 多いと横に並べきれないので前後への送りにし、全部の並びは脇に置く。単日公演は無し。
    #[derive(Copy, Eq)]
    pub enum SiblingNav {
        /// 単日公演 (行き来する先が無い)。
        Hidden,
        Segments,
        Pager,
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
        /// 歌唱メンバー。演者名は**コアがその公演の演者で解決済み**。
        pub performers: Vec<PerformerRef>,
        /// 公演の出演者全員で歌う行なら `全員`。
        /// 判定 (出演者 2 人以上・歌唱者と完全一致) は `domain::setlist_lineup::row_lineup` が持つ。
        /// 名前を全部並べる代わりにこの札を出し、名前は畳んでおく。
        pub full_cast_label: Option<String>,
        /// 原唱者 (オリメン) との関係。判定できない行・当たり前の行 (ソロ曲を本人が歌う) ・
        /// 全員曲の部分一致には付かない。規則は `domain::setlist_lineup::lineup_note`。
        pub lineup: Option<LineupNote>,
        /// `songs.song_type == "cover"` (曲そのものがカバー曲)。
        pub is_cover: bool,
        /// この披露で着ていた衣装。記録が無ければ空。
        pub costumes: Vec<SetlistCostume>,
        /// この披露がその曲の初披露 (この DB に載っている範囲で最古) なら「初披露」。
        pub first_performance_label: Option<String>,
        /// 詳細表示で行に添える**披露の履歴** (`披露  4 回目  2 年 6 か月ぶり`)。
        /// カバーなどで通算が膨らんだ行には、オリメンにとっての回数 (`歌唱  オリメン 3 回目`) が続く。
        /// 上映会 (MV 上映会など、誰も歌わない公演) の行では空。
        ///
        /// 軸の分け方・文言・主従は `domain::screen_composition` (アプリの詳細表示と同じ 1 本)。
        /// 出面は参加記録を持たないので「回収」の軸は来ない。どのモードで見せるかは
        /// 閲覧者の切替で、HTML には常に描いておく。
        pub history: Vec<SetlistNoteGroup>,
    }
}

web_dto! {
    /// 行に添える事実の軸 1 本 (`披露` / `歌唱`)。
    #[derive(Eq)]
    pub struct SetlistNoteGroup {
        /// 行の左に固定幅で出す軸の名前。
        pub label: String,
        pub notes: Vec<SetlistNote>,
    }
}

web_dto! {
    /// 軸の中の事実 1 つ。強調は `tone` で出し分ける (文字列を見て決めない)。
    #[derive(Eq)]
    pub struct SetlistNote {
        pub text: String,
        pub tone: SetlistNoteTone,
    }
}

web_dto! {
    /// `domain::screen_composition::RowNoteTone` の写し。
    #[derive(Copy, Eq)]
    pub enum SetlistNoteTone {
        /// 軸の主な値 (`4 回目`)。
        Value,
        /// 主な値の補足 (`3 年ぶり`)。沈める。
        Detail,
        /// 初披露。
        Debut,
        /// 自分が回収した。出面には来ない (参加記録を持たない)。
        Mine,
        /// 自分がまだ持っていない。出面には来ない。
        Missing,
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
        /// その公演でアイドルを演じた人の名前 (公演日の CV。舞台なら俳優)。
        /// **アイドル名と違うときだけ入る** (演者不明なら `None`)。
        /// アイドル名は `reference.name`。決め方は `event_detail_queries::show_performer`。
        ///
        /// **どちらを出すかは受け手が決めない。** 表示の規則は
        /// `domain::event_detail_queries::performer_display_name` が持ち、
        /// 閲覧者が選んだモードに従って主/副を返す。ここは素材を両方渡すだけで、
        /// 「同じ名前を 2 つ持たせない」判断もその関数 (`Both` の副) に任せる。
        pub cast_name: Option<String>,
        /// `cast_name` が声優か俳優か。俳優 (`stage`) には「CV.」を添えない。
        pub cast_kind: CastKind,
    }
}

web_dto! {
    /// 演者の種別 (`domain::event_detail_queries::PerformerKind` の写し)。
    #[derive(Copy, Eq)]
    pub enum CastKind {
        /// 声優。
        Voice,
        /// 声優以外 (舞台の俳優など)。
        Stage,
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
    }
}

web_dto! {
    /// セトリ行に添えるチップ 1 個ぶんの衣装。
    #[derive(Eq)]
    pub struct SetlistCostume {
        pub id: String,
        /// チップに出す 1 行 (`衣装名` / `衣装名（着ていた人）`)。
        ///
        /// **名前と着用者を繋ぐのは Rust の仕事。** 出面で組み直すと、括弧の付け方が
        /// iOS / Android / Web で割れる (`domain::costume_queries` が唯一の規則)。
        pub label: String,
    }
}
