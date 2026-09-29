//! ランキング (`/ranking/` と `/ranking/brand/<id>/`)。
//!
//! 数えるのは `domain::stats_queries` (アプリの「調べる」と同じ関数) で、ここは並べるだけ。

use super::context::Ctx;
use super::lists::{brand_links, collection_json_ld, Emitted};
use crate::domain::stats_queries::{
    brand_song_counts, cast_show_count_ranking_in, share_permille, song_play_count_ranking_in,
    yearly_show_counts_in,
};
use crate::web_export::content;
use crate::web_export::dto::*;

pub const PATH: &str = "/ranking/";
const TITLE: &str = "ランキング";
/// 何位まで出すか (アプリの「調べる」の既定と同じ)。
const TOP_N: u32 = 20;

pub fn ranking_pages(ctx: &Ctx) -> Vec<Emitted<RankingPage>> {
    let mut out = vec![page(ctx, None, PATH.to_string(), "index/ranking.json".to_string())];
    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        let Some(path) = ctx.brand_list_path("ranking", &brand.id) else { continue };
        let data = format!("index/ranking-brand-{}.json", Ctx::param_key(&brand.id));
        out.push(page(ctx, Some(&brand.id), path, data));
    }
    out
}

fn page(ctx: &Ctx, brand_id: Option<&str>, path: String, data: String) -> Emitted<RankingPage> {
    let songs = ranked(
        song_play_count_ranking_in(ctx.snap, brand_id, TOP_N)
            .into_iter()
            .filter_map(|r| Some((ctx.song_ref(&r.id)?, r.play_count))),
        "回",
    );
    let idols = ranked(
        cast_show_count_ranking_in(ctx.snap, brand_id, TOP_N)
            .into_iter()
            .filter_map(|r| Some((ctx.idol_ref(&r.id)?, r.show_count))),
        "公演",
    );
    // ブランドのページでは出さない (1 本だけの棒は何も言わない)。
    let brand_songs = if brand_id.is_some() {
        Vec::new()
    } else {
        let rows: Vec<(Ref, u32)> = brand_song_counts(ctx.snap)
            .into_iter()
            .filter(|b| b.song_count > 0 && !ctx.is_other_brand(Some(&b.id)))
            .filter_map(|b| Some((ctx.brand_ref(&b.id)?, b.song_count)))
            .collect();
        let max = rows.iter().map(|r| r.1).max().unwrap_or(0);
        rows.into_iter()
            .map(|(reference, value)| RankRow {
                rank: None,
                reference,
                value,
                unit: "曲".to_string(),
                share_permille: share_permille(value, max),
            })
            .collect()
    };

    let this_year = &ctx.today[..4.min(ctx.today.len())];
    let counts = yearly_show_counts_in(ctx.snap, brand_id);
    let max = counts.iter().map(|y| y.show_count).max().unwrap_or(0);
    let years: Vec<YearBar> = counts
        .into_iter()
        .map(|y| YearBar {
            short: y.year[y.year.len().saturating_sub(2)..].to_string(),
            share_permille: share_permille(y.show_count, max),
            is_planned: y.year.as_str() >= this_year,
            value: y.show_count,
            year: y.year,
        })
        .collect();
    let years_note = years.iter().any(|y| y.is_planned).then(|| content::ranking_years_note(this_year));

    let brand = brand_id.and_then(|b| ctx.snap.brand(b));
    let title = match brand {
        Some(b) => format!("{}のランキング", b.name),
        None => TITLE.to_string(),
    };
    let description = match brand {
        Some(b) => format!("{}でよく披露される曲、出演公演の多いアイドル、年ごとの公演数。", b.name),
        None => "アイドルマスターのライブでよく披露される曲、出演公演の多いアイドル、ブランド別の楽曲数、年ごとの公演数。".to_string(),
    };
    let mut crumbs = vec![Ctx::crumb("ホーム", "/")];
    if brand.is_some() {
        crumbs.push(Ctx::crumb(TITLE, PATH));
    }
    crumbs.push(Ctx::crumb(&title, &path));

    Emitted {
        path: path.clone(),
        data,
        route_kind: if brand_id.is_some() { RouteKind::RankingBrand } else { RouteKind::Ranking },
        param_key: brand_id.map(str::to_string),
        page: RankingPage {
            schema_version: SCHEMA_VERSION,
            path: path.clone(),
            title: title.clone(),
            lede: content::RANKING_LEDE.to_string(),
            scope: FilterAxis::new(content::FILTER_AXIS_BRAND, scope_links(ctx, &path)),
            songs,
            idols,
            brand_songs,
            years,
            years_note,
            seo: ctx.seo(&title, &description, &path, brand_id, collection_json_ld(&title, &path), crumbs),
        },
    }
}

/// すべて / ブランドごと。件数は付けない (何の件数でもない)。
fn scope_links(ctx: &Ctx, current: &str) -> Vec<NavLink> {
    let mut links = brand_links(ctx, "ranking", current, "すべて", 0);
    for l in &mut links {
        l.count = None;
    }
    links
}

/// 上から順位を振り、1 位に対する棒の長さを付ける。
fn ranked(rows: impl Iterator<Item = (Ref, u32)>, unit: &str) -> Vec<RankRow> {
    let rows: Vec<(Ref, u32)> = rows.collect();
    let max = rows.first().map(|r| r.1).unwrap_or(0);
    rows.into_iter()
        .enumerate()
        .map(|(i, (reference, value))| RankRow {
            rank: Some(i as u32 + 1),
            reference,
            value,
            unit: unit.to_string(),
            share_permille: share_permille(value, max),
        })
        .collect()
}
