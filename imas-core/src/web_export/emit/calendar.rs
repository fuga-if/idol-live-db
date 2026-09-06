//! カレンダー (`/calendar/`, `/calendar/<YYYY-MM>/`)。
//!
//! 何をどの日に出すか (公演・リリース・誕生日・記念日・チケット) は
//! `domain::calendar_queries` — アプリのカレンダーと同じ 1 本。ここは月の枠 (週 × 7 日) に
//! 流し込み、リンクと文言を付けるだけ。月ごとに 1 枚の静的ページで、`/calendar/` は
//! 今月の写し (正規 URL は月のページ)。範囲は最初の公演の月から、最後の公演か今日の月まで
//! 連続して作る (空の月も、前後の月へ辿れるように枠だけ出す)。

use super::context::{distinguishing_show_name, join_parts, simple_json_ld, Ctx};
use super::lists::Emitted;
use crate::domain::calendar_queries::{calendar_entries, CalendarEntryRecord, CalendarTicketKind};
use crate::web_export::content;
use crate::web_export::dto::*;
use chrono::{Datelike, Duration, Months, NaiveDate};
use std::collections::{BTreeMap, BTreeSet};

pub const CALENDAR_PATH: &str = "/calendar/";
/// 枠の 1 日に出す件数。残りは `+N` で示し、下の一覧に全部出す。
const GRID_ITEMS: usize = 3;

fn month_key(year: i32, month: u32) -> String {
    format!("{year:04}-{month:02}")
}

fn month_path(key: &str) -> String {
    format!("/calendar/{key}/")
}

/// `YYYY-MM…` → (年, 月)。読めない日付は無視する。
fn parse_month(text: &str) -> Option<(i32, u32)> {
    let year: i32 = text.get(0..4)?.parse().ok()?;
    let month: u32 = text.get(5..7)?.parse().ok()?;
    (1..=12).contains(&month).then_some((year, month))
}

fn next_month((year, month): (i32, u32)) -> (i32, u32) {
    if month == 12 { (year + 1, 1) } else { (year, month + 1) }
}

/// 1 か月ぶんの (最初の日, 最後の日)。
fn month_bounds(year: i32, month: u32) -> Option<(NaiveDate, NaiveDate)> {
    let first = NaiveDate::from_ymd_opt(year, month, 1)?;
    let last = first.checked_add_months(Months::new(1))?.pred_opt()?;
    Some((first, last))
}

/// カレンダーの全ページ。先頭が `/calendar/` (今月の写し)。
pub fn calendar_pages(ctx: &Ctx) -> Vec<Emitted<CalendarPage>> {
    // 月ごとの公演数 (年・月の切替に添える数)。
    let mut show_counts: BTreeMap<String, u32> = BTreeMap::new();
    for show in &ctx.snap.shows {
        if let Some((y, m)) = parse_month(&show.date) {
            *show_counts.entry(month_key(y, m)).or_default() += 1;
        }
    }
    let (Some(first), Some(today)) = (show_counts.keys().next().cloned(), parse_month(&ctx.today)) else {
        return vec![];
    };
    let today_key = month_key(today.0, today.1);
    let last = show_counts.keys().next_back().cloned().unwrap_or_default().max(today_key.clone());

    // 最初の月から最後の月まで連続した列。
    let mut months: Vec<String> = Vec::new();
    let mut cursor = parse_month(&first).unwrap_or(today);
    loop {
        let key = month_key(cursor.0, cursor.1);
        let done = key >= last;
        months.push(key);
        if done {
            break;
        }
        cursor = next_month(cursor);
    }
    let range = MonthRange { months, show_counts, today_key };

    let mut out: Vec<Emitted<CalendarPage>> = range
        .months
        .iter()
        .filter_map(|key| month_page(ctx, key, &range))
        .collect();

    // 今月の写し。正規 URL は月のページ (同じ中身を 2 つ索引させない)。
    if let Some(current) = out.iter().find(|p| p.page.month_key == range.today_key) {
        let mut page = current.page.clone();
        page.path = CALENDAR_PATH.to_string();
        page.today_link = None;
        page.seo = ctx.seo(
            content::CALENDAR_TITLE,
            content::CALENDAR_DESCRIPTION,
            CALENDAR_PATH,
            None,
            simple_json_ld("CollectionPage", content::CALENDAR_TITLE, CALENDAR_PATH),
            vec![Ctx::crumb("ホーム", "/"), Ctx::crumb(content::CALENDAR_TITLE, CALENDAR_PATH)],
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

struct MonthRange {
    months: Vec<String>,
    show_counts: BTreeMap<String, u32>,
    today_key: String,
}

/// 日ごとの予定と帯、この月の件数。
#[derive(Default)]
struct MonthEntries {
    items: BTreeMap<String, Vec<CalendarItem>>,
    bands: BTreeMap<String, Vec<CalendarBand>>,
    shows: u32,
    release_songs: u32,
    birthdays: u32,
    anniversaries: u32,
}

fn collect_month(ctx: &Ctx, first: NaiveDate, last: NaiveDate) -> MonthEntries {
    let mut out = MonthEntries::default();
    let first_text = first.to_string();
    let last_text = last.to_string();
    let mut push = |date: &str, item: CalendarItem| out.items.entry(date.to_string()).or_default().push(item);
    for entry in calendar_entries(ctx.snap, &first_text, &last_text) {
        match entry {
            CalendarEntryRecord::Show { show_id, name, date, venue, event_name, brand_id, .. } => {
                let Some(reference) = ctx.show_ref(&show_id) else { continue };
                out.shows += 1;
                push(
                    &date,
                    CalendarItem {
                        kind: CalendarItemKind::Show,
                        kind_label: content::CALENDAR_KIND_SHOW.to_string(),
                        sub: join_parts([
                            distinguishing_show_name(&event_name, &name).map(str::to_string),
                            venue,
                        ]),
                        label: event_name,
                        path: Some(reference.path),
                        theme_key: ctx.brand_theme(brand_id.as_deref()),
                        refs: vec![],
                    },
                );
            }
            CalendarEntryRecord::Release { date, song_ids } => {
                let refs: Vec<Ref> = song_ids.iter().filter_map(|id| ctx.song_ref(id)).collect();
                if refs.is_empty() {
                    continue;
                }
                out.release_songs += refs.len() as u32;
                push(
                    &date,
                    CalendarItem {
                        kind: CalendarItemKind::Release,
                        kind_label: content::CALENDAR_KIND_RELEASE.to_string(),
                        label: content::calendar_release_label(refs.len()),
                        sub: None,
                        path: None,
                        theme_key: ctx.brand_theme(None),
                        refs,
                    },
                );
            }
            CalendarEntryRecord::Birthday { idol_id, occurs_on } => {
                let Some(idol) = ctx.idol_ref(&idol_id) else { continue };
                out.birthdays += 1;
                push(
                    &occurs_on,
                    CalendarItem {
                        kind: CalendarItemKind::Birthday,
                        kind_label: content::CALENDAR_KIND_BIRTHDAY.to_string(),
                        label: idol.name,
                        sub: idol.sub,
                        path: Some(idol.path),
                        theme_key: idol.theme_key,
                        refs: vec![],
                    },
                );
            }
            CalendarEntryRecord::StaffBirthday { staff_id, occurs_on } => {
                let Some(staff) = ctx.snap.staff.iter().find(|s| s.id == staff_id) else { continue };
                out.birthdays += 1;
                push(
                    &occurs_on,
                    CalendarItem {
                        kind: CalendarItemKind::Birthday,
                        kind_label: content::CALENDAR_KIND_BIRTHDAY.to_string(),
                        label: staff.name.clone(),
                        sub: staff.role.clone(),
                        path: None,
                        theme_key: ctx.brand_theme(Some(&staff.brand_id)),
                        refs: vec![],
                    },
                );
            }
            CalendarEntryRecord::Anniversary { anniversary_id, occurs_on } => {
                let Some(ann) = ctx.snap.anniversaries.iter().find(|a| a.id == anniversary_id) else { continue };
                out.anniversaries += 1;
                let years = parse_month(&occurs_on).map(|(y, _)| y).unwrap_or(0)
                    - parse_month(&ann.date).map(|(y, _)| y).unwrap_or(0);
                push(
                    &occurs_on,
                    CalendarItem {
                        kind: CalendarItemKind::Anniversary,
                        kind_label: content::CALENDAR_KIND_ANNIVERSARY.to_string(),
                        label: content::anniversary_display(&ann.label, years),
                        sub: None,
                        path: ctx.brand_ref(&ann.brand_id).map(|b| b.path),
                        theme_key: ctx.brand_theme(Some(&ann.brand_id)),
                        refs: vec![],
                    },
                );
            }
            CalendarEntryRecord::Ticket { event_id, event_name, date, kind, .. } => {
                let brand = ctx.snap.event(&event_id).and_then(|e| e.brand_id.clone());
                let kind_label = match kind {
                    CalendarTicketKind::Deadline => content::CALENDAR_KIND_TICKET_DEADLINE,
                    CalendarTicketKind::Lottery => content::CALENDAR_KIND_TICKET_LOTTERY,
                };
                push(
                    &date,
                    CalendarItem {
                        kind: CalendarItemKind::Ticket,
                        kind_label: kind_label.to_string(),
                        label: event_name,
                        sub: None,
                        path: ctx.event_ref(&event_id).map(|e| e.path),
                        theme_key: ctx.brand_theme(brand.as_deref()),
                        refs: vec![],
                    },
                );
            }
            CalendarEntryRecord::TicketPeriod { event_id, event_name, start, end, .. } => {
                let brand = ctx.snap.event(&event_id).and_then(|e| e.brand_id.clone());
                let theme_key = ctx.brand_theme(brand.as_deref());
                let path = ctx.event_ref(&event_id).map(|e| e.path);
                let (Some(s), Some(e)) =
                    (NaiveDate::parse_from_str(&start, "%Y-%m-%d").ok(), NaiveDate::parse_from_str(&end, "%Y-%m-%d").ok())
                else {
                    continue;
                };
                let mut day = s.max(first);
                while day <= e.min(last) {
                    out.bands.entry(day.to_string()).or_default().push(CalendarBand {
                        label: event_name.clone(),
                        theme_key: theme_key.clone(),
                        starts: day == s,
                        ends: day == e,
                        path: path.clone(),
                    });
                    day += Duration::days(1);
                }
                if s >= first && s <= last {
                    push(
                        &start,
                        CalendarItem {
                            kind: CalendarItemKind::Ticket,
                            kind_label: content::CALENDAR_KIND_TICKET_OPEN.to_string(),
                            label: event_name,
                            sub: None,
                            path,
                            theme_key,
                            refs: vec![],
                        },
                    );
                }
            }
        }
    }
    out
}

fn month_page(ctx: &Ctx, key: &str, range: &MonthRange) -> Option<Emitted<CalendarPage>> {
    let (year, month) = parse_month(key)?;
    let (first, last) = month_bounds(year, month)?;
    let entries = collect_month(ctx, first, last);

    // 週の枠。日曜始まり (アプリと同じ)。
    let grid_start = first - Duration::days(i64::from(first.weekday().num_days_from_sunday()));
    let grid_end = last + Duration::days(i64::from(6 - last.weekday().num_days_from_sunday()));
    let mut weeks: Vec<CalendarWeek> = Vec::new();
    let mut day = grid_start;
    while day <= grid_end {
        let mut days = Vec::with_capacity(7);
        for _ in 0..7 {
            let date = day.to_string();
            let in_month = day >= first && day <= last;
            let all = if in_month { entries.items.get(&date).map(Vec::as_slice).unwrap_or(&[]) } else { &[] };
            days.push(CalendarDay {
                day: day.day(),
                in_month,
                is_today: date == ctx.today,
                weekday: day.weekday().num_days_from_sunday(),
                items: all.iter().take(GRID_ITEMS).cloned().collect(),
                overflow_label: (all.len() > GRID_ITEMS).then(|| content::calendar_overflow_label(all.len() - GRID_ITEMS)),
                bands: if in_month { entries.bands.get(&date).cloned().unwrap_or_default() } else { vec![] },
                date,
            });
            day += Duration::days(1);
        }
        weeks.push(CalendarWeek { days });
    }

    let days: Vec<CalendarDayGroup> = entries
        .items
        .iter()
        .map(|(date, items)| CalendarDayGroup { date_badge: DateBadge::from_ymd(date), items: items.clone() })
        .collect();

    let index = range.months.iter().position(|k| k == key)?;
    let nav = |k: &str| {
        let (y, m) = parse_month(k)?;
        Some(NavLink::new(&content::calendar_month_title(y, m), month_path(k)))
    };
    let in_range: BTreeSet<&str> = range.months.iter().map(String::as_str).collect();
    let year_of = |k: &str| parse_month(k).map(|(y, _)| y);
    let mut year_links: Vec<NavLink> = Vec::new();
    for k in &range.months {
        let Some(y) = year_of(k) else { continue };
        if year_links.last().is_some_and(|l| l.label == y.to_string()) {
            continue;
        }
        let count: u32 = range.show_counts.iter().filter(|(m, _)| year_of(m) == Some(y)).map(|(_, c)| c).sum();
        let mut link = NavLink::new(&y.to_string(), month_path(k)).with_count(count);
        link.current = y == year;
        year_links.push(link);
    }
    let month_links: Vec<NavLink> = (1..=12u32)
        .filter_map(|m| {
            let k = month_key(year, m);
            in_range.contains(k.as_str()).then(|| {
                let mut link = NavLink::new(&content::calendar_month_short(m), month_path(&k))
                    .with_count(range.show_counts.get(&k).copied().unwrap_or(0));
                link.current = m == month;
                link
            })
        })
        .collect();

    let title = content::calendar_month_title(year, month);
    let path = month_path(key);
    Some(Emitted {
        path: path.clone(),
        data: format!("index/calendar-{key}.json"),
        route_kind: RouteKind::CalendarMonth,
        param_key: Some(key.to_string()),
        page: CalendarPage {
            schema_version: SCHEMA_VERSION,
            path: path.clone(),
            seo: ctx.seo(
                &title,
                &content::calendar_month_description(year, month, entries.shows),
                &path,
                None,
                simple_json_ld("CollectionPage", &title, &path),
                vec![
                    Ctx::crumb("ホーム", "/"),
                    Ctx::crumb(content::CALENDAR_TITLE, CALENDAR_PATH),
                    Ctx::crumb(&title, &path),
                ],
            ),
            title,
            month_key: key.to_string(),
            lede: content::CALENDAR_LEDE.to_string(),
            stat_tiles: nonzero_tiles([
                StatTile::new("▤", entries.shows, content::CALENDAR_TILE_SHOWS),
                StatTile::new("♬", entries.release_songs, content::CALENDAR_TILE_RELEASES),
                StatTile::new("☺", entries.birthdays, content::CALENDAR_TILE_BIRTHDAYS),
                StatTile::new("◆", entries.anniversaries, content::CALENDAR_TILE_ANNIVERSARIES),
            ]),
            prev: index.checked_sub(1).and_then(|i| nav(&range.months[i])),
            next: range.months.get(index + 1).and_then(|k| nav(k)),
            today_link: (key != range.today_key).then(|| NavLink::new(content::CALENDAR_TODAY_LINK, CALENDAR_PATH)),
            year_links,
            month_links,
            weekday_labels: content::CALENDAR_WEEKDAYS.iter().map(|w| w.to_string()).collect(),
            weeks,
            days,
        },
    })
}
