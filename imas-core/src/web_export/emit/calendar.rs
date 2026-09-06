//! カレンダー (`/calendar/`, `/calendar/<YYYY-MM>/`)。
//!
//! 何をどの日に出すか (公演・リリース・誕生日・記念日・チケット) は
//! `domain::calendar_queries` — アプリのカレンダーと同じ 1 本。ここは月の枠 (週 × 7 日) に
//! 流し込み、リンクと文言を付けるだけ。月ごとに 1 枚の静的ページで、`/calendar/` は
//! 今月の写し (正規 URL は月のページ)。範囲は最初の公演の月から、最後の公演か今日の月まで
//! 連続して作る (空の月も、前後の月へ辿れるように枠だけ出す)。

use super::context::{distinguishing_show_name, join_parts, simple_json_ld, Ctx};
use super::lists::{list_crumbs, Emitted, SiteList};
use crate::domain::calendar_queries::{
    anniversary_years, calendar_entries, CalendarEntryRecord, CalendarTicketKind,
};
use crate::domain::short_year_month::ymd_components;
use crate::domain::stats_queries::monthly_show_counts;
use crate::web_export::content;
use crate::web_export::dto::*;
use chrono::{Datelike, Duration, Months, NaiveDate};
use std::collections::BTreeMap;
use std::iter::successors;

pub const CALENDAR_PATH: &str = "/calendar/";
/// 枠の 1 日に出す件数。残りは `+N` で示し、下の一覧に全部出す。
pub const GRID_ITEMS: usize = 3;

pub fn month_path(key: &str) -> String {
    format!("/calendar/{key}/")
}

/// `YYYY-MM…` → (年, 月)。読めない日付は無視する。
fn year_month(date: &str) -> Option<(i32, u32)> {
    let parts = ymd_components(date);
    let year = parts.first()?.parse().ok()?;
    let month: u32 = parts.get(1)?.parse().ok()?;
    (1..=12).contains(&month).then_some((year, month))
}

fn month_key(date: NaiveDate) -> String {
    format!("{:04}-{:02}", date.year(), date.month())
}

/// 1 か月ぶんの (最初の日, 最後の日)。
fn month_bounds(year: i32, month: u32) -> Option<(NaiveDate, NaiveDate)> {
    let first = NaiveDate::from_ymd_opt(year, month, 1)?;
    let last = first.checked_add_months(Months::new(1))?.pred_opt()?;
    Some((first, last))
}

/// 作る月の列と、切替に添える数。
struct MonthRange {
    /// `YYYY-MM` の連続した列 (昇順)。
    months: Vec<String>,
    show_counts: BTreeMap<String, u32>,
    today_key: String,
    /// 年の切替 (範囲内の年だけ。押すとその年の最初の月)。`current` はページごとに付け直す。
    years: Vec<NavLink>,
}

/// カレンダーの全ページ。先頭が `/calendar/` (今月の写し)。
pub fn calendar_pages(ctx: &Ctx) -> Vec<Emitted<CalendarPage>> {
    let show_counts = monthly_show_counts(ctx.snap);
    let (Some(first), Some(today)) = (show_counts.keys().next(), year_month(&ctx.today)) else {
        return vec![];
    };
    let (Some(start), Some(today_first)) = (
        year_month(first).and_then(|(y, m)| NaiveDate::from_ymd_opt(y, m, 1)),
        NaiveDate::from_ymd_opt(today.0, today.1, 1),
    ) else {
        return vec![];
    };
    let today_key = month_key(today_first);
    let last_key = today_key.clone().max(show_counts.keys().next_back().cloned().unwrap_or_default());
    let months: Vec<String> = successors(Some(start), |d| d.checked_add_months(Months::new(1)))
        .map(month_key)
        .take_while(|k| *k <= last_key)
        .collect();
    let years = months
        .chunk_by(|a, b| a[..4] == b[..4])
        .map(|chunk| {
            let count: u32 = chunk.iter().filter_map(|k| show_counts.get(k)).sum();
            NavLink::new(&chunk[0][..4], month_path(&chunk[0])).with_count(count)
        })
        .collect();
    let range = MonthRange { months, show_counts, today_key, years };

    let mut out: Vec<Emitted<CalendarPage>> =
        (0..range.months.len()).filter_map(|i| month_page(ctx, i, &range)).collect();

    // 今月の写し。正規 URL は月のページ (同じ中身を 2 つ索引させない)。
    if let Some(current) = out.iter().find(|p| p.param_key.as_deref() == Some(&range.today_key)) {
        let mut page = current.page.clone();
        page.path = CALENDAR_PATH.to_string();
        page.seo = ctx.seo(
            content::CALENDAR_TITLE,
            content::CALENDAR_DESCRIPTION,
            CALENDAR_PATH,
            None,
            simple_json_ld("CollectionPage", content::CALENDAR_TITLE, CALENDAR_PATH),
            list_crumbs(SiteList::Calendar, content::CALENDAR_TITLE, CALENDAR_PATH),
        );
        page.seo.canonical = content::absolute(&month_path(&range.today_key));
        out.insert(
            0,
            Emitted {
                path: CALENDAR_PATH.to_string(),
                data: "index/calendar.json".to_string(),
                route_kind: RouteKind::CalendarIndex,
                param_key: None,
                page,
            },
        );
    }
    out
}

/// 日ごとの予定と、日を跨ぐ帯。
#[derive(Default)]
struct MonthEntries {
    items: BTreeMap<String, Vec<CalendarItem>>,
    bands: BTreeMap<String, Vec<CalendarBand>>,
}

fn collect_month(ctx: &Ctx, first: NaiveDate, last: NaiveDate) -> MonthEntries {
    let mut out = MonthEntries::default();
    // ライブの押し先と色 (チケットの予定はライブに紐付く)。
    let event_link = |event_id: &str| {
        let brand = ctx.snap.event(event_id).and_then(|e| e.brand_id.clone());
        (ctx.event_ref(event_id).map(|e| e.path), ctx.brand_theme(brand.as_deref()))
    };
    for entry in calendar_entries(ctx.snap, &first.to_string(), &last.to_string()) {
        let (date, item) = match entry {
            CalendarEntryRecord::Show { show_id, name, date, venue, event_name, brand_id, .. } => {
                let Some(show) = ctx.show_ref(&show_id) else { continue };
                let sub = join_parts([distinguishing_show_name(&event_name, &name).map(str::to_string), venue]);
                let theme = ctx.brand_theme(brand_id.as_deref());
                (date, CalendarItem {
                    sub,
                    path: Some(show.path),
                    ..CalendarItem::new(CalendarItemKind::Show, content::CALENDAR_KIND_SHOW, event_name, theme)
                })
            }
            CalendarEntryRecord::Release { date, song_ids } => {
                let refs: Vec<Ref> = song_ids.iter().filter_map(|id| ctx.song_ref(id)).collect();
                if refs.is_empty() {
                    continue;
                }
                let label = content::calendar_release_label(refs.len());
                (date, CalendarItem {
                    refs,
                    ..CalendarItem::new(CalendarItemKind::Release, content::CALENDAR_KIND_RELEASE, label, ctx.brand_theme(None))
                })
            }
            CalendarEntryRecord::Birthday { idol_id, occurs_on } => {
                let Some(idol) = ctx.idol_ref(&idol_id) else { continue };
                (occurs_on, CalendarItem {
                    sub: idol.sub,
                    path: Some(idol.path),
                    ..CalendarItem::new(CalendarItemKind::Birthday, content::CALENDAR_KIND_BIRTHDAY, idol.name, idol.theme_key)
                })
            }
            CalendarEntryRecord::StaffBirthday { staff_id, occurs_on } => {
                let Some(staff) = ctx.snap.staff.iter().find(|s| s.id == staff_id) else { continue };
                let theme = ctx.brand_theme(Some(&staff.brand_id));
                (occurs_on, CalendarItem {
                    sub: staff.role.clone(),
                    ..CalendarItem::new(CalendarItemKind::Birthday, content::CALENDAR_KIND_BIRTHDAY, staff.name.clone(), theme)
                })
            }
            CalendarEntryRecord::Anniversary { anniversary_id, occurs_on } => {
                let Some(ann) = ctx.snap.anniversaries.iter().find(|a| a.id == anniversary_id) else { continue };
                let label = content::anniversary_display(&ann.label, anniversary_years(&ann.date, &occurs_on));
                let theme = ctx.brand_theme(Some(&ann.brand_id));
                (occurs_on, CalendarItem {
                    path: ctx.brand_ref(&ann.brand_id).map(|b| b.path),
                    ..CalendarItem::new(CalendarItemKind::Anniversary, content::CALENDAR_KIND_ANNIVERSARY, label, theme)
                })
            }
            CalendarEntryRecord::Ticket { event_id, event_name, date, kind, .. } => {
                let (path, theme) = event_link(&event_id);
                let kind_label = match kind {
                    CalendarTicketKind::Deadline => content::CALENDAR_KIND_TICKET_DEADLINE,
                    CalendarTicketKind::Lottery => content::CALENDAR_KIND_TICKET_LOTTERY,
                };
                (date, CalendarItem { path, ..CalendarItem::new(CalendarItemKind::Ticket, kind_label, event_name, theme) })
            }
            CalendarEntryRecord::TicketPeriod { event_id, event_name, start, end, .. } => {
                let (path, theme) = event_link(&event_id);
                let (Some(s), Some(e)) = (
                    NaiveDate::parse_from_str(&start, "%Y-%m-%d").ok(),
                    NaiveDate::parse_from_str(&end, "%Y-%m-%d").ok(),
                ) else {
                    continue;
                };
                for day in s.max(first).iter_days().take_while(|d| *d <= e.min(last)) {
                    out.bands.entry(day.to_string()).or_default().push(CalendarBand {
                        label: event_name.clone(),
                        theme_key: theme.clone(),
                        starts: day == s,
                        ends: day == e,
                        path: path.clone(),
                    });
                }
                if !(first..=last).contains(&s) {
                    continue;
                }
                (start, CalendarItem { path, ..CalendarItem::new(CalendarItemKind::Ticket, content::CALENDAR_KIND_TICKET_OPEN, event_name, theme) })
            }
        };
        out.items.entry(date).or_default().push(item);
    }
    out
}

/// 週 × 7 日の枠 (日曜始まり)。月の外の日は枠を揃えるためだけに入る。代表値も同じ枠を使う。
pub fn month_grid(
    first: NaiveDate,
    last: NaiveDate,
    today: &str,
    items: &BTreeMap<String, Vec<CalendarItem>>,
    bands: &BTreeMap<String, Vec<CalendarBand>>,
) -> Vec<CalendarWeek> {
    let grid_start = first - Duration::days(i64::from(first.weekday().num_days_from_sunday()));
    let grid_end = last + Duration::days(i64::from(6 - last.weekday().num_days_from_sunday()));
    let cells: Vec<CalendarDay> = grid_start
        .iter_days()
        .take_while(|d| *d <= grid_end)
        .map(|d| {
            let date = d.to_string();
            let all = items.get(&date).map(Vec::as_slice).unwrap_or(&[]);
            CalendarDay {
                day: d.day(),
                in_month: (first..=last).contains(&d),
                is_today: date == today,
                items: all.iter().take(GRID_ITEMS).cloned().collect(),
                overflow_label: (all.len() > GRID_ITEMS)
                    .then(|| content::calendar_overflow_label(all.len() - GRID_ITEMS)),
                bands: bands.get(&date).cloned().unwrap_or_default(),
                date,
            }
        })
        .collect();
    cells.chunks(7).map(|week| CalendarWeek { days: week.to_vec() }).collect()
}

fn month_page(ctx: &Ctx, index: usize, range: &MonthRange) -> Option<Emitted<CalendarPage>> {
    let key = &range.months[index];
    let (year, month) = year_month(key)?;
    let (first, last) = month_bounds(year, month)?;
    let entries = collect_month(ctx, first, last);
    let weeks = month_grid(first, last, &ctx.today, &entries.items, &entries.bands);
    let days: Vec<CalendarDayGroup> = entries
        .items
        .into_iter()
        .map(|(date, items)| CalendarDayGroup { date_badge: DateBadge::from_ymd(&date), items })
        .collect();
    let count = |kind: CalendarItemKind| days.iter().flat_map(|g| &g.items).filter(|i| i.kind == kind).count() as u32;
    let release_songs: u32 = days.iter().flat_map(|g| &g.items).map(|i| i.refs.len() as u32).sum();

    let path = month_path(key);
    // 年・月の切替。今の年の札はこのページを指すので `mark_current` が現在地として拾う。
    let year_prefix = &key[..4];
    let mut year_links: Vec<NavLink> = range
        .years
        .iter()
        .cloned()
        .map(|mut link| {
            if link.label == year_prefix {
                link.path = path.clone();
            }
            link
        })
        .collect();
    mark_current(&mut year_links, &path);
    let mut month_links: Vec<NavLink> = range
        .months
        .iter()
        .filter(|k| k.starts_with(year_prefix))
        .filter_map(|k| {
            let (_, m) = year_month(k)?;
            Some(NavLink::new(&format!("{m}月"), month_path(k)).with_count(range.show_counts.get(k).copied().unwrap_or(0)))
        })
        .collect();
    mark_current(&mut month_links, &path);
    let neighbour = |i: usize| {
        let k = range.months.get(i)?;
        let (y, m) = year_month(k)?;
        Some(NavLink::new(&content::calendar_month_title(y, m), month_path(k)))
    };

    let title = content::calendar_month_title(year, month);
    Some(Emitted {
        path: path.clone(),
        data: format!("index/calendar-{key}.json"),
        route_kind: RouteKind::CalendarMonth,
        param_key: Some(key.clone()),
        page: CalendarPage {
            schema_version: SCHEMA_VERSION,
            path: path.clone(),
            seo: ctx.seo(
                &title,
                &content::calendar_month_description(year, month, count(CalendarItemKind::Show)),
                &path,
                None,
                simple_json_ld("CollectionPage", &title, &path),
                list_crumbs(SiteList::Calendar, &title, &path),
            ),
            title,
            lede: content::CALENDAR_LEDE.to_string(),
            stat_tiles: nonzero_tiles([
                SiteList::Shows.tile(count(CalendarItemKind::Show), None),
                StatTile::new("♬", release_songs, content::CALENDAR_TILE_RELEASES),
                StatTile::new("☺", count(CalendarItemKind::Birthday), content::CALENDAR_KIND_BIRTHDAY),
                StatTile::new("◆", count(CalendarItemKind::Anniversary), content::CALENDAR_KIND_ANNIVERSARY),
            ]),
            prev: index.checked_sub(1).and_then(neighbour),
            next: neighbour(index + 1),
            today_link: (*key != range.today_key).then(|| NavLink::new(content::CALENDAR_TODAY_LINK, CALENDAR_PATH)),
            year_links,
            month_links,
            weekday_labels: content::CALENDAR_WEEKDAYS.iter().map(|w| w.to_string()).collect(),
            weeks,
            days,
        },
    })
}
