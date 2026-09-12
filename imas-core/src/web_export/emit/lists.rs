//! 一覧ページ・トップ・About。
//!
//! 切替 (ブランド別・年別・誕生月別・都道府県別) は**すべて別ページ**として出す。
//! クライアント状態を持たないというユーザー指示の直接の帰結で、切替 UI は
//! [`NavLink`] のリンク集になる。

use super::context::{join_parts, simple_json_ld, tag_badge, Ctx, PARTS_SEPARATOR, TAGS_PATH};
use crate::domain::date_display::until_display;
use crate::domain::display_join::join_capped;
use crate::domain::kana_row::{kana_row_label, kana_sort_key};
use super::places::{location_display, UNCLASSIFIED_PREFECTURE};
use crate::domain::event_grouping::{group_events_by_year, year_key};
use crate::domain::event_list_queries::{self, EventWithDateRecord};
use crate::domain::idol_queries;
use crate::domain::song_list_queries::{song_list_indexes, SongListFilter, SongListSort};
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url::url_segment;
use std::collections::{BTreeMap, HashSet};
use crate::domain::idol_list_filtering::{IdolQuery, IdolSortKind};
use crate::domain::song_list_queries::SongQuery;

/// 一覧に出すライブの種別。
///
/// **省略しない。** 省略すると `event_list_queries` の既定が効いて、ラジオや配信が
/// 一覧から静かに消える (= そのページが `/` から到達できなくなる)。
pub fn all_event_kinds() -> Vec<String> {
    content::ALL_EVENT_KINDS.iter().map(|k| k.to_string()).collect()
}

/// 1 枚ぶんの出力 (どこに置き、どの URL になり、どのルートに対応するか)。
///
/// `route_kind` と `param_key` を作る側が持つのは、**URL を作った側が答えを知っている**から。
/// 以前は書き出す側が `path` を文字列で刻んで種別と params を逆算していて、
/// URL 規約が「組み立てる場所」と「読み解く場所」の 2 箇所にあった。
pub struct Emitted<T> {
    pub path: String,
    pub data: String,
    /// Astro のルートファイル 1 本に対応する種別。
    pub route_kind: RouteKind,
    /// `getStaticPaths` の params に渡す生値 (params を取らないページは `None`)。
    pub param_key: Option<String>,
    pub page: T,
}

// ---------------------------------------------------------------------------
// ライブ一覧
// ---------------------------------------------------------------------------

/// 年グループと、その URL の段 (`"2019"`。日程未定は `"undated"`)。
struct YearBucket {
    key: String,
    group: YearGroup,
}

/// 年グループを組む。**分割規則は `group_events_by_year` が持つ**ので、
/// ここは結果の添字で元の配列を引き直すだけ。鍵はラベルを逆解析せず、同じ日付から
/// `year_key` で出す (ラベルの綴りが変わっても URL は変わらない)。
fn year_groups(
    ctx: &Ctx,
    records: &[EventWithDateRecord],
    upcoming: bool,
    with_brand: bool,
) -> Vec<YearBucket> {
    let dates: Vec<Option<String>> = records.iter().map(|r| r.first_date.clone()).collect();
    group_events_by_year(&dates, upcoming, &ctx.today)
        .into_iter()
        .map(|g| YearBucket {
            key: g
                .indices
                .first()
                .and_then(|&i| year_key(dates[i as usize].as_deref()))
                .unwrap_or_else(|| "undated".to_string()),
            group: YearGroup {
                year: g.year,
                events: g
                    .indices
                    .iter()
                    .filter_map(|&i| event_list_item(ctx, &records[i as usize], with_brand))
                    .collect(),
            },
        })
        .collect()
}

/// 会場をまとめた 1 行。多いときは畳む (ツアーは 20 会場を超える)。
fn venue_display(labels: &[String]) -> Option<String> {
    let labels: Vec<&str> = labels.iter().map(String::as_str).collect();
    join_capped(&labels, PARTS_SEPARATOR, 3, "会場")
}

/// 一覧の 1 行。
///
/// `with_brand` はブランドの札を出すか。**ブランド別ページでは出さない**
/// (そのページの全行が同じブランドなので、行ごとに繰り返しても見分けに効かない)。
/// 一覧 JSON はページ単位で吐かれるので、どちらの文脈かは作る側が知っている。
fn event_list_item(
    ctx: &Ctx,
    record: &EventWithDateRecord,
    with_brand: bool,
) -> Option<EventListItem> {
    let e = &record.event;
    let show_count = ctx
        .snap
        .event_index_by_id
        .get(&e.id)
        .map(|&i| ctx.snap.shows_by_event[i as usize].len() as u32)
        .unwrap_or(0);
    let mut venue_labels: Vec<String> = ctx
        .snap
        .event_index_by_id
        .get(&e.id)
        .map(|&i| {
            ctx.snap.shows_by_event[i as usize]
                .iter()
                .filter_map(|&s| ctx.snap.shows[s as usize].venue.clone())
                .collect()
        })
        .unwrap_or_default();
    venue_labels.dedup();
    let first = record.first_date.as_deref();
    let last = record.last_date.as_deref();
    Some(EventListItem {
        reference: ctx.event_ref(&e.id)?,
        date_badge: first.map(DateBadge::from_ymd),
        end_display: until_display(first, last),
        brand_mark: if with_brand { e.brand_id.as_deref().and_then(|b| ctx.brand_ref(b)) } else { None },
        venue_display: venue_display(&venue_labels),
        show_count_display: (show_count > 1).then(|| format!("{show_count} 公演")),
        kind_label: content::kind_chip(&e.kind).map(str::to_string),
        kind: e.kind.clone(),
    })
}

/// 一覧ページのパンくず。入口 (`/songs/` など) は [ホーム, 自分]、絞った一覧
/// (`/songs/brand/ml/` など) は [ホーム, 入口, 自分] — 上部バーの現在地も、この入口が
/// パンくずに居るかで決まる。
pub fn list_crumbs(root: SiteList, title: &str, path: &str) -> Vec<Crumb> {
    let mut crumbs = vec![Ctx::crumb("ホーム", "/")];
    if path != root.path() {
        crumbs.push(Ctx::crumb(root.label(), root.path()));
    }
    crumbs.push(Ctx::crumb(title, path));
    crumbs
}

/// ブランド切替のリンク。**作っていない一覧は並べない** (判断は `Ctx::brand_list_path`)。
fn brand_links(ctx: &Ctx, collection: &str, current: &str, all_label: &str, all_count: u32) -> Vec<NavLink> {
    let mut links = vec![NavLink::new(all_label, format!("/{collection}/")).with_count(all_count)];
    links.extend(ctx.snap.brand_order.iter().filter_map(|&i| {
        let brand = &ctx.snap.brands[i as usize];
        Some(
            NavLink::new(&brand.short_name, ctx.brand_list_path(collection, &brand.id)?)
                .with_theme(ctx.brand_theme(Some(&brand.id))),
        )
    }));
    mark_current(&mut links, current);
    links
}

fn scope_links(current: &str, upcoming: u32, past: u32) -> Vec<NavLink> {
    let mut links = vec![
        NavLink::new("今後のライブ", "/events/upcoming/").with_count(upcoming),
        NavLink::new("開催済み", "/events/past/").with_count(past),
        // 月の枠で見る (中身は同じ公演)。
        NavLink::new(SiteList::Calendar.label(), SiteList::Calendar.path()),
    ];
    mark_current(&mut links, current);
    links
}

fn past_year_path(key: &str) -> String {
    format!("/events/past/{key}/")
}

/// ライブ一覧 1 枚ぶんの指定。`make` に渡す (位置引数 9 個を並べない)。
struct EventListSpec<'a> {
    path: &'a str,
    title: &'a str,
    kind: EventListKind,
    route: (RouteKind, Option<String>),
    groups: Vec<YearGroup>,
    /// 入口だけ: 開催済みの最新の年と、その見出し。
    recent_past: Option<(String, YearGroup)>,
    /// このページの続き (次に読むもの)。
    next: Option<NavLink>,
    total: u32,
    data: String,
    description: &'a str,
}

/// ライブ一覧をすべて組む (`/events/` から `/events/brand/<b>/` まで)。
///
/// - `/events/` は入口: 今後の予定を全部と、開催済みのいちばん新しい年 (`recent_past`) を載せ、
///   末尾に「開催済みをすべて見る」(`next`) を置く。今後だけの一覧 (`/events/upcoming/`) の
///   写しにしない (同じものが 2 枚あると、件数の食い違いだけが目立つ)。
/// - `/events/past/` と各年のページは 1 年ぶんを載せ、`next` で 1 つ前の年へ送る。
pub fn event_lists(ctx: &Ctx) -> Vec<Emitted<EventListPage>> {
    let kinds = all_event_kinds();
    // include_empty=true にするのは、公演がまだ無いライブ (発表直後) のページも
    // `/` から辿れるようにするため。落とすとそのページが孤立する。
    let all = event_list_queries::events_with_first_date(ctx.snap, None, true, false, Some(&kinds));

    let upcoming: Vec<YearGroup> = year_groups(ctx, &all, true, true).into_iter().map(|b| b.group).collect();
    let past = year_groups(ctx, &all, false, true);
    let upcoming_total: u32 = upcoming.iter().map(|g| g.events.len() as u32).sum();
    let past_total: u32 = past.iter().map(|b| b.group.events.len() as u32).sum();

    let year_links: Vec<NavLink> = past
        .iter()
        .map(|b| NavLink::new(&b.group.year, past_year_path(&b.key)).with_count(b.group.events.len() as u32))
        .collect();
    // 1 つ前の年 (開催済みは新しい順なので、次の要素) への送り。
    let older_year = |i: usize| -> Option<NavLink> {
        let b = past.get(i + 1)?;
        Some(
            NavLink::new(&format!("{}のライブ", b.group.year), past_year_path(&b.key))
                .with_count(b.group.events.len() as u32),
        )
    };

    let make = |spec: EventListSpec| {
        let mut year_links = year_links.clone();
        mark_current(&mut year_links, spec.path);
        // パンくずの親は種別で決まる (入口 → 無し / 年 → ライブ・開催済み / それ以外 → ライブ)。
        let parents: Vec<Crumb> = match spec.kind {
            EventListKind::Index => vec![],
            EventListKind::PastYear => vec![
                Ctx::crumb("ライブ", "/events/"),
                Ctx::crumb("開催済みのライブ", "/events/past/"),
            ],
            _ => vec![Ctx::crumb("ライブ", "/events/")],
        };
        let breadcrumbs: Vec<Crumb> = std::iter::once(Ctx::crumb("ホーム", "/"))
            .chain(parents)
            .chain(std::iter::once(Ctx::crumb(spec.title, spec.path)))
            .collect();
        let (recent_past_title, recent_past) = spec.recent_past.map(|(t, g)| (Some(t), Some(g))).unwrap_or((None, None));
        Emitted {
            path: spec.path.to_string(),
            data: spec.data,
            route_kind: spec.route.0,
            param_key: spec.route.1,
            page: EventListPage {
                schema_version: SCHEMA_VERSION,
                path: spec.path.to_string(),
                title: spec.title.to_string(),
                kind: spec.kind,
                groups: spec.groups,
                recent_past,
                recent_past_title,
                next: spec.next,
                scope: FilterAxis::new(content::FILTER_SCOPE_EVENTS, scope_links(spec.path, upcoming_total, past_total)),
                // 年の軸は開催済みの側だけ (今後の一覧に過去の年を並べても行き先が違う)。
                filters: filter_axes([
                    FilterAxis::new(
                        content::FILTER_AXIS_YEAR,
                        if matches!(spec.kind, EventListKind::Past | EventListKind::PastYear) { year_links } else { vec![] },
                    ),
                    FilterAxis::new(
                        content::FILTER_AXIS_BRAND,
                        brand_links(ctx, "events", spec.path, "すべて", upcoming_total + past_total),
                    ),
                ]),
                total: spec.total,
                seo: ctx.seo(
                    spec.title,
                    spec.description,
                    spec.path,
                    None,
                    collection_json_ld(spec.title, spec.path),
                    breadcrumbs,
                ),
            },
        }
    };

    let mut out = vec![
        make(EventListSpec {
            path: "/events/",
            title: "ライブ",
            kind: EventListKind::Index,
            route: (RouteKind::EventListIndex, None),
            groups: upcoming.clone(),
            recent_past: past.first().map(|b| (format!("開催済み ({})", b.group.year), b.group.clone())),
            next: Some(NavLink::new("開催済みのライブをすべて見る", "/events/past/").with_count(past_total)),
            total: upcoming_total + past_total,
            data: "index/events.json".to_string(),
            description: "アイドルマスターのライブ・イベントの一覧。今後の開催予定と開催済みを年別に。",
        }),
        make(EventListSpec {
            path: "/events/upcoming/",
            title: "今後のライブ",
            kind: EventListKind::Upcoming,
            route: (RouteKind::EventListUpcoming, None),
            groups: upcoming,
            recent_past: None,
            next: None,
            total: upcoming_total,
            data: "index/events-upcoming.json".to_string(),
            description: "これから開催されるアイドルマスターのライブ・イベント。",
        }),
    ];

    // `/events/past/` は年の入口。中身は最新の年だけ載せ (全部載せると 1 枚が重い)、
    // 末尾で 1 つ前の年へ送る。
    out.push(make(EventListSpec {
        path: "/events/past/",
        title: "開催済みのライブ",
        kind: EventListKind::Past,
        route: (RouteKind::EventListPast, None),
        groups: past.first().map(|b| b.group.clone()).into_iter().collect(),
        recent_past: None,
        next: older_year(0),
        total: past_total,
        data: "index/events-past.json".to_string(),
        description: "開催済みのアイドルマスターのライブ・イベントを年別に。",
    }));

    for (i, b) in past.iter().enumerate() {
        let path = past_year_path(&b.key);
        out.push(make(EventListSpec {
            path: &path,
            title: &format!("{}のライブ", b.group.year),
            kind: EventListKind::PastYear,
            route: (RouteKind::EventListPastYear, Some(b.key.clone())),
            groups: vec![b.group.clone()],
            recent_past: None,
            next: older_year(i),
            total: b.group.events.len() as u32,
            data: format!("index/events-past-{}.json", b.key),
            description: &format!("{}に開催されたアイドルマスターのライブ・イベント。", b.group.year),
        }));
    }

    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        let Some(path) = ctx.brand_list_path("events", &brand.id) else { continue };
        let records =
            event_list_queries::events_with_first_date(ctx.snap, Some(&brand.id), true, false, Some(&kinds));
        // ブランド別ページなので、行の副題にブランド名は入れない。
        let groups: Vec<YearGroup> = year_groups(ctx, &records, true, false)
            .into_iter()
            .chain(year_groups(ctx, &records, false, false))
            .map(|b| b.group)
            .collect();
        let total = groups.iter().map(|g| g.events.len() as u32).sum();
        out.push(make(EventListSpec {
            path: &path,
            title: &format!("{}のライブ", brand.name),
            kind: EventListKind::Brand,
            route: (RouteKind::EventListBrand, Some(brand.id.clone())),
            groups,
            recent_past: None,
            next: None,
            total,
            data: format!("index/events-brand-{}.json", Ctx::param_key(&brand.id)),
            description: &format!("{}のライブ・イベントの一覧。", brand.name),
        }));
    }
    out
}

// ---------------------------------------------------------------------------
// 楽曲一覧
// ---------------------------------------------------------------------------

/// 一覧の既定フィルタ。**この 3 つの false/true がコアの「何を隠すか」の判断**で、
/// Web はそれをそのまま使う (派生曲・他ブランド・ライブ限定曲を一覧に出さない)。
fn default_song_filter(brand_ids: Vec<String>) -> SongListFilter {
    SongListFilter {
        brand_ids,
        include_remixes: false,
        include_other_brand: false,
        exclude_live_only: true,
        ..SongListFilter::default()
    }
}

/// 原唱者名を 1 行に畳む。全体曲は 60 人を超えるので、多いときは人数で丸める。
fn artists_display(names: &[&str]) -> Option<String> {
    join_capped(names, " / ", 4, "名")
}

/// 一覧の 1 行。
///
/// `light` は「`ref` だけの軽い行にするか」。`/songs/all/` は 3,153 行を 1 枚に並べる
/// 到達性のためのハブなので、ジャケ・原唱者・披露回数を落として転送量を削る
/// (付けたままだと 1 ファイル 2MB を超える)。
fn song_list_item(ctx: &Ctx, index: u32, light: bool) -> Option<SongListItem> {
    let song = &ctx.snap.songs[index as usize];
    let mut reference = ctx.song_ref(&song.id)?;
    if light {
        // ジャケも落とす。3,153 枚の外部画像をぶら下げるページにしない。
        reference.artwork_url = None;
        return Some(SongListItem {
            reference,
            release_date: None,
            unit_label: None,
            artists_label: None,
            song_type_label: None,
            collab_label: None,
            composer_credit: None,
            cd_credit: None,
            performance_count: None,
            subtitle: None,
        });
    }
    let names: Vec<&str> = ctx
        .snap
        .song_artists(&song.id, Some("original"))
        .iter()
        .map(|i| i.name.as_str())
        .collect();
    let artists_label = artists_display(&names);
    Some(SongListItem {
        subtitle: join_parts([
            song.unit_name.clone(),
            artists_label.clone(),
            song.release_date.clone(),
        ]),
        reference,
        release_date: song.release_date.clone(),
        unit_label: song.unit_name.clone(),
        artists_label,
        song_type_label: song.song_type.as_deref().and_then(content::song_type_label).map(str::to_string),
        collab_label: song.is_collab.then(|| content::SONG_COLLAB_LABEL.to_string()),
        composer_credit: song.composer.as_deref().filter(|c| !c.is_empty()).map(content::composer_credit),
        cd_credit: song.cd_title.as_deref().filter(|c| !c.is_empty()).map(content::cd_credit),
        performance_count: Some(ctx.snap.performance_counts[index as usize]),
    })
}

/// ブランドの代表曲 (披露回数の降順)。並べ替えの規則はコアの `song_list_indexes` が持つ。
pub fn brand_top_song_indexes(ctx: &Ctx, brand_id: &str) -> Vec<u32> {
    song_list_indexes(
        ctx.snap,
        &default_song_filter(vec![brand_id.to_string()]),
        SongListSort::PerformanceCount,
        None,
        &[],
        &[],
    )
}

/// よみの先頭 1 文字で切った目次。
///
/// 表示のための区切りなので規則はここに置く (コアの判断ではない)。判定の前に
/// `prepare_needle` を通すので、「ア」も「あ」に入る = 検索の畳み込みと同じ規則になる。
fn kana_sections(ctx: &Ctx, items: &[SongListItem]) -> Vec<KanaSection> {
    kana_sections_of(items.iter().map(|item| {
        ctx.snap
            .song(&item.reference.id)
            .map(|s| s.reading().to_string())
            .unwrap_or_else(|| item.reference.name.clone())
    }))
}

/// よみの目次を、並び順の読みの列から組む (曲・ユニット共通)。
fn kana_sections_of(sources: impl Iterator<Item = String>) -> Vec<KanaSection> {
    let mut sections: Vec<KanaSection> = Vec::new();
    for (i, source) in sources.enumerate() {
        let label = kana_row_label(&source).to_string();
        if !sections.last().is_some_and(|last| last.label == label) {
            sections.push(KanaSection { label, start_index: i as u32 });
        }
    }
    sections
}



pub fn song_lists(ctx: &Ctx) -> Vec<Emitted<SongListPage>> {
    let total_all = ctx.snap.songs.len() as u32;
    // 既定フィルタを通した件数。ブランド切替の「すべて」に出す数はこれ
    // (全 3,153 曲ではなく、その一覧が実際に並べる 2,035 曲)。
    let listed = song_list_indexes(
        ctx.snap,
        &default_song_filter(vec![]),
        SongListSort::TitleKana,
        None,
        &[],
        &[],
    );
    let listed_total = listed.len() as u32;

    let make = |path: String,
                title: String,
                kind: SongListKind,
                route: (RouteKind, Option<String>),
                indexes: Vec<u32>,
                data: String,
                brand: Option<Ref>,
                description: String,
                base: SongListFilter| {
        let light = matches!(kind, SongListKind::All);
        let items: Vec<SongListItem> =
            indexes.iter().filter_map(|&i| song_list_item(ctx, i, light)).collect();
        // 行を ref だけに削った一覧 (/songs/all/) は絞り込みの土台を持たない。
        let query_base = (!light).then(|| SongQuery::from_filter(&base));
        let brand_id = brand.as_ref().map(|b| b.id.clone());
        let mut seo = ctx.seo(
            &title,
            &description,
            &path,
            brand_id.as_deref(),
            collection_json_ld(&title, &path),
            list_crumbs(SiteList::Songs, &title, &path),
        );
        if matches!(kind, SongListKind::All) {
            // 一覧規則から外れた曲の詳細ページを孤立させないためだけのハブ。
            // 索引には載せず、リンクだけ辿らせる。
            seo.robots = Robots::NoindexFollow;
        }
        Emitted {
            path: path.clone(),
            data,
            route_kind: route.0,
            param_key: route.1,
            page: SongListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title,
                kind,
                brand,
                rows_are_light: light,
                query_base,
                kana_sections: kana_sections(ctx, &items),
                total: items.len() as u32,
                all_songs_link: (path == "/songs/")
                    .then(|| NavLink::new("派生曲・ライブ限定曲を含む全件", "/songs/all/").with_count(total_all)),
                // タグから探す入口。一覧を作るかどうかと同じ判断 (`Ctx::tags_link`)。
                tags_link: (path == "/songs/").then(|| ctx.tags_link(content::TAG_LIST_LINK_LABEL)).flatten(),
                items,
                // アイドル一覧と同じ理由で、島が動く環境では隠れる (同じ軸を 2 つ並べない)。
                filters: filter_axes([FilterAxis::new(
                    content::FILTER_AXIS_BRAND,
                    brand_links(ctx, "songs", &path, "すべて", listed_total),
                )
                .also_in_island("brandIds")]),
                seo,
            },
        }
    };

    let mut out = vec![make(
        "/songs/".to_string(),
        "楽曲".to_string(),
        SongListKind::Index,
        (RouteKind::SongListIndex, None),
        listed,
        "index/songs.json".to_string(),
        None,
        "アイドルマスターの楽曲一覧。クレジット・歌唱アイドル・ライブでの披露履歴。".to_string(),
        default_song_filter(vec![]),
    )];

    // 全件ハブ。並びは通常の一覧と同じ規則 (よみ順) にする。
    let all = song_list_indexes(
        ctx.snap,
        &SongListFilter {
            include_remixes: true,
            include_other_brand: true,
            exclude_live_only: false,
            ..SongListFilter::default()
        },
        SongListSort::TitleKana,
        None,
        &[],
        &[],
    );
    out.push(make(
        "/songs/all/".to_string(),
        "楽曲（全件）".to_string(),
        SongListKind::All,
        (RouteKind::SongListAll, None),
        all,
        "index/songs-all.json".to_string(),
        None,
        format!("収録している全 {total_all} 曲。派生曲・ライブ限定曲を含みます。"),
        SongListFilter {
            include_remixes: true,
            include_other_brand: true,
            exclude_live_only: false,
            ..SongListFilter::default()
        },
    ));

    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        let Some(path) = ctx.brand_list_path("songs", &brand.id) else { continue };
        let indexes = song_list_indexes(
            ctx.snap,
            &default_song_filter(vec![brand.id.clone()]),
            SongListSort::TitleKana,
            None,
            &[],
            &[],
        );
        out.push(make(
            path,
            format!("{}の楽曲", brand.name),
            SongListKind::Brand,
            (RouteKind::SongListBrand, Some(brand.id.clone())),
            indexes,
            format!("index/songs-brand-{}.json", Ctx::param_key(&brand.id)),
            ctx.brand_ref(&brand.id),
            format!("{}の楽曲一覧。", brand.name),
            default_song_filter(vec![brand.id.clone()]),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// タグ (曲に付いたコミュニティのタグ) の一覧
// ---------------------------------------------------------------------------

/// タグの一覧は楽曲の下に置く: パンくずは [ホーム, 楽曲, タグ, (そのタグ)]。上部バーの現在地は
/// パンくずに `/songs/` が居ることで「楽曲」になる。
fn tag_crumbs(leaf: Option<(&str, &str)>) -> Vec<Crumb> {
    let mut crumbs = list_crumbs(SiteList::Songs, content::TAG_LIST_TITLE, TAGS_PATH);
    if let Some((name, path)) = leaf {
        crumbs.push(Ctx::crumb(name, path));
    }
    crumbs
}

/// タグ一覧 (`/tags/`) と、タグごとの曲一覧 (`/tags/<tagId>/`)。
///
/// 並びは `domain::song_tag_queries` (`Ctx::tag_ranking`)。タグの付いた曲が 1 曲も無ければ
/// **どちらも出さない** (お題と同じ: 中身の無いページを sitemap に載せない)。そのとき
/// `/songs/` の入口 (`tags_link`) も同じ判断で消える。
pub fn tag_lists(ctx: &Ctx) -> (Option<Emitted<TagListPage>>, Vec<Emitted<TagPage>>) {
    let Some(all_tags_link) = ctx.tags_link(content::TAG_LIST_TITLE) else {
        return (None, vec![]);
    };

    let pages: Vec<Emitted<TagPage>> = ctx
        .tag_ranking
        .iter()
        .map(|ranking| {
            let tag = ranking.tag;
            let path = ctx.tag_path(&tag.id);
            let items: Vec<TagSongRow> = ranking
                .songs
                .iter()
                .filter_map(|&(index, votes)| song_list_item(ctx, index, false).map(|item| (item, votes)))
                .enumerate()
                .map(|(i, (item, votes))| TagSongRow {
                    reference: item.reference,
                    subtitle: item.subtitle,
                    votes: votes.max(0) as u32,
                    rank: i as u32 + 1,
                })
                .collect();
            let title = content::tag_page_title(&tag.name);
            let total = items.len() as u32;
            Emitted {
                path: path.clone(),
                data: format!("index/tags-{}.json", Ctx::param_key(&tag.id)),
                route_kind: RouteKind::Tag,
                param_key: Some(tag.id.clone()),
                page: TagPage {
                    schema_version: SCHEMA_VERSION,
                    path: path.clone(),
                    seo: ctx.seo(
                        &title,
                        &content::tag_page_description(&tag.name, total),
                        &path,
                        None,
                        collection_json_ld(&title, &path),
                        tag_crumbs(Some((&title, &path))),
                    ),
                    title,
                    badge: tag_badge(tag),
                    description: tag.description.clone(),
                    lede: content::tag_page_lede(&tag.name),
                    total,
                    items,
                    all_tags_link: all_tags_link.clone(),
                },
            }
        })
        .collect();

    let items: Vec<TagListItem> = ctx
        .tag_ranking
        .iter()
        .map(|ranking| TagListItem {
            badge: tag_badge(ranking.tag),
            path: ctx.tag_path(&ranking.tag.id),
            description: ranking.tag.description.clone(),
            official_label: ranking.tag.is_official.then(|| content::TAG_OFFICIAL_LABEL.to_string()),
            song_count: ranking.songs.len() as u32,
        })
        .collect();
    let index = Emitted {
        path: TAGS_PATH.to_string(),
        data: "index/tags.json".to_string(),
        route_kind: RouteKind::TagListIndex,
        param_key: None,
        page: TagListPage {
            schema_version: SCHEMA_VERSION,
            path: TAGS_PATH.to_string(),
            title: content::TAG_LIST_TITLE.to_string(),
            lede: content::TAG_LIST_LEDE.to_string(),
            total: items.len() as u32,
            items,
            seo: ctx.seo(
                content::TAG_LIST_TITLE,
                content::TAG_LIST_DESCRIPTION,
                TAGS_PATH,
                None,
                collection_json_ld(content::TAG_LIST_TITLE, TAGS_PATH),
                tag_crumbs(None),
            ),
        },
    };
    (Some(index), pages)
}

// ---------------------------------------------------------------------------
// アイドル一覧
// ---------------------------------------------------------------------------

/// 表の列 (名前の次から)。値の並びは [`idol_cells`] が同じ順で作る。
/// **見出しと値を 1 箇所で決める**ので、片方だけ足してずれることが無い。
fn idol_columns() -> Vec<IdolColumn> {
    use IdolSortKind::{Age, Birthday, Debut, Height, Official, Weight};
    [
        // ブランドの列は公式順で並べる。`idols.sort_order` はブランドごとの番号帯
        // (`brands.sort_order * 1000`) になっていて、公式順で並べると必ずブランド順に
        // なる (tools/renumber_idol_sort_order.py が付番と検査を持つ)。
        // 帯を導入する前はブランドが混ざっていたので、この列は押せなくしてあった。
        (content::IDOL_COLUMN_BRAND, false, Some(Official)),
        (content::IDOL_COLUMN_VOICE_ACTOR, false, None),
        (content::IDOL_COLUMN_BIRTHDAY, false, Some(Birthday)),
        (content::IDOL_COLUMN_AGE, true, Some(Age)),
        (content::IDOL_COLUMN_HEIGHT, true, Some(Height)),
        (content::IDOL_COLUMN_WEIGHT, true, Some(Weight)),
        (content::IDOL_COLUMN_BLOOD, false, None),
        (content::IDOL_COLUMN_CONSTELLATION, false, None),
        (content::IDOL_COLUMN_BIRTHPLACE, false, None),
        (content::IDOL_COLUMN_ATTRIBUTE, false, None),
        (content::IDOL_COLUMN_DEBUT, false, Some(Debut)),
        (content::IDOL_COLUMN_SONGS, true, None),
        (content::IDOL_COLUMN_SHOWS, true, None),
    ]
    .into_iter()
    .map(|(label, numeric, sort)| column(label, numeric, sort))
    .collect()
}

/// 列 1 つ。**並べ替えの鍵はコアの `IdolSortKind` から取る** (画面が "age" のような
/// 文字列を自前で書くと、鍵を変えたときに黙って並ばなくなる)。
fn column(label: &str, numeric: bool, sort: Option<IdolSortKind>) -> IdolColumn {
    IdolColumn {
        label: label.to_string(),
        numeric,
        sort_key: sort.map(|k| k.key().to_string()),
    }
}

/// 1 行ぶんの値。[`idol_columns`] と同じ並び。
fn idol_cells(ctx: &Ctx, record: &idol_queries::IdolRecord) -> Vec<Option<String>> {
    // 持ち曲 (原唱) と出演公演は索引を数えるだけ (行ごとにクエリを投げない)。
    let counts = ctx.snap.idol_index_by_id.get(&record.id).map(|&i| {
        let songs = ctx.snap.songs_by_idol[i as usize].iter().filter(|l| l.role == "original").count();
        (songs as u32, ctx.snap.cast_shows_by_idol[i as usize].len() as u32)
    });
    let nonzero = |n: u32| (n > 0).then(|| n.to_string());
    vec![
        record.brand_id.as_deref().and_then(|b| ctx.brand(b)).map(|b| b.short_name.clone()),
        idol_queries::current_voice_actor_name(ctx.snap, &record.id),
        idol_queries::birthday_display(record.birthday.as_deref()),
        record.age.map(content::idol_age_display),
        idol_queries::height_display(record.height),
        record.weight.map(content::idol_weight_display),
        record.blood_type.as_deref().map(content::idol_blood_display),
        record.constellation.clone(),
        record.birth_place.clone(),
        record.attribute.as_deref().map(content::idol_attribute_label),
        record.debut_date.as_deref().map(content::idol_debut_display),
        counts.and_then(|(songs, _)| nonzero(songs)),
        counts.and_then(|(_, shows)| nonzero(shows)),
    ]
    .into_iter()
    .map(|value: Option<String>| value.filter(|v| !v.is_empty()))
    .collect()
}

fn idol_list_item(ctx: &Ctx, record: &idol_queries::IdolRecord) -> Option<IdolListItem> {
    Some(IdolListItem {
        reference: ctx.idol_ref(&record.id)?,
        name_kana: record.name_kana.clone(),
        cells: idol_cells(ctx, record),
    })
}

/// **その一覧の中で値が 1 種類しかない列は落とす。** 全行が空の列 (誰も値を持たない)
/// も、全行が同じ値の列 (ブランド別の一覧の「ブランド」) も、そこでは見分けに使えない。
/// 見出しと値を一緒に間引くので、並びはずれない。
fn drop_empty_columns(columns: Vec<IdolColumn>, items: &mut [IdolListItem]) -> Vec<IdolColumn> {
    let keep: Vec<bool> = (0..columns.len())
        .map(|i| {
            // 1 行だけの一覧は間引かない (見分ける相手が居ないだけで、値は読みたい)。
            items.len() <= 1
                || items.iter().map(|item| item.cells[i].as_deref()).collect::<HashSet<_>>().len() > 1
        })
        .collect();
    for item in items.iter_mut() {
        let mut iter = keep.iter();
        item.cells.retain(|_| *iter.next().expect("keep は cells と同じ長さ"));
    }
    let mut iter = keep.iter();
    columns.into_iter().filter(|_| *iter.next().expect("keep は columns と同じ長さ")).collect()
}

pub fn idol_lists(ctx: &Ctx) -> Vec<Emitted<IdolListPage>> {
    let birth_month_links: Vec<NavLink> = (1..=12u32)
        .map(|m| {
            NavLink::new(&format!("{m}月"), birth_month_path(m))
                .with_count(idol_queries::idols_by_birth_month(ctx.snap, m).len() as u32)
        })
        .collect();

    let all_total = idol_queries::idol_list(ctx.snap, None).len() as u32;

    let make = |path: String,
                title: String,
                kind: IdolListKind,
                route: (RouteKind, Option<String>),
                records: Vec<idol_queries::IdolRecord>,
                data: String,
                brand: Option<Ref>,
                birth_month: Option<u32>,
                description: String| {
        let mut items: Vec<IdolListItem> =
            records.iter().filter_map(|r| idol_list_item(ctx, r)).collect();
        let columns = drop_empty_columns(idol_columns(), &mut items);
        let brand_id = brand.as_ref().map(|b| b.id.clone());
        Emitted {
            path: path.clone(),
            data,
            route_kind: route.0,
            param_key: route.1,
            page: IdolListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title: title.clone(),
                kind,
                brand,
                birth_month,
                total: items.len() as u32,
                // 絞り込みの出発点。ページの中身を決めた条件をそのまま渡す
                // (JS 側で「/idols/brand/cg/ ならブランド cg」と書き直すと二重定義になる)。
                query_base: IdolQuery {
                    brand_ids: brand_id.iter().cloned().collect(),
                    birth_month,
                    ..IdolQuery::default()
                },
                items,
                columns,
                name_column: column(content::IDOL_COLUMN_NAME, false, Some(IdolSortKind::NameKana)),
                // 島 (絞り込みバー) が同じ 2 軸を持つので、島が動く環境では隠れる。
                // 鍵は `web/src/lib/listfilter/idols.ts` の `FieldSpec.key` と揃える。
                filters: filter_axes([
                    FilterAxis::new(content::FILTER_AXIS_BRAND, brand_links(ctx, "idols", &path, "すべて", all_total))
                        .also_in_island("brandIds"),
                    FilterAxis::new(content::FILTER_AXIS_BIRTH_MONTH, {
                        let mut links = birth_month_links.clone();
                        mark_current(&mut links, &path);
                        links
                    })
                    .also_in_island("birthMonth"),
                ]),
                seo: ctx.seo(
                    &title,
                    &description,
                    &path,
                    brand_id.as_deref(),
                    collection_json_ld(&title, &path),
                    list_crumbs(SiteList::Idols, &title, &path),
                ),
            },
        }
    };

    let mut out = vec![make(
        "/idols/".to_string(),
        "アイドル".to_string(),
        IdolListKind::Index,
        (RouteKind::IdolListIndex, None),
        idol_queries::idol_list(ctx.snap, None),
        "index/idols.json".to_string(),
        None,
        None,
        "アイドルマスターのアイドル一覧。プロフィール・CV・持ち曲・出演したライブ。".to_string(),
    )];

    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        let Some(path) = ctx.brand_list_path("idols", &brand.id) else { continue };
        out.push(make(
            path,
            format!("{}のアイドル", brand.name),
            IdolListKind::Brand,
            (RouteKind::IdolListBrand, Some(brand.id.clone())),
            idol_queries::idol_list(ctx.snap, Some(&brand.id)),
            format!("index/idols-brand-{}.json", Ctx::param_key(&brand.id)),
            ctx.brand_ref(&brand.id),
            None,
            format!("{}のアイドル一覧。", brand.name),
        ));
    }

    for month in 1..=12u32 {
        out.push(make(
            birth_month_path(month),
            format!("{month}月生まれのアイドル"),
            IdolListKind::BirthMonth,
            (RouteKind::IdolListBirthMonth, Some(month.to_string())),
            idol_queries::idols_by_birth_month(ctx.snap, month),
            format!("index/idols-birth-month-{month}.json"),
            None,
            Some(month),
            format!("{month}月が誕生日のアイドル一覧。"),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// ユニット一覧
// ---------------------------------------------------------------------------

pub fn unit_lists(ctx: &Ctx) -> Vec<Emitted<UnitListPage>> {
    let index = unit_queries::unit_index_data(ctx.snap);
    // よみ順 (曲一覧と同じ規則)。DB の並びは登録順で、1,500 件を目で追えない。
    let unit_reading = |u: &unit_queries::UnitRecord| u.name_kana.clone().unwrap_or_else(|| u.name.clone());
    let mut units: Vec<&unit_queries::UnitRecord> = index.units.iter().collect();
    units.sort_by_cached_key(|u| kana_sort_key(&unit_reading(u)));
    let member_counts: BTreeMap<String, u32> = index.units.iter().map(|u| {
        let count = ctx
            .snap
            .unit_index_by_id
            .get(&u.id)
            .map(|&i| ctx.snap.members_by_unit[i as usize].len() as u32)
            .unwrap_or(0);
        (u.id.clone(), count)
    }).collect();

    let item = |u: &unit_queries::UnitRecord| -> Option<UnitListItem> {
        let song_count = ctx
            .snap
            .unit_index_by_id
            .get(&u.id)
            .map(|&i| ctx.snap.songs_by_unit[i as usize].len() as u32)
            .unwrap_or(0);
        Some(UnitListItem {
            reference: ctx.unit_ref(&u.id)?,
            brand: ctx.brand_ref(&u.brand_id),
            note: (!u.is_permanent).then(|| content::UNIT_LIMITED_LABEL.to_string()),
            member_count: member_counts.get(&u.id).copied().unwrap_or(0),
            // `songs_by_unit` が空でないユニットが `song_unit_ids` に入る、という
            // 関係なので `max(1)` は証明可能に no-op だった (そのために HashSet を
            // 1 つ作っていた)。
            song_count,
        })
    };

    let make = |path: String,
                title: String,
                route: (RouteKind, Option<String>),
                units: Vec<&unit_queries::UnitRecord>,
                data: String,
                brand: Option<Ref>,
                description: String| {
        let items: Vec<UnitListItem> = units.iter().filter_map(|u| item(u)).collect();
        let kana_sections = kana_sections_of(units.iter().map(|u| unit_reading(u)));
        let brand_id = brand.as_ref().map(|b| b.id.clone());
        Emitted {
            path: path.clone(),
            data,
            route_kind: route.0,
            param_key: route.1,
            page: UnitListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title: title.clone(),
                brand,
                total: items.len() as u32,
                items,
                kana_sections,
                filters: filter_axes([FilterAxis::new(
                    content::FILTER_AXIS_BRAND,
                    brand_links(ctx, "units", &path, "すべて", index.units.len() as u32),
                )]),
                seo: ctx.seo(
                    &title,
                    &description,
                    &path,
                    brand_id.as_deref(),
                    collection_json_ld(&title, &path),
                    list_crumbs(SiteList::Units, &title, &path),
                ),
            },
        }
    };

    let mut out = vec![make(
        "/units/".to_string(),
        "ユニット".to_string(),
        (RouteKind::UnitListIndex, None),
        units.clone(),
        "index/units.json".to_string(),
        None,
        "アイドルマスターのユニット一覧。メンバーとユニット曲。".to_string(),
    )];
    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        let Some(path) = ctx.brand_list_path("units", &brand.id) else { continue };
        out.push(make(
            path,
            format!("{}のユニット", brand.name),
            (RouteKind::UnitListBrand, Some(brand.id.clone())),
            units.iter().copied().filter(|u| u.brand_id == brand.id).collect(),
            format!("index/units-brand-{}.json", Ctx::param_key(&brand.id)),
            ctx.brand_ref(&brand.id),
            format!("{}のユニット一覧。", brand.name),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// 会場一覧
// ---------------------------------------------------------------------------

/// 誕生月別一覧の URL。
fn birth_month_path(month: u32) -> String {
    format!("/idols/birth-month/{month}/")
}

/// 都道府県別一覧の URL。都道府県名は日本語なので必ず `url_segment` を通す。
fn pref_path(prefecture: &str) -> String {
    format!("/venues/pref/{}/", url_segment(prefecture))
}

/// 会場の都道府県。空欄は `未分類` にまとめる (実データに 35 件ある)。
pub fn prefecture_of(venue: &crate::domain::snapshot::Venue) -> String {
    match venue.prefecture.as_deref() {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => UNCLASSIFIED_PREFECTURE.to_string(),
    }
}

pub fn venue_lists(ctx: &Ctx) -> Vec<Emitted<VenueListPage>> {
    let show_counts: BTreeMap<&str, u32> = ctx
        .snap
        .venues
        .iter()
        .map(|v| {
            let count =
                ctx.snap.shows_by_venue_id.get(&v.id).map(|s| s.len() as u32).unwrap_or(0);
            (v.id.as_str(), count)
        })
        .collect();

    // 都道府県ごとの並びは venue_order (コアが決めた並び) をそのまま保つ。
    let mut by_prefecture: BTreeMap<String, Vec<u32>> = BTreeMap::new();
    for &i in &ctx.snap.venue_order {
        by_prefecture.entry(prefecture_of(&ctx.snap.venues[i as usize])).or_default().push(i);
    }

    // 会場の多い順 (東京 105 が真ん中に埋もれない)。同数は名前順で決定化。
    let mut prefecture_links: Vec<NavLink> = by_prefecture
        .iter()
        .map(|(pref, list)| NavLink::new(pref, pref_path(pref)).with_count(list.len() as u32))
        .collect();
    prefecture_links.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.label.cmp(&b.label)));

    let item = |i: u32| -> Option<VenueListItem> {
        let v = &ctx.snap.venues[i as usize];
        Some(VenueListItem {
            reference: ctx.venue_ref(&v.id)?,
            location_display: location_display(v.prefecture.as_deref(), v.city.as_deref()),
            prefecture: v.prefecture.clone(),
            city: v.city.clone(),
            capacity: v.capacity.map(|c| c as i32),
            show_count: show_counts.get(v.id.as_str()).copied().unwrap_or(0),
        })
    };

    let make = |path: String,
                title: String,
                route: (RouteKind, Option<String>),
                indexes: &[u32],
                data: String,
                prefecture: Option<String>,
                description: String| {
        let items: Vec<VenueListItem> = indexes.iter().filter_map(|&i| item(i)).collect();
        Emitted {
            path: path.clone(),
            data,
            route_kind: route.0,
            param_key: route.1,
            page: VenueListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title: title.clone(),
                prefecture,
                total: items.len() as u32,
                items,
                filters: filter_axes([FilterAxis::new(content::FILTER_AXIS_PREFECTURE, {
                    let mut links = prefecture_links.clone();
                    mark_current(&mut links, &path);
                    links
                })]),
                seo: ctx.seo(
                    &title,
                    &description,
                    &path,
                    None,
                    collection_json_ld(&title, &path),
                    list_crumbs(SiteList::Venues, &title, &path),
                ),
            },
        }
    };

    let all: Vec<u32> = ctx.snap.venue_order.clone();
    let mut out = vec![make(
        "/venues/".to_string(),
        "会場".to_string(),
        (RouteKind::VenueListIndex, None),
        &all,
        "index/venues.json".to_string(),
        None,
        "アイドルマスターのライブが行われた会場の一覧。".to_string(),
    )];
    for (pref, indexes) in &by_prefecture {
        out.push(make(
            pref_path(pref),
            format!("{pref}の会場"),
            (RouteKind::VenueListPref, Some(pref.clone())),
            indexes,
            format!("index/venues-pref-{}.json", Ctx::param_key(pref)),
            Some(pref.clone()),
            format!("{pref}にある、アイドルマスターのライブが行われた会場。"),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// ブランド一覧 / トップ / About
// ---------------------------------------------------------------------------

fn brand_list_item(ctx: &Ctx, brand_id: &str) -> Option<BrandListItem> {
    let brand = ctx.brand(brand_id)?;
    let counts = ctx.brand_counts(brand_id);
    Some(BrandListItem {
        reference: ctx.brand_ref(brand_id)?,
        // カードに大きく出す短い名前。短縮名は実データで最長 5 文字なのでそのまま通る。
        // 2 文字に切ると `765AS` → `76`、`学マス` → `学マ` でどれも読めなくなる。
        glyph: super::glyph::brand_glyph(&brand.short_name),
        short_name: Some(brand.short_name.clone()),
        // 素の件数を配ると .astro が組み立て直すことになり、実際にトップと /brands/ で
        // 項目数が食い違っていた (片方だけユニット数が無かった)。
        preview_display: join_parts([
            Some(format!("ライブ {}", counts.events)),
            Some(format!("楽曲 {}", counts.songs)),
            Some(format!("アイドル {}", counts.idols)),
            Some(format!("ユニット {}", counts.units)),
        ])
        .unwrap_or_default(),
    })
}

pub fn brand_list(ctx: &Ctx) -> BrandListPage {
    let path = "/brands/";
    BrandListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: "ブランド".to_string(),
        items: ctx
            .snap
            .brand_order
            .iter()
            .filter_map(|&i| brand_list_item(ctx, &ctx.snap.brands[i as usize].id))
            .collect(),
        seo: ctx.seo(
            "ブランド",
            "アイドルマスターの各ブランドと、その所属アイドル・ユニット・ライブ・楽曲。",
            path,
            None,
            collection_json_ld("ブランド", path),
            vec![Ctx::crumb("ホーム", "/"), Ctx::crumb("ブランド", path)],
        ),
    }
}

/// お題の一覧。**焼き込んだ集計をそのまま並べる**だけで、投票は受け付けない。
///
/// 出すのは `status = 'active'` のものだけ (取り下げられたお題は出さない)。
/// 締切前かどうかも、`ends_at` と出面の「今日」から Rust が決める。
pub fn poll_list(ctx: &Ctx) -> PollListPage {
    let path = "/polls/";
    // 何件まで見せるか。全部出すと 1 ページが得票の羅列になるので上位だけ。
    const TOP_N: usize = 10;

    let polls: Vec<PollSummaryDto> = ctx
        .community
        .polls
        .iter()
        .filter(|p| p.status == "active")
        .map(|poll| {
            let all = ctx.community.poll_entries(&poll.id);
            let entries: Vec<PollEntryDto> = all
                .iter()
                .filter_map(|e| {
                    // 消えた曲・アイドルを指す得票は落とす (id は D1 側の値)。
                    let reference = match poll.target_type.as_str() {
                        "idol" => ctx.idol_ref(&e.entity_id),
                        _ => ctx.song_ref(&e.entity_id),
                    }?;
                    Some((reference, e.vote_count))
                })
                .take(TOP_N)
                .enumerate()
                .map(|(i, (reference, votes))| PollEntryDto {
                    reference,
                    votes: votes.max(0) as u32,
                    rank: i as u32 + 1,
                })
                .collect();
            PollSummaryDto {
                id: poll.id.clone(),
                title: poll.title.clone(),
                description: poll.description.clone(),
                target_label: match poll.target_type.as_str() {
                    "idol" => "アイドル",
                    "unit" => "ユニット",
                    _ => "曲",
                }
                .to_string(),
                // 時刻は落として日付だけ見せる (分単位の締切に意味は無い)。
                ends_on: poll.ends_at.as_ref().map(|e| e[..10.min(e.len())].to_string()),
                // 締切前か。`ends_at` が無いお題は開いたまま。
                is_open: poll
                    .ends_at
                    .as_deref()
                    .is_none_or(|e| &e[..10.min(e.len())] >= ctx.today.as_str()),
                total_votes: all.iter().map(|e| e.vote_count.max(0) as u32).sum(),
                entries,
            }
        })
        .collect();

    PollListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: "みんなのお題".to_string(),
        total: polls.len() as u32,
        polls,
        seo: ctx.seo(
            "みんなのお題",
            "アプリの利用者が出し合ったお題と、その時点の得票。投票はアプリから。",
            path,
            None,
            collection_json_ld("みんなのお題", path),
            vec![Ctx::crumb("ホーム", "/"), Ctx::crumb("みんなのお題", path)],
        ),
    }
}

pub fn counts(ctx: &Ctx) -> Counts {
    Counts {
        events: ctx.snap.events.len() as u32,
        shows: ctx.snap.shows.len() as u32,
        songs: ctx.snap.songs.len() as u32,
        idols: ctx.snap.idols.len() as u32,
        units: ctx.snap.units.len() as u32,
        venues: ctx.snap.venues.len() as u32,
        brands: ctx.snap.brands.len() as u32,
        setlist_items: ctx.snap.setlist_items.len() as u32,
    }
}

/// サイトの主要な一覧。ナビ (ヘッダ / フッタ)・トップの件数タイル・ブランドの数の帯が、
/// 記号・名前・入口を**この 1 本から**取る (並びと表記を 3 箇所に持たない)。
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum SiteList {
    Events,
    /// ライブを月の枠で見る入口。件数のタイルとブランド別一覧は持たない。
    Calendar,
    Shows,
    Songs,
    Idols,
    Units,
    Venues,
    Brands,
}

impl SiteList {
    /// 見出しの記号。版権物を持たないので記号で見分ける。
    pub fn glyph(self) -> &'static str {
        match self {
            Self::Events => "♪",
            Self::Calendar => "▦",
            Self::Shows => "▤",
            Self::Songs => "♬",
            Self::Idols => "☺",
            Self::Units => "❋",
            Self::Venues => "⌂",
            Self::Brands => "◆",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Events => "ライブ",
            Self::Calendar => content::CALENDAR_TITLE,
            Self::Shows => "公演",
            Self::Songs => "楽曲",
            Self::Idols => "アイドル",
            Self::Units => "ユニット",
            Self::Venues => "会場",
            Self::Brands => "ブランド",
        }
    }

    /// サイト全体の一覧への入口。
    pub fn path(self) -> &'static str {
        match self {
            Self::Events => "/events/",
            Self::Calendar => super::calendar::CALENDAR_PATH,
            Self::Shows => "/events/past/",
            Self::Songs => "/songs/",
            Self::Idols => "/idols/",
            Self::Units => "/units/",
            Self::Venues => "/venues/",
            Self::Brands => "/brands/",
        }
    }

    /// ブランド別一覧を持つものは、その collection 名 (`Ctx::brand_list_path` の引数)。
    pub fn brand_collection(self) -> Option<&'static str> {
        match self {
            Self::Events => Some("events"),
            Self::Songs => Some("songs"),
            Self::Idols => Some("idols"),
            Self::Units => Some("units"),
            Self::Calendar | Self::Shows | Self::Venues | Self::Brands => None,
        }
    }

    /// 件数タイル 1 枚。
    pub fn tile(self, value: u32, href: Option<String>) -> StatTile {
        let tile = StatTile::new(self.glyph(), value, self.label());
        match href {
            Some(href) => tile.with_href(href),
            None => tile,
        }
    }
}

/// サイト全体の件数タイル。
///
/// `with_links` はタイルから一覧へ飛ばすか (トップは飛ばす / About は読み物なので飛ばさない)。
/// `with_setlist_items` は「セトリ項目」を足すか (About だけ)。
/// どの件数をどの順で出すかの判断はここ 1 箇所にある。
fn site_stat_tiles(counts: Counts, with_links: bool, with_setlist_items: bool) -> Vec<StatTile> {
    let mut tiles: Vec<StatTile> = [
        (SiteList::Events, counts.events),
        (SiteList::Shows, counts.shows),
        (SiteList::Songs, counts.songs),
        (SiteList::Idols, counts.idols),
        (SiteList::Units, counts.units),
        (SiteList::Venues, counts.venues),
    ]
    .into_iter()
    .map(|(list, value)| list.tile(value, with_links.then(|| list.path().to_string())))
    .collect();
    if with_setlist_items {
        // 「セトリ項目」だけは対応する一覧が無いのでリンクを持たない。
        tiles.push(StatTile {
            glyph: "≡".to_string(),
            value: counts.setlist_items,
            label: "セトリ項目".to_string(),
            href: None,
        });
    }
    tiles
}

/// 一覧以外の入口 (検索・このサイトについて)。ヘッダ / フッタが描く。
pub fn utility_nav() -> Vec<NavLink> {
    vec![NavLink::new("検索", "/search/"), NavLink::new("このサイトについて", "/about/")]
}

/// トップページ。
pub fn home(ctx: &Ctx, upcoming: &[EventListItem], counts: Counts) -> HomePage {
    let path = "/";
    HomePage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        tagline: content::SITE_TAGLINE.to_string(),
        // 先頭 8 件。種別の札は例外 (フェス・リリースイベント) にだけ付く (`content::kind_chip`)。
        upcoming: upcoming.iter().take(8).cloned().collect(),
        recent_shows: super::events::recent_shows(ctx, 8),
        recent_shows_more: NavLink::new("開催済みのライブへ", "/events/past/"),
        app_note: content::app_note(),
        stat_tiles: site_stat_tiles(counts, true, false),
        brands: ctx
            .snap
            .brand_order
            .iter()
            .filter_map(|&i| brand_list_item(ctx, &ctx.snap.brands[i as usize].id))
            .collect(),
        app: content::app_links(),
        seo: ctx.seo(
            content::SITE_NAME,
            content::SITE_TAGLINE,
            path,
            None,
            simple_json_ld("WebSite", content::SITE_NAME, "/"),
            vec![Ctx::crumb("ホーム", "/")],
        ),
    }
}

/// サイト共通ナビ (ヘッダ / フッタ)。
///
/// お題は焼き込んだ集計が 1 件も無いとページごと出ない (`emit::run`) ので、
/// その判断を知っている側がリンクの有無も決める。TS に手書きの並びを
/// 持たせると、条件を知らないままリンク切れを出す。
pub fn primary_nav(with_polls: bool, with_calls: bool) -> Vec<NavLink> {
    let mut nav: Vec<NavLink> = [
        SiteList::Events,
        // ライブを月の枠で見る入口はライブの隣。
        SiteList::Calendar,
        SiteList::Songs,
        SiteList::Idols,
        SiteList::Units,
        SiteList::Venues,
        SiteList::Brands,
    ]
    .into_iter()
    .map(|list| NavLink::new(list.label(), list.path()))
    .collect();
    if with_polls {
        nav.push(NavLink::new("お題", "/polls/"));
    }
    if with_calls {
        // 「コール」だけではアプリの外で意味が取れない (コーレス? 電話?)。
        nav.push(NavLink::new("コールガイド", super::calls::PATH));
    }
    nav
}

pub fn about(ctx: &Ctx, counts: Counts) -> AboutPage {
    let path = "/about/";
    AboutPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        stat_tiles: site_stat_tiles(counts, false, true),
        data_version: ctx.data_version.clone(),
        content_hash: ctx.content_hash.clone(),
        generated_at: ctx.generated_at.clone(),
        today_jst: ctx.today.clone(),
        app: content::app_links(),
        sections: content::about_sections(),
        seo: ctx.seo(
            "このサイトについて",
            "非公式のファンメイドサイトです。版権方針・ライセンス・アプリ・データの貢献について。",
            path,
            None,
            simple_json_ld("AboutPage", "このサイトについて", path),
            vec![Ctx::crumb("ホーム", "/"), Ctx::crumb("このサイトについて", path)],
        ),
    }
}

fn collection_json_ld(name: &str, path: &str) -> serde_json::Value {
    simple_json_ld("CollectionPage", name, path)
}

/// 「今後のライブ」のリスト。
///
/// `/events/upcoming/` を組んだ結果から取り出す。トップのためだけに
/// `events_with_first_date` と年グループ化をもう一度回さない。
pub fn upcoming_items(pages: &[Emitted<EventListPage>]) -> Vec<EventListItem> {
    pages
        .iter()
        .find(|p| p.route_kind == RouteKind::EventListUpcoming)
        .map(|p| p.page.groups.iter().flat_map(|g| g.events.iter().cloned()).collect())
        .unwrap_or_default()
}


