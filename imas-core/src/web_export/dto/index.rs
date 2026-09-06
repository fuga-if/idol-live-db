//! 一覧ページ / トップ / About / ルート台帳の DTO (`index/*.json`, `routes.json`)。
//!
//! 一覧の「切替」(ブランド別・年別・誕生月別・都道府県別) は、すべて **別ページ**として
//! 出す。クライアント状態を持たせないというユーザー指示の直接の帰結で、切替 UI は
//! [`super::common::NavLink`] のリンク集になる。

use super::common::{AppLinks, DateBadge, NavLink, Ref, SeoBlock, StatTile, TagBadge};
use super::event::ShowSummary;
use crate::domain::idol_list_filtering::IdolQuery;
use crate::domain::song_list_queries::SongQuery;

// ---------------------------------------------------------------------------
// ライブ一覧
// ---------------------------------------------------------------------------

web_dto! {
    /// ライブ一覧ページ。`/events/` `/events/upcoming/` `/events/past/`
    /// `/events/past/<year>/` `/events/brand/<brandId>/` が同じ型を使う。
    pub struct EventListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub kind: EventListKind,
        /// `event_grouping::group_events_by_year` の結果をそのまま写したもの。
        pub groups: Vec<YearGroup>,
        /// 入口 (`/events/`) だけ: 開催済みのいちばん新しい年の束と、その見出し
        /// (「開催済み (2026年)」)。`groups` (今後の予定) の下に置く。年の一覧では None。
        pub recent_past: Option<YearGroup>,
        pub recent_past_title: Option<String>,
        /// このページの続き (入口では「開催済みをすべて見る」、年の一覧では 1 つ前の年)。
        /// 一覧が途中で切れていることをページの末尾で言うための 1 本。
        pub next: Option<NavLink>,
        /// 今後 / 開催済み の切替。
        pub scope_links: Vec<NavLink>,
        pub brand_links: Vec<NavLink>,
        pub year_links: Vec<NavLink>,
        pub total: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// どの切り口の一覧か。
    #[derive(Copy, Eq)]
    pub enum EventListKind {
        /// `/events/` (入口)。
        Index,
        Upcoming,
        /// `/events/past/` (年の一覧)。
        Past,
        /// `/events/past/<year>/`。
        PastYear,
        Brand,
    }
}

web_dto! {
    /// 年ごとのまとまり。
    #[derive(Eq)]
    pub struct YearGroup {
        pub year: String,
        pub events: Vec<EventListItem>,
    }
}

web_dto! {
    /// ライブ一覧の 1 行。
    ///
    /// 日付・ブランド・会場・公演数を**別々の項目**で持つ。行はそれぞれを別の位置
    /// (日付ブロック / 色付きの札 / 文字 / 数) に置くので、1 本に繋いだ副題は持たない。
    /// 何を出す・何を落とすの判断はすべてここまでで済んでいて、受け手は置くだけ。
    #[derive(Eq)]
    pub struct EventListItem {
        #[serde(rename = "ref")]
        pub reference: Ref,
        /// 行の左端に置く日付ブロック (初日)。日付が無いライブでは `None`。
        pub date_badge: Option<DateBadge>,
        /// 期間の終端 (`〜 9/13 (日)`)。**1 日で終わるライブでは `None`**
        /// (初日と同じ日を 2 度出さない。判断は `date_display::range_end`)。
        pub end_display: Option<String>,
        /// 行に出すブランドの札。**ブランド別一覧では `None`** (全行同じ札を並べても
        /// 見分けに効かない)。
        pub brand_mark: Option<Ref>,
        /// 会場をまとめた 1 行 (多いときは畳む)。
        pub venue_display: Option<String>,
        /// 公演数 (`2 公演`)。**1 公演なら `None`** (数えるまでもないものに数を付けない)。
        pub show_count_display: Option<String>,
        /// 種別 (`live` / `festival` / …)。
        pub kind: String,
        /// 行に出す種別チップ。**既定の種別 (ライブ) には付かない** — ほぼ全行に同じ札が並んでも
        /// 見分けにならず、フェス・リリースイベントのような例外だけを言えばよい。
        /// 判断は `content::kind_chip` 1 箇所。
        pub kind_label: Option<String>,
    }
}

// ---------------------------------------------------------------------------
// 楽曲一覧
// ---------------------------------------------------------------------------

web_dto! {
    /// 楽曲一覧ページ。`/songs/` `/songs/brand/<brandId>/` `/songs/all/`。
    pub struct SongListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub kind: SongListKind,
        pub brand: Option<Ref>,
        pub items: Vec<SongListItem>,
        /// 行を `ref` だけまで削った一覧か (`/songs/all/`)。
        ///
        /// **行から何を落としたかを決めるのは Rust の 1 箇所**なので、受け手は
        /// 行を走査して列の有無を推測しない (走査すると「たまたま全行 null」と
        /// 「そもそも載せていない」が混ざり、同じ種類のページで表の形が変わる)。
        pub rows_are_light: bool,
        /// この一覧を組んだときの絞り込み条件。ブラウザの wasm が
        /// これを土台に条件を足して `song_list_indexes` を回す。
        ///
        /// 土台を Rust が出すのは、ページの中身と絞り込みの出発点を同じ 1 箇所で
        /// 決めるため。JS 側で「/songs/ なら既定フィルタ」と書き直すと二重定義になる。
        /// 行を `ref` だけに削った一覧 (`/songs/all/`) には無い。
        pub query_base: Option<SongQuery>,
        pub kana_sections: Vec<KanaSection>,
        pub brand_links: Vec<NavLink>,
        /// 既定フィルタから外れた曲も含む全件ハブ (`/songs/all/`) への案内。
        ///
        /// `/songs/` にだけ入る。これが無いと、一覧規則で外れた曲 (派生曲・ライブ限定曲・
        /// `other` ブランド) の詳細ページが `/` からどこからも辿れなくなる。
        pub all_songs_link: Option<NavLink>,
        /// タグから探す入口 (`/tags/`)。`/songs/` にだけ、タグの付いた曲が 1 曲でもあるときに入る
        /// (タグ一覧はそのときだけ作る)。
        pub tags_link: Option<NavLink>,
        pub total: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// 楽曲一覧の切り口。
    #[derive(Copy, Eq)]
    pub enum SongListKind {
        /// 既定フィルタを通した一覧 (`/songs/`)。
        Index,
        Brand,
        /// 既定フィルタから外れた曲も含む全件ハブ (`/songs/all/`)。
        /// 詳細ページを孤立させないためだけの 1 枚で、`noindex,follow` にする。
        All,
    }
}

web_dto! {
    /// 楽曲一覧の 1 行。
    #[derive(Eq)]
    pub struct SongListItem {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub release_date: Option<String>,
        pub unit_label: Option<String>,
        /// 原唱者を 1 行に畳んだもの (`join_capped` で「先頭 4 名 ほか N 名」に丸めた形)。
        ///
        /// `subtitle` にも畳み込まれているが、行の 2 行目はユニットと分けて出すので
        /// 独立して持つ。**丸め方を決めるのはここ (Rust) の 1 箇所**で、
        /// 受け手が名前の配列から組み立て直すことはしない。
        pub artists_label: Option<String>,
        /// 曲種別 (「ソロ曲」「ユニット曲」「全体曲」…)。語は `content::song_type_label`。
        pub song_type_label: Option<String>,
        /// 「作曲 <作曲者>」。語は `content::composer_credit`。行の 3 行目 (幅があるときだけ)。
        pub composer_credit: Option<String>,
        /// 「収録 <CD 名>」。語は `content::cd_credit`。同上。
        pub cd_credit: Option<String>,
        /// 披露回数。
        ///
        /// `/songs/all/` (全件ハブ) では **`None`**。あちらは 3,153 行を 1 枚に並べる
        /// 到達性のためのページなので、行に付ける情報を `ref` だけまで削ってある。
        /// `0` ではなく `None` にしてあるのは、「0 回披露」と「載せていない」を
        /// 取り違えないようにするため。
        pub performance_count: Option<u32>,
        /// 行の副題 (ユニット名・原唱者・リリース日)。空なら `None`。
        pub subtitle: Option<String>,
    }
}

web_dto! {
    /// タグ一覧ページ。`/tags/`。曲に付いたコミュニティのタグを、付いている曲の多い順に並べる。
    ///
    /// **読むだけ。** タグ付けはログインが要るのでアプリへ誘導する。集計は `db/community.sql`
    /// を焼き込んだもので、閲覧のたびに D1 は読まない。
    pub struct TagListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        /// 見出しの下の説明。
        pub lede: String,
        pub items: Vec<TagListItem>,
        pub total: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// タグ一覧の 1 行。
    #[derive(Eq)]
    pub struct TagListItem {
        pub badge: TagBadge,
        /// そのタグの曲一覧 (`/tags/<tagId>/`)。
        pub path: String,
        pub description: Option<String>,
        /// 運営が用意したタグに付く札 (`content::TAG_OFFICIAL_LABEL`)。
        pub official_label: Option<String>,
        /// 付いている曲の数。
        pub song_count: u32,
    }
}

web_dto! {
    /// タグ 1 つの曲一覧。`/tags/<tagId>/`。付けた人の多い順。
    pub struct TagPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub badge: TagBadge,
        /// タグ自身の説明 (付けた人が書いたもの)。無ければ `None`。
        pub description: Option<String>,
        /// 見出しの下の説明 (並び順の断り)。
        pub lede: String,
        pub items: Vec<TagSongRow>,
        pub total: u32,
        /// タグ一覧 (`/tags/`) へ戻る導線。
        pub all_tags_link: NavLink,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// タグの付いた曲 1 行。
    #[derive(Eq)]
    pub struct TagSongRow {
        #[serde(rename = "ref")]
        pub reference: Ref,
        /// 行の副題 (ユニット名・原唱者・リリース日)。楽曲一覧の行と同じ畳み方。
        pub subtitle: Option<String>,
        /// 何人が付けたか。
        pub votes: u32,
        /// 1 始まりの順位 (同数でも別の順位を振る = 表示の通し番号)。
        pub rank: u32,
    }
}

web_dto! {
    /// かな目次の 1 区画。
    #[derive(Eq)]
    pub struct KanaSection {
        /// 「あ」「か」…「英数」「その他」。
        pub label: String,
        /// `items` の何番目から始まるか。
        pub start_index: u32,
        pub count: u32,
    }
}

// ---------------------------------------------------------------------------
// アイドル / ユニット / 会場 / ブランド 一覧
// ---------------------------------------------------------------------------

web_dto! {
    /// アイドル一覧ページ。`/idols/` `/idols/brand/<brandId>/` `/idols/birth-month/<m>/`。
    pub struct IdolListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub kind: IdolListKind,
        pub brand: Option<Ref>,
        /// 誕生月別のときだけ入る (1–12)。
        pub birth_month: Option<u32>,
        pub items: Vec<IdolListItem>,
        pub brand_links: Vec<NavLink>,
        pub birth_month_links: Vec<NavLink>,
        pub total: u32,
        /// この一覧を組んだときの条件。ブラウザの wasm がこれを土台に
        /// 条件を足して `filter_idol_list` / `sort_idol_list` を回す
        /// (曲一覧の `SongListPage.query_base` と同じ仕掛け)。
        pub query_base: IdolQuery,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// お題の一覧 (`/polls/`)。
    ///
    /// **読むだけ。** 投票はログインが要るのでアプリへ誘導する。
    /// 中身は D1 の集計を焼き込んだもので、閲覧時に D1 は読まない。
    pub struct PollListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub polls: Vec<PollSummaryDto>,
        pub total: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// お題 1 件と、その時点の得票。
    pub struct PollSummaryDto {
        pub id: String,
        pub title: String,
        pub description: Option<String>,
        /// 何を選ぶお題か (「曲」「アイドル」)。語は Rust が決める。
        pub target_label: String,
        /// 締切 (`YYYY-MM-DD`)。無期限なら None。
        pub ends_on: Option<String>,
        /// 締切前か。**判定は Rust** (TS に `new Date()` を書かせない)。
        pub is_open: bool,
        pub total_votes: u32,
        /// 上位の得票。同数は entity id 順で安定させる。
        pub entries: Vec<PollEntryDto>,
    }
}

web_dto! {
    /// お題の得票 1 行。
    pub struct PollEntryDto {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub votes: u32,
        /// 1 始まりの順位 (同数でも別の順位を振る = 表示の通し番号)。
        pub rank: u32,
    }
}

web_dto! {
    /// アイドル一覧の切り口。
    #[derive(Copy, Eq)]
    pub enum IdolListKind {
        Index,
        Brand,
        BirthMonth,
    }
}

web_dto! {
    /// アイドル一覧の 1 行。
    #[derive(Eq)]
    pub struct IdolListItem {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub brand: Option<Ref>,
        pub current_voice_actor: Option<String>,
        pub birthday_display: Option<String>,
    }
}

web_dto! {
    /// ユニット一覧ページ。`/units/` `/units/brand/<brandId>/`。
    pub struct UnitListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub brand: Option<Ref>,
        pub items: Vec<UnitListItem>,
        /// 楽曲一覧と同じ、よみの目次。`items` はよみ順に並んでいる。
        pub kana_sections: Vec<KanaSection>,
        pub brand_links: Vec<NavLink>,
        pub total: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// ユニット一覧の 1 行。
    #[derive(Eq)]
    pub struct UnitListItem {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub brand: Option<Ref>,
        /// 例外にだけ付く札 (「公演限定」)。常設が 9 割なので、常設に札を付けても見分けにならない。
        pub note: Option<String>,
        pub member_count: u32,
        pub song_count: u32,
    }
}

web_dto! {
    /// 会場一覧ページ。`/venues/` `/venues/pref/<prefecture>/`。
    pub struct VenueListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        /// 都道府県別のときだけ入る。空欄の会場は `未分類` に集める。
        pub prefecture: Option<String>,
        pub items: Vec<VenueListItem>,
        pub prefecture_links: Vec<NavLink>,
        pub total: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// 会場一覧の 1 行。
    #[derive(Eq)]
    pub struct VenueListItem {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub prefecture: Option<String>,
        pub city: Option<String>,
        /// 「千葉県 千葉市美浜区」。
        pub location_display: Option<String>,
        pub capacity: Option<i32>,
        pub show_count: u32,
    }
}

web_dto! {
    /// ブランド一覧ページ (`/brands/`)。
    pub struct BrandListPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub items: Vec<BrandListItem>,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// ブランド一覧の 1 行。
    #[derive(Eq)]
    pub struct BrandListItem {
        #[serde(rename = "ref")]
        pub reference: Ref,
        pub short_name: Option<String>,
        /// ブランドカードに大きく出す短い名前 (`765AS` / `デレマス` / `SideM`)。
        ///
        /// **切らずに丸ごと出す。** `765AS` を 2 文字に切ると `76`、`学マス` は
        /// `学マ` になり、どれも読めない。実データの短縮名は最長 5 文字なので
        /// そのまま置ける。切る/切らないの判断を TS に持たせないための項目。
        pub glyph: String,
        /// カードの 1 行紹介 (`ライブ 210 ・ 楽曲 600 ・ アイドル 52 ・ ユニット 300`)。
        ///
        /// 素の `Counts` を配ると .astro が組み立て直すことになり、実際にトップと
        /// `/brands/` で項目数が食い違っていた (片方だけユニット数が無かった)。
        pub preview_display: String,
    }
}

// ---------------------------------------------------------------------------
// トップ / About
// ---------------------------------------------------------------------------

web_dto! {
    /// トップページ (`/`)。
    pub struct HomePage {
        pub schema_version: u32,
        pub path: String,
        /// ヒーローの 1 行説明。
        pub tagline: String,
        /// 今後のライブ (直近 8 件)。
        pub upcoming: Vec<EventListItem>,
        /// 最近の公演 (直近 8 件)。
        pub recent_shows: Vec<ShowSummary>,
        /// 件数タイル (ライブ / 公演 / 楽曲 / アイドル / ユニット / 会場)。各一覧への入口を持つ。
        pub stat_tiles: Vec<StatTile>,
        pub brands: Vec<BrandListItem>,
        pub app: AppLinks,
        /// 「アプリで、もっと」の説明文。アプリにしか無い機能の並びは `content` が 1 箇所で持つ
        /// (歌詞を出面で出す/出さないで変わる)。
        pub app_note: String,
        /// 「最近の公演」の続き先。公演だけの一覧は無いので、開催済みのライブへ送る。
        pub recent_shows_more: NavLink,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// About ページ (`/about/`)。
    pub struct AboutPage {
        pub schema_version: u32,
        pub path: String,
        /// 件数タイル (トップの 6 種 + セトリ項目)。押せるリンクは持たない。
        pub stat_tiles: Vec<StatTile>,
        pub data_version: Option<String>,
        pub content_hash: Option<String>,
        pub generated_at: String,
        pub today_jst: String,
        pub app: AppLinks,
        /// 版権・ライセンス・歌詞などの固定文。見出しと本文の対で持つ。
        pub sections: Vec<AboutSection>,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// About の 1 節。
    #[derive(Eq)]
    pub struct AboutSection {
        pub heading: String,
        /// 段落の列 (1 段落 1 要素)。
        pub paragraphs: Vec<String>,
        pub links: Vec<AboutLink>,
    }
}

web_dto! {
    /// About から外に出るリンク。
    #[derive(Eq)]
    pub struct AboutLink {
        pub label: String,
        pub href: String,
        /// 外部サイトか (`rel="noopener"` と外部アイコンの材料)。
        pub external: bool,
    }
}

// ---------------------------------------------------------------------------
// ルート台帳
// ---------------------------------------------------------------------------

web_dto! {
    /// 全ルートの台帳 (`routes.json`)。sitemap の生成と、到達性テストに使う。
    pub struct RoutesFile {
        pub schema_version: u32,
        pub routes: Vec<RouteEntry>,
        /// `robots` が `noindex,*` のページの完成形 path。
        ///
        /// [`RouteEntry::in_sitemap`] と同じ判断の裏返しだが、こちらは
        /// `astro.config.mjs` の `@astrojs/sitemap` の `filter(url)` から
        /// **ページ JSON を 1 本も開かずに**引けるように、平たい配列で持たせてある。
        /// 判断そのものは Rust 側 ([`super::common::Robots`]) にあり、Astro は写すだけ。
        pub noindex_paths: Vec<String>,
    }
}

web_dto! {
    /// ルート 1 本。
    ///
    /// ## Astro 側での使い分け (ここを取り違えると 404 になる)
    ///
    /// | フィールド | 使い道 |
    /// |---|---|
    /// | [`Self::path`] | `href` にそのまま入れる完成形 URL (percent-encode 済み・末尾スラッシュ付き) |
    /// | [`Self::key`] | `getStaticPaths` の `params` に渡す値 (**Astro が encode する前**の生の値) |
    /// | [`Self::id`] | DB 上の id (詳細ページのみ)。アプリ連携・deeplink 用。**URL の材料にしない** |
    ///
    /// `key` と `id` は通常は同じ文字列だが、危険な文字を含む id では `key` だけが
    /// フォールバック slug に落ちる。`params` に `id` を渡すと、その 2 件だけ
    /// 出力されないページを指すことになる。
    #[derive(Eq)]
    pub struct RouteEntry {
        /// 末尾スラッシュ付きの完成形 URL。
        pub path: String,
        pub kind: RouteKind,
        /// `getStaticPaths` の params に渡す値。
        ///
        /// 詳細ページでは安全化済みのセグメント (= `url::path_key` の出力)、
        /// パラメータを取る一覧ページでは param の生値 (年 `"2016"` / ブランド id `"ml"` /
        /// 月 `"4"` / 都道府県 `"東京都"`)。params を取らないルートは `None`。
        pub key: Option<String>,
        /// DB 上の id (詳細ページのみ)。アプリ連携・deeplink 用で、**URL の材料にしない**。
        /// 一覧ページでは `None`。
        pub id: Option<String>,
        /// このページを描くのに読む JSON の、`web/data/` からの相対パス。
        pub data: String,
        /// sitemap に載せるか (`noindex` は載せない)。
        pub in_sitemap: bool,
    }
}

web_dto! {
    /// ルートの種別。
    ///
    /// **粒度は「Astro のルートファイル 1 本」に揃えてある。** `/events/past/[year]/` と
    /// `/events/brand/[brandId]/` を同じ `eventList` にまとめてしまうと、`getStaticPaths` が
    /// params の集合を取り出すのに `path` を文字列で刻むことになり、URL の組み立て規則が
    /// TypeScript 側に生えてしまう。1 種別 = 1 ルートファイルにしておけば
    ///
    /// ```ts
    /// routes().routes
    ///   .filter(r => r.kind === "eventListPastYear")
    ///   .map(r => ({ params: { year: r.key! }, props: { data: r.data } }))
    /// ```
    ///
    /// で済み、TS 側には規則が 1 つも残らない。
    #[derive(Copy, Eq)]
    pub enum RouteKind {
        /// `/`
        Home,
        /// `/about/`
        About,
        /// `/search/`
        Search,

        /// `/events/`
        EventListIndex,
        /// `/events/upcoming/`
        EventListUpcoming,
        /// `/events/past/`
        EventListPast,
        /// `/events/past/[year]/` — `key` = 年 (`"2016"`)
        EventListPastYear,
        /// `/events/brand/[brandId]/` — `key` = ブランド id
        EventListBrand,

        /// `/songs/`
        SongListIndex,
        /// `/songs/brand/[brandId]/` — `key` = ブランド id
        SongListBrand,
        /// `/songs/all/`
        SongListAll,
        /// `/tags/` — 曲に付いたタグの一覧
        TagListIndex,
        /// `/tags/[tagId]/` — `key` = タグ id
        Tag,
        /// `/calendar/` — 今月のカレンダー (正規 URL は月のページ)
        CalendarIndex,
        /// `/calendar/[month]/` — `key` = `YYYY-MM`
        CalendarMonth,

        /// `/idols/`
        IdolListIndex,
        /// `/idols/brand/[brandId]/` — `key` = ブランド id
        IdolListBrand,
        /// `/idols/birth-month/[month]/` — `key` = 月 (`"4"`)
        IdolListBirthMonth,

        /// `/units/`
        UnitListIndex,
        /// `/units/brand/[brandId]/` — `key` = ブランド id
        UnitListBrand,

        /// `/venues/`
        VenueListIndex,
        /// `/venues/pref/[prefecture]/` — `key` = 都道府県名 (空欄の会場は `未分類`)
        VenueListPref,

        /// `/brands/`
        BrandList,
        /// `/polls/`
        PollList,
        /// `/calls/` — コールガイドの進捗
        CallGuide,

        /// `/events/[id]/`
        Event,
        /// `/shows/[id]/`
        Show,
        /// `/songs/[id]/`
        Song,
        /// `/idols/[id]/`
        Idol,
        /// `/units/[id]/`
        Unit,
        /// `/venues/[id]/`
        Venue,
        /// `/brands/[id]/`
        Brand,
    }
}
