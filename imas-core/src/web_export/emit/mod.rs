//! 実データの書き出し。
//!
//! 流れ: `db/master.sql` → 作業用 SQLite → [`Snapshot`] → domain 関数 → DTO → JSON。
//! 「今日」は入口で 1 回だけ確定し、以降の upcoming / past の分割はすべてその 1 個から
//! 決まる (Astro もブラウザも `Date` を触らない)。

pub mod song_filters;
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
    //
    // 7 コレクションで手順が同じ (ページを組む → 書く → ルート台帳に載せる)。
    // 違うのは「どの一覧を回すか」と「どの関数でページを組むか」だけなので、
    // その 2 つだけを渡す。コピペで並べると 1 つだけ `in_sitemap` の判定を
    // 書き忘れる、といった壊れ方をする。
    macro_rules! write_details {
        ($kind:expr, $route:expr, $rows:expr, $page:expr) => {
            for id in $rows {
                let Some(page) = $page(&id) else { continue };
                let data = ctx.data_path($kind, &id);
                w.write_json(&data, &page)?;
                book.detail(
                    $route,
                    &page.path,
                    ctx.expect_key($kind, &id),
                    &id,
                    &data,
                    page.seo.robots == Robots::IndexFollow,
                );
            }
        };
    }

    let ids = |f: fn(&Snapshot) -> Vec<String>| f(ctx.snap);
    write_details!(RefKind::Event, RouteKind::Event, ids(|s| s.events.iter().map(|e| e.id.clone()).collect()), |id: &String| events::event_page(ctx, id));
    write_details!(RefKind::Show, RouteKind::Show, ids(|s| s.shows.iter().map(|x| x.id.clone()).collect()), |id: &String| events::show_page(ctx, id));
    write_details!(RefKind::Song, RouteKind::Song, ids(|s| s.songs.iter().map(|x| x.id.clone()).collect()), |id: &String| songs::song_page(ctx, id));
    write_details!(RefKind::Idol, RouteKind::Idol, ids(|s| s.idols.iter().map(|x| x.id.clone()).collect()), |id: &String| idols::idol_page(ctx, id));
    write_details!(RefKind::Unit, RouteKind::Unit, ids(|s| s.units.iter().map(|x| x.id.clone()).collect()), |id: &String| idols::unit_page(ctx, id));
    let directory = places::VenueDirectory::load(ctx);
    write_details!(RefKind::Venue, RouteKind::Venue, ids(|s| s.venues.iter().map(|x| x.id.clone()).collect()), |id: &String| places::venue_page(ctx, id, &directory));
    write_details!(RefKind::Brand, RouteKind::Brand, ids(|s| s.brands.iter().map(|x| x.id.clone()).collect()), |id: &String| places::brand_page(ctx, id));

    // --- 一覧 ---
    // 一覧は「どのルートか」を作る側が知っている (Emitted が持っている) ので、
    // ここで path から逆算しない。
    macro_rules! write_lists {
        ($items:expr) => {
            for item in $items {
                w.write_json(&item.data, &item.page)?;
                for (path, value) in &item.extra {
                    w.write_json(path, value)?;
                }
                let in_sitemap = item.page.seo.robots == Robots::IndexFollow;
                match &item.param_key {
                    Some(key) => {
                        book.param_listing(item.route_kind, &item.path, key, &item.data, in_sitemap)
                    }
                    None => book.listing(item.route_kind, &item.path, &item.data, in_sitemap),
                }
            }
        };
    }
    let event_pages = lists::event_lists(ctx);
    let upcoming = lists::upcoming_items(&event_pages);
    write_lists!(event_pages);
    write_lists!(lists::song_lists(ctx));
    write_lists!(lists::idol_lists(ctx));
    write_lists!(lists::unit_lists(ctx));
    write_lists!(lists::venue_lists(ctx));

    let brands = lists::brand_list(ctx);
    w.write_json("index/brands.json", &brands)?;
    book.listing(RouteKind::BrandList, "/brands/", "index/brands.json", true);

    let counts = lists::counts(ctx);
    let home = lists::home(ctx, &upcoming, counts);
    w.write_json("index/home.json", &home)?;
    book.listing(RouteKind::Home, "/", "index/home.json", true);

    let about = lists::about(ctx, counts);
    w.write_json("index/about.json", &about)?;
    book.listing(RouteKind::About, "/about/", "index/about.json", true);

    // --- 検索 ---
    let shards = search::shards(ctx);
    for shard in &shards {
        // 既にシリアライズ済みの本文をそのまま書く (manifest の bytes と同じもの)。
        w.write_text(&format!("search/{}.json", shard.file), &shard.json)?;
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
    w.count_pages(routes.routes.len());
    w.write_json("routes.json", &routes)?;

    let mut stats = w.into_stats();
    stats.fallback_slugs = ctx.fallback_slugs;
    stats.fallback_unsafe = ctx.fallback_unsafe;
    stats.fallback_too_long = ctx.fallback_too_long;
    Ok(stats)
}
