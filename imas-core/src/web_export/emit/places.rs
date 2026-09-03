//! 会場 (venue) とブランド (brand) の詳細ページ。

use super::context::Ctx;
use super::events::shows_at_venue;
use crate::domain::event_detail_queries as detail;
use crate::domain::event_list_queries;
use crate::domain::idol_queries;
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;
use std::collections::BTreeMap;

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
    let place = [venue.prefecture.as_deref(), venue.city.as_deref()]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" ");

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
        capacity: venue.capacity.map(|c| c as i32),
        aliases: venue
            .aliases
            .as_deref()
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .collect(),
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

/// トップと `/brands/` に出す件数タイル用に、ブランド 1 件ぶんを数える。
pub fn brand_counts(ctx: &Ctx, brand_id: &str) -> Counts {
    let events = ctx.snap.events.iter().filter(|e| e.brand_id.as_deref() == Some(brand_id));
    let event_ids: std::collections::HashSet<&str> = events.map(|e| e.id.as_str()).collect();
    let shows = ctx
        .snap
        .shows
        .iter()
        .filter(|s| event_ids.contains(ctx.snap.events[s.event as usize].id.as_str()))
        .count();
    Counts {
        events: event_ids.len() as u32,
        shows: shows as u32,
        songs: ctx.snap.songs.iter().filter(|s| s.brand_id.as_deref() == Some(brand_id)).count()
            as u32,
        idols: ctx.snap.idols.iter().filter(|i| i.brand_id.as_deref() == Some(brand_id)).count()
            as u32,
        units: ctx.snap.units.iter().filter(|u| u.brand_id == brand_id).count() as u32,
        // 会場とブランドはブランドに紐付かないので、ここでは 0 にする
        // (ブランドページで「会場 0」と出さないよう、web 側は events/shows/songs/idols/units だけ見る)。
        venues: 0,
        brands: 0,
        setlist_items: 0,
    }
}

pub fn brand_page(ctx: &Ctx, brand_id: &str) -> Option<BrandPage> {
    let brand = ctx.brand(brand_id)?.clone();
    let path = ctx.path(RefKind::Brand, brand_id);
    let theme_key = ctx.brand_theme(Some(brand_id));

    // ブランドの最近のライブ (開催日の新しい順に 12 件)。
    let mut events = event_list_queries::events_with_first_date(
        ctx.snap,
        Some(brand_id),
        true,
        false,
        Some(&super::lists::all_event_kinds()),
    );
    events.sort_by(|a, b| b.first_date.cmp(&a.first_date).then(a.event.id.cmp(&b.event.id)));
    let recent_events: Vec<Ref> =
        events.iter().take(12).filter_map(|e| ctx.event_ref(&e.event.id)).collect();

    // 代表曲 = 披露回数の多い順。
    let mut songs: Vec<(u32, &str)> = ctx
        .snap
        .songs
        .iter()
        .enumerate()
        .filter(|(_, s)| s.brand_id.as_deref() == Some(brand_id))
        .map(|(i, s)| (ctx.snap.performance_counts[i], s.id.as_str()))
        .collect();
    songs.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(b.1)));
    let top_songs: Vec<Ref> =
        songs.iter().take(12).filter_map(|(_, id)| ctx.song_ref(id)).collect();

    let counts = brand_counts(ctx, brand_id);
    // `other` は一覧の入口を作らない。既定フィルタが other を含めないというコアの規則と、
    // 一覧の入口が存在するという事実が食い違うため (到達は検索と個別ページから)。
    let section_links = if ctx.is_other_brand(Some(brand_id)) {
        vec![nav("アイドル", &format!("/idols/brand/{brand_id}/"), &theme_key, counts.idols)]
    } else {
        vec![
            nav("ライブ", &format!("/events/brand/{brand_id}/"), &theme_key, counts.events),
            nav("楽曲", &format!("/songs/brand/{brand_id}/"), &theme_key, counts.songs),
            nav("アイドル", &format!("/idols/brand/{brand_id}/"), &theme_key, counts.idols),
            nav("ユニット", &format!("/units/brand/{brand_id}/"), &theme_key, counts.units),
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
        color: brand.color.clone(),
        theme_key,
        counts,
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
