//! 会場 (venue) とブランド (brand) の詳細ページ。

use super::context::{join_parts, simple_json_ld, Ctx};
use super::events::shows_at_venue;
use super::idols::period_display;
use crate::domain::event_detail_queries as detail;
use crate::domain::event_list_queries;
use crate::domain::idol_queries;
use crate::domain::snapshot::Snapshot;
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url::split_csv;
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

        // `venue_names` は**現在の名前も 1 行として持つ**。234 会場中 233 会場は
        // その 1 行だけなので、そのまま配ると「旧称」の見出しの下に現在名が 1 つ
        // 並ぶ (しかも期間が両端とも空なので値が `—` になる)。
        //
        // 旧称として意味があるのは「名前が変わったことがある会場」だけなので、
        // 名称履歴が 2 件以上ある会場に絞り、そのうえで現在名の行を落とす。
        let mut grouped: BTreeMap<String, Vec<_>> = BTreeMap::new();
        for n in directory.names {
            grouped.entry(n.venue_id.clone()).or_default().push(n);
        }
        let mut names_by_venue: BTreeMap<String, Vec<VenueNameRow>> = BTreeMap::new();
        for (venue_id, rows) in grouped {
            if rows.len() < 2 {
                continue;
            }
            let current = ctx.snap.venue(&venue_id).map(|v| v.name.as_str());
            let past: Vec<VenueNameRow> = rows
                .into_iter()
                .filter(|n| Some(n.name.as_str()) != current)
                .map(|n| VenueNameRow {
                    period_display: period_display(n.valid_from.as_deref(), n.valid_to.as_deref()),
                    name: n.name,
                    start_date: n.valid_from,
                    end_date: n.valid_to,
                })
                .collect();
            if !past.is_empty() {
                names_by_venue.insert(venue_id, past);
            }
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
    let location_display = location_display(venue.prefecture.as_deref(), venue.city.as_deref());
    let place = location_display.clone().unwrap_or_default();
    let aliases_display = join_parts(split_csv(venue.aliases.as_deref()).map(Some));

    let breadcrumbs = vec![
        Ctx::crumb("ホーム", "/"),
        Ctx::crumb("会場", "/venues/"),
        Ctx::crumb(&venue.name, &path),
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
            simple_json_ld("Place", &venue.name, &path),
            breadcrumbs,
        ),
    })
}

/// 所在地の表記 (`"千葉県 千葉市美浜区"`)。
///
/// 都道府県と市区町村の間だけは中黒ではなく空白。地名の 2 段は「別の項目」ではなく
/// 「1 つの住所」なので、項目の区切り ([`PARTS_SEPARATOR`]) とは意味が違う。
pub fn location_display(prefecture: Option<&str>, city: Option<&str>) -> Option<String> {
    let parts: Vec<&str> = [prefecture, city]
        .into_iter()
        .flatten()
        .filter(|s| !s.is_empty())
        .collect();
    (!parts.is_empty()).then(|| parts.join(" "))
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

/// 全ブランドの件数を **1 パスで**数える。
///
/// ブランドごとに全表を舐めると、9 ブランド × 5 コレクション (計 7,278 行) を
/// ブランドページ・トップ・`/brands/` のそれぞれで数え直すことになる。
/// 作るのは 1 度きりで、[`Ctx`] が持ち回る。
pub fn brand_counts_table(snap: &Snapshot) -> BTreeMap<String, BrandCounts> {
    let mut table: BTreeMap<String, BrandCounts> =
        snap.brands.iter().map(|b| (b.id.clone(), BrandCounts::default())).collect();
    let mut bump = |brand: Option<&str>, f: fn(&mut BrandCounts)| {
        if let Some(counts) = brand.and_then(|b| table.get_mut(b)) {
            f(counts);
        }
    };
    for event in &snap.events {
        bump(event.brand_id.as_deref(), |c| c.events += 1);
    }
    for show in &snap.shows {
        bump(snap.events[show.event as usize].brand_id.as_deref(), |c| c.shows += 1);
    }
    for song in &snap.songs {
        bump(song.brand_id.as_deref(), |c| c.songs += 1);
    }
    for idol in &snap.idols {
        bump(idol.brand_id.as_deref(), |c| c.idols += 1);
    }
    for unit in &snap.units {
        bump(Some(unit.brand_id.as_str()), |c| c.units += 1);
    }
    table
}

/// ブランドページの入口リンク。件数付きで、そのブランドの各一覧へ飛ばす。
///
/// **一覧を作っていない組み合わせは並べない。**どの組み合わせが存在するかの判断は
/// [`Ctx::brand_list_path`] が 1 箇所で持つ (かつて 6 箇所に散っていて、パンくずだけ
/// 判断を持たずに存在しないページへリンクしていた)。
fn brand_section_links(ctx: &Ctx, brand_id: &str, counts: BrandCounts) -> Vec<NavLink> {
    let theme_key = ctx.brand_theme(Some(brand_id));
    [
        ("ライブ", "events", counts.events),
        ("楽曲", "songs", counts.songs),
        ("アイドル", "idols", counts.idols),
        ("ユニット", "units", counts.units),
    ]
    .into_iter()
    .filter_map(|(label, collection, count)| {
        Some(NavLink {
            label: label.to_string(),
            path: ctx.brand_list_path(collection, brand_id)?,
            current: false,
            theme_key: Some(theme_key.clone()),
            count: Some(count),
        })
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

    let counts = ctx.brand_counts(brand_id);
    // `other` は一覧の入口を作らない。既定フィルタが other を含めないというコアの規則と、
    // 一覧の入口が存在するという事実が食い違うため (到達は検索と個別ページから)。
    let breadcrumbs = vec![
        Ctx::crumb("ホーム", "/"),
        Ctx::crumb("ブランド", "/brands/"),
        Ctx::crumb(&brand.name, &path),
    ];

    Some(BrandPage {
        schema_version: SCHEMA_VERSION,
        id: brand.id.clone(),
        path: path.clone(),
        name: brand.name.clone(),
        short_name: Some(brand.short_name.clone()),
        section_links: brand_section_links(ctx, brand_id, counts),
        theme_key,
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
        seo: ctx.seo(
            &brand.name,
            &format!("{}のアイドル・ユニット・ライブ・楽曲。", brand.name),
            &path,
            Some(brand_id),
            simple_json_ld("CollectionPage", &brand.name, &path),
            breadcrumbs,
        ),
    })
}
