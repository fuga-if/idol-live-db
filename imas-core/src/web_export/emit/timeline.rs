//! 年表 (`/timeline/` と `/timeline/brand/<id>/`)。
//!
//! 図の座標は `domain::timeline_chart` が決める。ここは DTO に写すだけ。

use super::context::Ctx;
use super::lists::{brand_links, collection_json_ld, Emitted};
use crate::domain::timeline_chart::{milestone_date_display, timeline_chart, ChartLaneKind, TimelineChart};
use crate::web_export::content;
use crate::web_export::dto::*;

pub const PATH: &str = "/timeline/";
const TITLE: &str = "年表";
/// 年の枠がこれより狭いと、目盛りを下 2 桁にする。
const SHORT_YEAR_BELOW: f64 = 40.0;

pub fn timeline_pages(ctx: &Ctx) -> Vec<Emitted<TimelinePage>> {
    let mut out: Vec<_> = page(ctx, None, PATH.to_string(), "index/timeline.json".to_string()).into_iter().collect();
    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        let Some(path) = ctx.brand_list_path("timeline", &brand.id) else { continue };
        let data = format!("index/timeline-brand-{}.json", Ctx::param_key(&brand.id));
        out.extend(page(ctx, Some(&brand.id), path, data));
    }
    out
}

fn r1(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

fn page(ctx: &Ctx, brand_id: Option<&str>, path: String, data: String) -> Option<Emitted<TimelinePage>> {
    let chart = timeline_chart(ctx.snap, brand_id, &ctx.today)?;
    let this_year = &ctx.today[..4.min(ctx.today.len())];

    let year_lives = chart
        .lives_in(this_year)
        .into_iter()
        .filter_map(|l| {
            Some(TimelineLiveRow {
                date_display: short_date(&l.date),
                event: ctx.event_ref(&l.event_id)?,
                chip: l.featured.then(|| content::TIMELINE_FEATURED_CHIP.to_string()),
            })
        })
        .collect();
    let year_milestones = chart
        .milestones_in(this_year)
        .into_iter()
        .map(|m| TimelineMilestoneRow { date_display: short_date(&m.date), label: m.label.clone() })
        .collect();
    let legend = chart
        .lanes
        .iter()
        .map(|l| TimelineLegend { label: l.kind.label().to_string(), note: l.kind.note().to_string() })
        .collect();

    let brand = brand_id.and_then(|b| ctx.snap.brand(b));
    let title = match brand {
        Some(b) => format!("{}の年表", b.name),
        None => TITLE.to_string(),
    };
    let description = match brand {
        Some(b) => format!("{}の節目・ライブ・楽曲を 1 本の時間軸で。", b.name),
        None => "アイドルマスターの節目・ライブ・楽曲を 1 本の時間軸で。".to_string(),
    };
    let mut crumbs = vec![Ctx::crumb("ホーム", "/")];
    if brand.is_some() {
        crumbs.push(Ctx::crumb(TITLE, PATH));
    }
    crumbs.push(Ctx::crumb(&title, &path));
    let mut scope = brand_links(ctx, "timeline", &path, "すべて", 0);
    for l in &mut scope {
        l.count = None;
    }

    Some(Emitted {
        path: path.clone(),
        data,
        route_kind: if brand_id.is_some() { RouteKind::TimelineBrand } else { RouteKind::Timeline },
        param_key: brand_id.map(str::to_string),
        page: TimelinePage {
            schema_version: SCHEMA_VERSION,
            path: path.clone(),
            title: title.clone(),
            lede: content::TIMELINE_LEDE.to_string(),
            scope: FilterAxis::new(content::FILTER_AXIS_BRAND, scope),
            chart: chart_dto(ctx, &chart),
            legend,
            year_lives_title: format!("{this_year}年のライブ"),
            year_lives,
            year_milestones_title: format!("{this_year}年の節目"),
            year_milestones,
            seo: ctx.seo(&title, &description, &path, brand_id, collection_json_ld(&title, &path), crumbs),
        },
    })
}

/// 一覧の日付 (`9.26`)。
fn short_date(date: &str) -> String {
    let full = milestone_date_display(date);
    full.split_once('.').map(|(_, md)| md.to_string()).unwrap_or(full)
}

fn chart_dto(ctx: &Ctx, c: &TimelineChart) -> TimelineChartDto {
    TimelineChartDto {
        width: r1(c.width),
        height: r1(c.height),
        gutter: r1(c.gutter),
        ruler_height: r1(c.ruler_height),
        years: c
            .years
            .iter()
            .map(|y| TimelineYearTick {
                year: y.year,
                label: if y.width < SHORT_YEAR_BELOW { format!("{:02}", y.year % 100) } else { y.year.to_string() },
                x: r1(y.x),
                width: r1(y.width),
                label_x: r1(y.x + y.width / 2.0),
            })
            .collect(),
        lanes: c
            .lanes
            .iter()
            .map(|l| TimelineLaneBand {
                label: l.kind.label().to_string(),
                y: r1(l.y),
                height: r1(l.height),
                // 節目・ライブは段の上に、楽曲は棒の足もとの高さに揃えない (段の上端から読む)。
                label_y: r1(l.y + if l.kind == ChartLaneKind::Live { l.height / 2.0 + 5.0 } else { 22.0 }),
            })
            .collect(),
        milestones: c
            .milestones
            .iter()
            .map(|m| TimelineMilestoneMark {
                x: r1(m.x),
                y: r1(m.y),
                date_display: milestone_date_display(&m.date),
                label: m.label.clone(),
                theme_key: (!m.brand_id.is_empty()).then(|| ctx.brand_theme(Some(&m.brand_id))),
                text_x: r1(if m.flip { m.x - 8.0 } else { m.x + 8.0 }),
                flip: m.flip,
                date_y: r1(m.y + 4.0),
                label_y: r1(m.y + 19.0),
            })
            .collect(),
        lives: c
            .lives
            .iter()
            .filter_map(|l| {
                let event = ctx.event_ref(&l.event_id)?;
                Some(TimelineLiveDot {
                    x: r1(l.x),
                    y: r1(l.y),
                    r: r1(l.r),
                    title: format!("{} ({})", l.title, milestone_date_display(&l.date)),
                    path: event.path,
                    featured: l.featured,
                    theme_key: event.theme_key,
                })
            })
            .collect(),
        releases: c
            .releases
            .iter()
            .map(|r| TimelineReleaseBar {
                year: r.year,
                count: r.count,
                x: r1(r.x),
                y: r1(r.y),
                width: r1(r.width),
                height: r1(r.height),
                label_x: r1(r.x + r.width / 2.0),
                label_y: r1(r.y + r.height + 13.0),
            })
            .collect(),
        today_x: c.today_x.map(r1),
    }
}
