//! 実データの書き出し。
//!
//! 流れ: `db/master.sql` → 作業用 SQLite → [`Snapshot`] → domain 関数 → DTO → JSON。
//! 「今日」は入口で 1 回だけ確定し、以降の upcoming / past の分割はすべてその 1 個から
//! 決まる (Astro もブラウザも `Date` を触らない)。

pub mod context;
pub mod events;
pub mod idols;
pub mod lists;
pub mod places;
pub mod search;
pub mod songs;

use super::dto::*;
use super::writer::Writer;
use super::{restore, theme, Args, Result, Stats, WebExportError};
use crate::domain::jst_day::jst_today;
use crate::domain::snapshot::Snapshot;
use crate::outbound::sqlite_loader::load_snapshot;
use context::Ctx;
use std::path::PathBuf;

/// ルート台帳を組み立てながら書き出す。
struct RouteBook {
    routes: Vec<RouteEntry>,
}

impl RouteBook {
    fn new() -> Self {
        Self { routes: Vec::new() }
    }

    /// params を取らないページ。
    fn listing(&mut self, kind: RouteKind, path: &str, data: &str, in_sitemap: bool) {
        self.routes.push(RouteEntry {
            path: path.to_string(),
            kind,
            key: None,
            id: None,
            data: data.to_string(),
            in_sitemap,
        });
    }

    /// params を取る一覧 (`key` に param の生値を入れる)。
    fn param_listing(&mut self, kind: RouteKind, path: &str, key: &str, data: &str, in_sitemap: bool) {
        self.routes.push(RouteEntry {
            path: path.to_string(),
            kind,
            key: Some(key.to_string()),
            id: None,
            data: data.to_string(),
            in_sitemap,
        });
    }

    /// 詳細ページ。
    fn detail(&mut self, kind: RouteKind, path: &str, key: &str, id: &str, data: &str, in_sitemap: bool) {
        self.routes.push(RouteEntry {
            path: path.to_string(),
            kind,
            key: Some(key.to_string()),
            id: Some(id.to_string()),
            data: data.to_string(),
            in_sitemap,
        });
    }

    fn finish(self) -> RoutesFile {
        let noindex_paths =
            self.routes.iter().filter(|r| !r.in_sitemap).map(|r| r.path.clone()).collect();
        RoutesFile { schema_version: SCHEMA_VERSION, routes: self.routes, noindex_paths }
    }
}

/// 一覧ページの `path` から、その一覧がどの `RouteKind` かを決める。
///
/// 一覧の種別は「Astro のルートファイル 1 本」に対応させてある。ここで取り違えると
/// `getStaticPaths` が params を取り出せなくなる。
fn list_kind_and_key(path: &str) -> (RouteKind, Option<String>) {
    let seg = |prefix: &str| path.strip_prefix(prefix).map(|r| r.trim_end_matches('/').to_string());
    if let Some(year) = seg("/events/past/") {
        if !year.is_empty() {
            return (RouteKind::EventListPastYear, Some(decode(&year)));
        }
        return (RouteKind::EventListPast, None);
    }
    if let Some(b) = seg("/events/brand/") {
        return (RouteKind::EventListBrand, Some(decode(&b)));
    }
    if let Some(b) = seg("/songs/brand/") {
        return (RouteKind::SongListBrand, Some(decode(&b)));
    }
    if let Some(b) = seg("/idols/brand/") {
        return (RouteKind::IdolListBrand, Some(decode(&b)));
    }
    if let Some(m) = seg("/idols/birth-month/") {
        return (RouteKind::IdolListBirthMonth, Some(decode(&m)));
    }
    if let Some(b) = seg("/units/brand/") {
        return (RouteKind::UnitListBrand, Some(decode(&b)));
    }
    if let Some(p) = seg("/venues/pref/") {
        return (RouteKind::VenueListPref, Some(decode(&p)));
    }
    match path {
        "/events/" => (RouteKind::EventListIndex, None),
        "/events/upcoming/" => (RouteKind::EventListUpcoming, None),
        "/songs/" => (RouteKind::SongListIndex, None),
        "/songs/all/" => (RouteKind::SongListAll, None),
        "/idols/" => (RouteKind::IdolListIndex, None),
        "/units/" => (RouteKind::UnitListIndex, None),
        "/venues/" => (RouteKind::VenueListIndex, None),
        "/brands/" => (RouteKind::BrandList, None),
        _ => (RouteKind::Home, None),
    }
}

/// `path` に載っているのは percent-encode 済みの値なので、params 用に戻す。
fn decode(segment: &str) -> String {
    let bytes = segment.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(byte) = u8::from_str_radix(&segment[i + 1..i + 3], 16) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| segment.to_string())
}

/// 実データを `out` に書き出す。
pub fn run(args: &Args) -> Result<Stats> {
    let out = args
        .out
        .clone()
        .ok_or_else(|| WebExportError::Args("--out が要る".into()))?;

    // 1) DB を用意する。
    let (db_path, content_hash) = match (&args.sql, &args.db) {
        (Some(sql), None) => {
            let work_db = args.work_db.clone().unwrap_or_else(|| default_work_db(&out));
            restore::restore(sql, &work_db)?;
            (work_db, Some(restore::content_hash(sql)?))
        }
        (None, Some(db)) => (db.clone(), None),
        _ => return Err(WebExportError::Args("--sql と --db のどちらか一方が要る".into())),
    };

    let snap: Snapshot = load_snapshot(
        db_path.to_str().ok_or_else(|| WebExportError::Db("DB パスが UTF-8 でない".into()))?,
    )
    .map_err(|e| WebExportError::Db(e.to_string()))?;

    // 2) 「今日」をここで 1 回だけ確定する。
    let today = match &args.today {
        Some(t) => {
            validate_ymd(t)?;
            t.clone()
        }
        None => {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            jst_today(now)
        }
    };
    // 生成時刻も `today` から作る。実時刻を入れると同じ入力でも出力が毎回変わり、
    // 「2 回流してバイト一致」で再現性を確かめられなくなる。
    let generated_at = format!("{today}T00:00:00Z");

    let ctx = Ctx::new(&snap, today, generated_at, content_hash);
    write_all(&ctx, &out, args.pretty)
}

fn default_work_db(out: &std::path::Path) -> PathBuf {
    out.parent().unwrap_or(std::path::Path::new(".")).join(".cache/master-web.sqlite")
}

fn validate_ymd(text: &str) -> Result<()> {
    let ok = text.len() == 10
        && text.as_bytes()[4] == b'-'
        && text.as_bytes()[7] == b'-'
        && text.bytes().enumerate().all(|(i, b)| i == 4 || i == 7 || b.is_ascii_digit());
    if ok {
        Ok(())
    } else {
        Err(WebExportError::Args(format!("--today は YYYY-MM-DD 形式: {text}")))
    }
}

fn write_all(ctx: &Ctx, out: &std::path::Path, pretty: bool) -> Result<Stats> {
    let mut w = Writer::create(out, pretty)?;
    let mut book = RouteBook::new();

    // --- テーマ ---
    let (idol_inputs, brand_inputs) = ctx.theme_inputs();
    let table = theme::build_table(&idol_inputs, &brand_inputs);
    w.write_json("themes.json", &table)?;
    // 単一の themes.css。HTML は data-theme 属性を 1 個置くだけでよくなる。
    w.write_text("themes.css", &theme::build_css(&table))?;

    // --- 詳細ページ ---
    for event in &ctx.snap.events {
        if let Some(page) = events::event_page(ctx, &event.id) {
            let data = ctx.data_path(RefKind::Event, &event.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Event,
                &page.path,
                &ctx.key("events", &event.id),
                &event.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }
    for show in &ctx.snap.shows {
        if let Some(page) = events::show_page(ctx, &show.id) {
            let data = ctx.data_path(RefKind::Show, &show.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Show,
                &page.path,
                &ctx.key("shows", &show.id),
                &show.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }
    for song in &ctx.snap.songs {
        if let Some(page) = songs::song_page(ctx, &song.id) {
            let data = ctx.data_path(RefKind::Song, &song.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Song,
                &page.path,
                &ctx.key("songs", &song.id),
                &song.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }
    for idol in &ctx.snap.idols {
        if let Some(page) = idols::idol_page(ctx, &idol.id) {
            let data = ctx.data_path(RefKind::Idol, &idol.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Idol,
                &page.path,
                &ctx.key("idols", &idol.id),
                &idol.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }
    for unit in &ctx.snap.units {
        if let Some(page) = idols::unit_page(ctx, &unit.id) {
            let data = ctx.data_path(RefKind::Unit, &unit.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Unit,
                &page.path,
                &ctx.key("units", &unit.id),
                &unit.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }
    let directory = places::VenueDirectory::load(ctx);
    for venue in &ctx.snap.venues {
        if let Some(page) = places::venue_page(ctx, &venue.id, &directory) {
            let data = ctx.data_path(RefKind::Venue, &venue.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Venue,
                &page.path,
                &ctx.key("venues", &venue.id),
                &venue.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }
    for brand in &ctx.snap.brands {
        if let Some(page) = places::brand_page(ctx, &brand.id) {
            let data = ctx.data_path(RefKind::Brand, &brand.id);
            w.write_json(&data, &page)?;
            book.detail(
                RouteKind::Brand,
                &page.path,
                &ctx.key("brands", &brand.id),
                &brand.id,
                &data,
                page.seo.robots == Robots::IndexFollow,
            );
        }
    }

    // --- 一覧 ---
    macro_rules! write_lists {
        ($items:expr) => {
            for item in $items {
                w.write_json(&item.data, &item.page)?;
                let (kind, key) = list_kind_and_key(&item.path);
                let in_sitemap = item.page.seo.robots == Robots::IndexFollow;
                match key {
                    Some(k) => book.param_listing(kind, &item.path, &k, &item.data, in_sitemap),
                    None => book.listing(kind, &item.path, &item.data, in_sitemap),
                }
            }
        };
    }
    write_lists!(lists::event_lists(ctx));
    write_lists!(lists::song_lists(ctx));
    write_lists!(lists::idol_lists(ctx));
    write_lists!(lists::unit_lists(ctx));
    write_lists!(lists::venue_lists(ctx));

    let brands = lists::brand_list(ctx);
    w.write_json("index/brands.json", &brands)?;
    book.listing(RouteKind::BrandList, "/brands/", "index/brands.json", true);

    let counts = lists::counts(ctx);
    let upcoming = lists::upcoming_items(ctx);
    let home = lists::home(ctx, &upcoming, counts);
    w.write_json("index/home.json", &home)?;
    book.listing(RouteKind::Home, "/", "index/home.json", true);

    let about = lists::about(ctx, counts);
    w.write_json("index/about.json", &about)?;
    book.listing(RouteKind::About, "/about/", "index/about.json", true);

    // --- 検索 ---
    let shards = search::shards(ctx);
    for shard in &shards {
        w.write_json(&format!("search/{}.json", shard.file), &shard.shard)?;
    }
    w.write_json("search/manifest.json", &search::manifest(&shards))?;
    book.listing(RouteKind::Search, "/search/", "search/manifest.json", true);

    w.write_json("parity/fold.json", &search::fold_parity(ctx))?;

    // --- メタとルート台帳 ---
    w.write_json(
        "meta.json",
        &SiteMeta {
            schema_version: SCHEMA_VERSION,
            generated_at: ctx.generated_at.clone(),
            today_jst: ctx.today.clone(),
            data_version: ctx.data_version.clone(),
            content_hash: ctx.content_hash.clone(),
            counts,
            app: crate::web_export::content::app_links(),
        },
    )?;

    let routes = book.finish();
    for _ in 0..routes.routes.len() {
        w.count_page();
    }
    w.write_json("routes.json", &routes)?;

    let mut stats = w.into_stats();
    stats.fallback_slugs = ctx.fallback_slugs;
    stats.fallback_unsafe = ctx.fallback_unsafe;
    stats.fallback_too_long = ctx.fallback_too_long;
    Ok(stats)
}
