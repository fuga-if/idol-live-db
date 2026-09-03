//! 一覧ページ / トップ / About / ルート台帳の DTO (`index/*.json`, `routes.json`)。
//!
//! 一覧の「切替」(ブランド別・年別・誕生月別・都道府県別) は、すべて **別ページ**として
//! 出す。クライアント状態を持たせないというユーザー指示の直接の帰結で、切替 UI は
//! [`super::common::NavLink`] のリンク集になる。

use super::common::{AppLinks, Counts, NavLink, Ref, SeoBlock};
use super::event::ShowSummary;
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// ライブ一覧
// ---------------------------------------------------------------------------

/// ライブ一覧ページ。`/events/` `/events/upcoming/` `/events/past/`
/// `/events/past/<year>/` `/events/brand/<brandId>/` が同じ型を使う。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct EventListPage {
    pub schema_version: u32,
    pub path: String,
    pub title: String,
    pub kind: EventListKind,
    /// `event_grouping::group_events_by_year` の結果をそのまま写したもの。
    pub groups: Vec<YearGroup>,
    /// 今後 / 開催済み の切替。
    pub scope_links: Vec<NavLink>,
    pub brand_links: Vec<NavLink>,
    pub year_links: Vec<NavLink>,
    pub total: u32,
    pub seo: SeoBlock,
}

/// どの切り口の一覧か。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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

/// 年ごとのまとまり。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct YearGroup {
    pub year: String,
    pub events: Vec<EventListItem>,
}

/// ライブ一覧の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct EventListItem {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub first_date: Option<String>,
    pub last_date: Option<String>,
    pub short_date: Option<String>,
    pub brand: Option<Ref>,
    /// 種別チップ (`live` / `festival` / …)。一覧を全種別で出すので、行で見分けが要る。
    pub kind: String,
    pub kind_label: String,
    pub show_count: u32,
    pub venue_labels: Vec<String>,
}

// ---------------------------------------------------------------------------
// 楽曲一覧
// ---------------------------------------------------------------------------

/// 楽曲一覧ページ。`/songs/` `/songs/brand/<brandId>/` `/songs/all/`。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SongListPage {
    pub schema_version: u32,
    pub path: String,
    pub title: String,
    pub kind: SongListKind,
    pub brand: Option<Ref>,
    pub items: Vec<SongListItem>,
    /// よみの先頭 1 文字で切った目次。
    pub kana_sections: Vec<KanaSection>,
    pub brand_links: Vec<NavLink>,
    pub total: u32,
    pub seo: SeoBlock,
}

/// 楽曲一覧の切り口。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub enum SongListKind {
    /// 既定フィルタを通した一覧 (`/songs/`)。
    Index,
    Brand,
    /// 既定フィルタから外れた曲も含む全件ハブ (`/songs/all/`)。
    /// 詳細ページを孤立させないためだけの 1 枚で、`noindex,follow` にする。
    All,
}

/// 楽曲一覧の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SongListItem {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub release_date: Option<String>,
    pub unit_label: Option<String>,
    pub original_artists: Vec<Ref>,
    pub performance_count: u32,
}

/// かな目次の 1 区画。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct KanaSection {
    /// 「あ」「か」…「英数」「その他」。
    pub label: String,
    /// `items` の何番目から始まるか。
    pub start_index: u32,
    pub count: u32,
}

// ---------------------------------------------------------------------------
// アイドル / ユニット / 会場 / ブランド 一覧
// ---------------------------------------------------------------------------

/// アイドル一覧ページ。`/idols/` `/idols/brand/<brandId>/` `/idols/birth-month/<m>/`。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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
    pub seo: SeoBlock,
}

/// アイドル一覧の切り口。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub enum IdolListKind {
    Index,
    Brand,
    BirthMonth,
}

/// アイドル一覧の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct IdolListItem {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub brand: Option<Ref>,
    pub current_voice_actor: Option<String>,
    pub birthday_display: Option<String>,
}

/// ユニット一覧ページ。`/units/` `/units/brand/<brandId>/`。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct UnitListPage {
    pub schema_version: u32,
    pub path: String,
    pub title: String,
    pub brand: Option<Ref>,
    pub items: Vec<UnitListItem>,
    pub brand_links: Vec<NavLink>,
    pub total: u32,
    pub seo: SeoBlock,
}

/// ユニット一覧の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct UnitListItem {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub brand: Option<Ref>,
    pub is_permanent: bool,
    pub member_count: u32,
    pub song_count: u32,
}

/// 会場一覧ページ。`/venues/` `/venues/pref/<prefecture>/`。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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

/// 会場一覧の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct VenueListItem {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub prefecture: Option<String>,
    pub city: Option<String>,
    pub capacity: Option<i32>,
    pub show_count: u32,
}

/// ブランド一覧ページ (`/brands/`)。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct BrandListPage {
    pub schema_version: u32,
    pub path: String,
    pub title: String,
    pub items: Vec<BrandListItem>,
    pub seo: SeoBlock,
}

/// ブランド一覧の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct BrandListItem {
    #[serde(rename = "ref")]
    pub reference: Ref,
    pub short_name: Option<String>,
    pub counts: Counts,
}

// ---------------------------------------------------------------------------
// トップ / About
// ---------------------------------------------------------------------------

/// トップページ (`/`)。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct HomePage {
    pub schema_version: u32,
    pub path: String,
    /// ヒーローの 1 行説明。
    pub tagline: String,
    /// 「非公式ファンメイド」の断り書き。
    pub disclaimer: String,
    /// 今後のライブ (直近 8 件)。
    pub upcoming: Vec<EventListItem>,
    /// 最近の公演 (直近 8 件)。
    pub recent_shows: Vec<ShowSummary>,
    pub counts: Counts,
    pub brands: Vec<BrandListItem>,
    pub app: AppLinks,
    /// 「今後のライブ」「開催済み」等への入口。
    pub section_links: Vec<NavLink>,
    pub seo: SeoBlock,
}

/// About ページ (`/about/`)。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct AboutPage {
    pub schema_version: u32,
    pub path: String,
    pub counts: Counts,
    pub data_version: Option<String>,
    pub content_hash: Option<String>,
    pub generated_at: String,
    pub today_jst: String,
    pub app: AppLinks,
    /// 版権・ライセンス・歌詞などの固定文。見出しと本文の対で持つ。
    pub sections: Vec<AboutSection>,
    pub seo: SeoBlock,
}

/// About の 1 節。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct AboutSection {
    pub heading: String,
    /// 段落の列 (1 段落 1 要素)。
    pub paragraphs: Vec<String>,
    pub links: Vec<AboutLink>,
}

/// About から外に出るリンク。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct AboutLink {
    pub label: String,
    pub href: String,
    /// 外部サイトか (`rel="noopener"` と外部アイコンの材料)。
    pub external: bool,
}

// ---------------------------------------------------------------------------
// ルート台帳
// ---------------------------------------------------------------------------

/// 全ルートの台帳 (`routes.json`)。sitemap の生成と、到達性テストに使う。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
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
