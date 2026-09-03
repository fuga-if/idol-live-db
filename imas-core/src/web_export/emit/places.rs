//! 会場 (venue) とブランド (brand) の詳細ページ。

use super::context::{join_parts, Ctx};
use super::events::shows_at_venue;
use super::idols::period_display;
use crate::domain::event_detail_queries as detail;
use crate::domain::event_list_queries;
use crate::domain::idol_queries;
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url::split_csv;
use crate::web_export::url::url_segment;
use std::collections::BTreeMap;

/// ブランドページに出す「最近のライブ」「代表曲」の件数。
const TOP_N: usize = 12;

/// 都道府県が空の会場をまとめる先。実データに 35 件ある。
pub const UNCLASSIFIED_PREFECTURE: &str = "未分類";

/// 会場ディレクトリを一度だけ読み、id 引きできる形にしたもの。
pub struct VenueDirectory {
    pub names_by_venue: BTreeMap<String, Vec<VenueNameRow>>,
    pub halls_by_venue: BTreeMap<String, Vec<HallRow>>,
}

impl VenueDirectory {
    pub fn load(ctx: &Ctx) -> Self {
        let directory = detail::venue_directory(ctx.snap);
        let mut names_by_venue: BTreeMap<String, Vec<VenueNameRow>> = BTreeMap::new();
        for n in directory.names {
            names_by_venue.entry(n.venue_id).or_default().push(VenueNameRow {
                period_display: period_display(n.valid_from.as_deref(), n.valid_to.as_deref()),
                name: n.name,
                start_date: n.valid_from,
                end_date: n.valid_to,
            });
        }
        let mut halls_by_venue: BTreeMap<String, Vec<HallRow>> = BTreeMap::new();
        for h in directory.halls {
            halls_by_venue
                .entry(h.venue_id)
                .or_default()
                .push(HallRow { name: h.name, capacity: h.capacity.map(|c| c as i32) });
        }
        Self { names_by_venue, halls_by_venue }
    }
}

pub fn venue_page(ctx: &Ctx, venue_id: &str, directory: &VenueDirectory) -> Option<VenuePage> {
    let venue = ctx.snap.venue(venue_id)?;
    let path = ctx.path(RefKind::Venue, venue_id);
    // 所在地は「千葉県 千葉市美浜区」。都道府県と市区町村の間だけは中黒でなく空白。
    let location_display = {
        let parts: Vec<&str> = [venue.prefecture.as_deref(), venue.city.as_deref()]
            .into_iter()
            .flatten()
            .filter(|s| !s.is_empty())
            .collect();
        (!parts.is_empty()).then(|| parts.join(" "))
    };
    let place = location_display.clone().unwrap_or_default();
    let aliases_display = join_parts(split_csv(venue.aliases.as_deref()).map(Some));

    let breadcrumbs = vec![
        ctx.crumb("ホーム", "/"),
        ctx.crumb("会場", "/venues/"),
        ctx.crumb(&venue.name, &path),
    ];

    Some(VenuePage {
        schema_version: SCHEMA_VERSION,
        id: venue.id.clone(),
        path: path.clone(),
        name: venue.name.clone(),
        name_kana: venue.name_kana.clone(),
        theme_key: ctx.brand_theme(None),
        prefecture: venue.prefecture.clone(),
        city: venue.city.clone(),
        fact_rows: venue_fact_rows(
            location_display.as_deref(),
            venue.capacity,
            aliases_display.as_deref(),
        ),
        location_display,
        capacity: venue.capacity.map(|c| c as i32),
        aliases_display,
        halls: directory.halls_by_venue.get(venue_id).cloned().unwrap_or_default(),
        past_names: directory.names_by_venue.get(venue_id).cloned().unwrap_or_default(),
        events: detail::event_ids_at_venue(ctx.snap, venue_id)
            .iter()
            .filter_map(|id| ctx.event_ref(id))
            .collect(),
        shows: shows_at_venue(ctx, venue_id),
        app: content::app_open_plain(),
        seo: ctx.seo(
            &venue.name,
            &format!(
                "{}{}で行われたアイドルマスターのライブと公演。",
                venue.name,
                if place.is_empty() { String::new() } else { format!("（{place}）") }
            ),
            &path,
            None,
            serde_json::json!({
                        "@type": "Place",
                "name": venue.name,
                "url": content::absolute(&path),
            }),
            breadcrumbs,
        ),
    })
}

/// 会場の「基本情報」行。値が無い行は出さない (アイドルの `profile_rows` と同じ規則)。
///
/// 「人」の付与もここでやる。単位は表示の判断だが、**どの単位を付けるかはデータの
/// 意味に属する**ので、値を知っている側で決める。
fn venue_fact_rows(
    location: Option<&str>,
    capacity: Option<i64>,
    aliases: Option<&str>,
) -> Vec<ProfileRow> {
    [
        ("所在", location.map(str::to_string), "plain"),
        ("収容人数", capacity.map(|c| format!("{c}人")), "monospaced"),
        ("別名", aliases.map(str::to_string), "plain"),
    ]
    .into_iter()
    .filter_map(|(label, value, style)| {
        Some(ProfileRow {
            label: label.to_string(),
            value: value.filter(|v| !v.is_empty())?,
            style: style.to_string(),
            link: None,
        })
    })
    .collect()
}

/// ブランド 1 件ぶんの件数。
///
/// `Counts` (サイト全体用) を流用しない。会場とセトリ項目はブランドに紐付かないので
/// 0 を詰めることになり、「web 側はその 3 つを読まない」という口約束に頼る形になる
/// (実際にその約束はコメントと食い違っていた)。意味のある 5 つだけを持つ。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct BrandCounts {
    pub events: u32,
    pub shows: u32,
    pub songs: u32,
    pub idols: u32,
    pub units: u32,
}

pub fn brand_counts(ctx: &Ctx, brand_id: &str) -> BrandCounts {
    let event_ids: std::collections::HashSet<&str> = ctx
        .snap
        .events
        .iter()
        .filter(|e| e.brand_id.as_deref() == Some(brand_id))
        .map(|e| e.id.as_str())
        .collect();
    let shows = ctx
        .snap
        .shows
        .iter()
        .filter(|s| event_ids.contains(ctx.snap.events[s.event as usize].id.as_str()))
        .count();
    BrandCounts {
        events: event_ids.len() as u32,
        shows: shows as u32,
        songs: ctx.snap.songs.iter().filter(|s| s.brand_id.as_deref() == Some(brand_id)).count()
            as u32,
        idols: ctx.snap.idols.iter().filter(|i| i.brand_id.as_deref() == Some(brand_id)).count()
            as u32,
        units: ctx.snap.units.iter().filter(|u| u.brand_id == brand_id).count() as u32,
    }
}

/// ブランドページの件数タイル。公演は出さない (現行の 4 タイルを維持)。
pub fn brand_stat_tiles(counts: BrandCounts) -> Vec<StatTile> {
    [
        ("♪", counts.events, "ライブ"),
        ("♬", counts.songs, "楽曲"),
        ("☺", counts.idols, "アイドル"),
        ("❋", counts.units, "ユニット"),
    ]
    .into_iter()
    .map(|(glyph, value, label)| StatTile {
        glyph: glyph.to_string(),
        value,
        label: label.to_string(),
        href: None,
    })
    .collect()
}

pub fn brand_page(ctx: &Ctx, brand_id: &str) -> Option<BrandPage> {
    let brand = ctx.brand(brand_id)?.clone();
    let path = ctx.path(RefKind::Brand, brand_id);
    let theme_key = ctx.brand_theme(Some(brand_id));

    // ブランドの最近のライブ。`events_with_first_date` が first_date の降順で返すので
    // ここで並べ直さない (並びの規則を 2 箇所に持たない)。
    let events = event_list_queries::events_with_first_date(
        ctx.snap,
        Some(brand_id),
        true,
        false,
        Some(&super::lists::all_event_kinds()),
    );
    let recent_events: Vec<Ref> =
        events.iter().take(TOP_N).filter_map(|e| ctx.event_ref(&e.event.id)).collect();

    // 代表曲。並べ替えの規則 (披露回数の降順・同数の解き方) はコアが持っているので、
    // 一覧と同じ関数を通す。ここで performance_counts を自前にソートすると、
    // アプリの「披露回数順」と並びが食い違う。
    let top_songs: Vec<Ref> = super::lists::brand_top_song_indexes(ctx, brand_id)
        .iter()
        .take(TOP_N)
        .filter_map(|&i| ctx.song_ref(&ctx.snap.songs[i as usize].id))
        .collect();

    let counts = brand_counts(ctx, brand_id);
    // `other` は一覧の入口を作らない。既定フィルタが other を含めないというコアの規則と、
    // 一覧の入口が存在するという事実が食い違うため (到達は検索と個別ページから)。
    // id を URL に埋めるときは必ず url_segment を通す (ブランド id は今のところ
    // すべて ASCII だが、規則を 1 箇所に保たないと将来の id で静かに壊れる)。
    let segment = url_segment(brand_id);
    let brand_path = |collection: &str| format!("/{collection}/brand/{segment}/");
    let section_links = if ctx.is_other_brand(Some(brand_id)) {
        vec![nav("アイドル", &brand_path("idols"), &theme_key, counts.idols)]
    } else {
        vec![
            nav("ライブ", &brand_path("events"), &theme_key, counts.events),
            nav("楽曲", &brand_path("songs"), &theme_key, counts.songs),
            nav("アイドル", &brand_path("idols"), &theme_key, counts.idols),
            nav("ユニット", &brand_path("units"), &theme_key, counts.units),
        ]
    };

    let breadcrumbs = vec![
        ctx.crumb("ホーム", "/"),
        ctx.crumb("ブランド", "/brands/"),
        ctx.crumb(&brand.name, &path),
    ];

    Some(BrandPage {
        schema_version: SCHEMA_VERSION,
        id: brand.id.clone(),
        path: path.clone(),
        name: brand.name.clone(),
        short_name: Some(brand.short_name.clone()),
        theme_key,
        stat_tiles: brand_stat_tiles(counts),
        idols: idol_queries::idol_list(ctx.snap, Some(brand_id))
            .iter()
            .filter_map(|i| ctx.idol_ref(&i.id))
            .collect(),
        units: unit_queries::all_units(ctx.snap)
            .iter()
            .filter(|u| u.brand_id == brand_id)
            .filter_map(|u| ctx.unit_ref(&u.id))
            .collect(),
        recent_events,
        top_songs,
        section_links,
        seo: ctx.seo(
            &brand.name,
            &format!("{}のアイドル・ユニット・ライブ・楽曲。", brand.name),
            &path,
            Some(brand_id),
            serde_json::json!({
                        "@type": "CollectionPage",
                "name": brand.name,
                "url": content::absolute(&path),
            }),
            breadcrumbs,
        ),
    })
}

fn nav(label: &str, path: &str, theme_key: &str, count: u32) -> NavLink {
    NavLink {
        label: label.to_string(),
        path: path.to_string(),
        current: false,
        theme_key: Some(theme_key.to_string()),
        count: Some(count),
    }
}
