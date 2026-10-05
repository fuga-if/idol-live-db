//! 配信のアーカイブ (見逃し配信) の期間を、ライブ横断で扱う規則。純粋ロジック。
//!
//! 期間そのものは公演の券種 (`show_tickets.archive_starts_at` / `archive_ends_at`) が持つ。
//! 券種 1 枚の表示 (価格の行に添える「アーカイブ 9/28 18:00〜10/5 23:59・公開中」) は
//! [`crate::domain::ticket_prices::ticket_archive`] が決め、ここはそれを**ライブ一覧の
//! 「見られるアーカイブ」とカレンダーの帯**のためにまとめ直す。
//!
//! # まとめ方
//!
//! 同じ公演に期間の同じ券種が並ぶ (DAY1 のみ / 2 日通し / 機能利用料違い…) ので、
//! **同じライブで期間 (始まり・終わりの生値) が同じ券種は 1 つの「窓」にまとめる**。
//! 窓は対象の公演を束ね、`DAY1・DAY2` のように公演の短い名を添える。
//!
//! # 端の扱い
//!
//! 日時の解釈と両端を含む判定は受付 ([`crate::domain::ticket_sales`]) と同じ。
//! 始まりが無い窓は、対象公演の最初の日 (00:00) から見られるものとして扱う
//! (公演より前に「見られる」と出さない)。終わりが無い窓は出さない (いつまでも
//! 「見られる」に居座り、帯も引けないため)。

use chrono::{NaiveDate, NaiveDateTime};
use std::collections::BTreeMap;

use crate::domain::show_naming::distinguishing_show_name;
use crate::domain::snapshot::Snapshot;
use crate::domain::ticket_sales::{lower_bound, moment_label, now_naive, parse_sale_moment, remaining_label, upper_bound, Moment};

/// ライブ一覧の「見られるアーカイブ」の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OpenArchive {
    pub event_id: String,
    pub event_name: String,
    /// ライブのブランド色 (行頭の帯)。
    pub brand_color: Option<String>,
    /// 対象の公演 (日付順)。
    pub show_ids: Vec<String>,
    /// 対象公演の短い名 (`DAY1` 等)。公演が 1 つしかないライブでは空。
    pub show_labels: Vec<String>,
    /// `"9/28 (日) 18:00 〜 10/5 (月) 23:59"`。
    pub period_label: String,
    /// `"10/5 (月) 23:59 まで"`。
    pub ends_label: String,
    /// `"今日まで"` / `"明日まで"` / `"あと 8 日"`。
    pub remaining_label: String,
}

/// カレンダーの帯 1 本ぶんの窓 ([`crate::domain::calendar_queries`] が使う)。
pub(crate) struct ArchiveWindow {
    pub event: u32,
    /// 対象の公演 (shows の添字、日付順)。
    pub shows: Vec<u32>,
    pub start: Moment,
    pub end: Moment,
}

/// ライブ横断で、期間の同じ券種をまとめた窓。並びはライブの添字 → 始まり → 終わり。
pub(crate) fn archive_windows(snap: &Snapshot) -> Vec<ArchiveWindow> {
    // (event, 始まりの生値, 終わりの生値) → 公演の添字。
    let mut groups: BTreeMap<(u32, Option<&str>, Option<&str>), Vec<u32>> = BTreeMap::new();
    for row in &snap.show_archives {
        let event = snap.shows[row.show as usize].event;
        let key = (event, row.archive_starts_at.as_deref(), row.archive_ends_at.as_deref());
        let shows = groups.entry(key).or_default();
        if !shows.contains(&row.show) {
            shows.push(row.show);
        }
    }
    let mut windows: Vec<ArchiveWindow> = groups
        .into_iter()
        .filter_map(|((event, starts, ends), mut shows)| {
            shows.sort_by(|&a, &b| {
                let (sa, sb) = (&snap.shows[a as usize], &snap.shows[b as usize]);
                (&sa.date, sa.sort_order, a).cmp(&(&sb.date, sb.sort_order, b))
            });
            let end = ends.and_then(parse_sale_moment)?;
            let start = match starts.and_then(parse_sale_moment) {
                Some(s) => s,
                None => {
                    let first = &snap.shows[shows[0] as usize].date;
                    (NaiveDate::parse_from_str(first, "%Y-%m-%d").ok()?, None)
                }
            };
            (lower_bound(start) <= upper_bound(end)).then_some(ArchiveWindow { event, shows, start, end })
        })
        .collect();
    windows.sort_by(|a, b| (a.event, lower_bound(a.start), upper_bound(a.end)).cmp(&(b.event, lower_bound(b.start), upper_bound(b.end))));
    windows
}

/// 窓の対象公演の短い名。公演が 1 つしかないライブでは空 (ライブ名だけで足りる)。
pub(crate) fn window_show_labels(snap: &Snapshot, window: &ArchiveWindow) -> Vec<String> {
    if snap.shows_by_event[window.event as usize].len() <= 1 {
        return Vec::new();
    }
    let event_name = &snap.events[window.event as usize].name;
    window
        .shows
        .iter()
        .map(|&si| {
            let show = &snap.shows[si as usize];
            distinguishing_show_name(event_name, &show.name).unwrap_or(&show.name).to_string()
        })
        .collect()
}

/// カレンダーの帯に出す表示文字列 (`"{event_name} (DAY1・DAY2 アーカイブ)"`)。受付の帯
/// ([`crate::domain::ticket_sales::calendar_sale_label`]) と同じ「ライブ名 (何の期間)」の組み方。
pub fn calendar_archive_label(event_name: &str, show_labels: &[String]) -> String {
    if show_labels.is_empty() {
        format!("{event_name} (アーカイブ)")
    } else {
        format!("{event_name} ({} アーカイブ)", show_labels.join("・"))
    }
}

/// いま見られるアーカイブ (ライブ一覧の頭に出す)。終わりの近い順。
pub fn open_archives(snap: &Snapshot, now_epoch_seconds: i64) -> Vec<OpenArchive> {
    let now = now_naive(now_epoch_seconds);
    let today = now.date();
    let mut rows: Vec<(NaiveDateTime, OpenArchive)> = archive_windows(snap)
        .into_iter()
        .filter(|w| lower_bound(w.start) <= now && now <= upper_bound(w.end))
        .map(|w| {
            let event = &snap.events[w.event as usize];
            let brand_color = event.brand_id.as_deref().and_then(|b| snap.brand(b)).and_then(|b| b.color.clone());
            let show_labels = window_show_labels(snap, &w);
            let record = OpenArchive {
                event_id: event.id.clone(),
                event_name: event.name.clone(),
                brand_color,
                show_ids: w.shows.iter().map(|&si| snap.shows[si as usize].id.clone()).collect(),
                show_labels,
                period_label: format!("{} 〜 {}", moment_label(w.start.0, w.start.1), moment_label(w.end.0, w.end.1)),
                ends_label: format!("{} まで", moment_label(w.end.0, w.end.1)),
                remaining_label: remaining_label(w.end.0, today),
            };
            (upper_bound(w.end), record)
        })
        .collect();
    rows.sort_by(|a, b| {
        (a.0, a.1.event_name.as_str(), &a.1.show_ids).cmp(&(b.0, b.1.event_name.as_str(), &b.1.show_ids))
    });
    rows.into_iter().map(|(_, r)| r).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Event, Show, ShowArchiveRow};
    use crate::domain::snapshot_build::{build, RawTables};

    fn jst_epoch(s: &str) -> i64 {
        let at = NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M").unwrap();
        at.and_utc().timestamp() - 9 * 3600
    }

    fn event(id: &str, name: &str) -> Event {
        Event {
            id: id.into(),
            brand_id: None,
            name: name.into(),
            name_kana: None,
            event_type: "live".into(),
            is_streaming: false,
            is_solo: true,
            kind: "live".into(),
            ticket_url: None,
            joint_brand_ids: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn show(id: &str, event: u32, name: &str, date: &str) -> Show {
        Show {
            id: id.into(),
            event,
            name: name.into(),
            date: date.into(),
            venue: None,
            venue_city: None,
            start_time: None,
            sort_order: 0,
            performer_type: None,
            venue_id: None,
            hall: None,
            stream_platform: None,
            venue_mode: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn archive(ticket_id: &str, show: u32, starts: Option<&str>, ends: Option<&str>) -> ShowArchiveRow {
        ShowArchiveRow {
            ticket_id: ticket_id.into(),
            show,
            archive_starts_at: starts.map(Into::into),
            archive_ends_at: ends.map(Into::into),
        }
    }

    fn snapshot(events: Vec<Event>, shows: Vec<Show>, archives: Vec<ShowArchiveRow>) -> Snapshot {
        build(RawTables {
            songs: vec![],
            idols: vec![],
            events,
            units: vec![],
            brands: vec![],
            creators: vec![],
            venues: vec![],
            staff: vec![],
            anniversaries: vec![],
            meta: Default::default(),
            shows,
            setlist_items: vec![],
            venue_names: vec![],
            venue_halls: vec![],
            idol_voice_actors: vec![],
            event_releases: vec![],
            costumes: vec![],
            costume_wears: vec![],
            ticket_sales: vec![],
            show_archives: archives,
            song_artists: vec![],
            setlist_performers: vec![],
            show_cast: vec![],
            unit_members: vec![],
            idol_brands: vec![],
        })
    }

    /// MSP 型: 2 日公演で、DAY1 のみ・DAY2 のみ・通しの券種が同じ期間を持つ。
    fn msp() -> Snapshot {
        snapshot(
            vec![event("ev_msp", "MSP")],
            vec![show("sh1", 0, "MSP DAY1", "2026-09-27"), show("sh2", 0, "MSP DAY2", "2026-09-28")],
            vec![
                archive("t_day1", 0, Some("2026-09-28 18:00"), Some("2026-10-05 23:59")),
                archive("t_set_day1", 0, Some("2026-09-28 18:00"), Some("2026-10-05 23:59")),
                archive("t_day2", 1, Some("2026-09-28 18:00"), Some("2026-10-05 23:59")),
            ],
        )
    }

    #[test]
    fn same_period_tickets_fold_into_one_window() {
        let snap = msp();
        let windows = archive_windows(&snap);
        assert_eq!(windows.len(), 1);
        assert_eq!(windows[0].shows, vec![0, 1]);
        assert_eq!(window_show_labels(&snap, &windows[0]), vec!["DAY1", "DAY2"]);
        assert_eq!(calendar_archive_label("MSP", &window_show_labels(&snap, &windows[0])), "MSP (DAY1・DAY2 アーカイブ)");
    }

    #[test]
    fn open_archives_cover_both_ends_inclusive() {
        let snap = msp();
        assert!(open_archives(&snap, jst_epoch("2026-09-28 17:59")).is_empty(), "始まる前は出さない");
        let open = open_archives(&snap, jst_epoch("2026-10-05 23:59"));
        assert_eq!(open.len(), 1);
        assert_eq!(open[0].remaining_label, "今日まで");
        assert_eq!(open[0].ends_label, "10/5 (月) 23:59 まで");
        assert_eq!(open[0].period_label, "9/28 (月) 18:00 〜 10/5 (月) 23:59");
        assert_eq!(open[0].show_ids, vec!["sh1", "sh2"]);
        assert!(open_archives(&snap, jst_epoch("2026-10-06 00:00")).is_empty(), "終わったら出さない");
        assert_eq!(open_archives(&snap, jst_epoch("2026-10-01 12:00"))[0].remaining_label, "あと 4 日");
    }

    #[test]
    fn different_periods_stay_separate_and_sort_by_end() {
        let snap = snapshot(
            vec![event("ev_a", "A"), event("ev_b", "B")],
            vec![show("a1", 0, "A", "2026-09-20"), show("b1", 1, "B DAY1", "2026-09-21"), show("b2", 1, "B DAY2", "2026-09-22")],
            vec![
                archive("ta", 0, Some("2026-09-21"), Some("2026-10-10")),
                archive("tb1", 1, Some("2026-09-22"), Some("2026-10-03")),
                archive("tb2", 2, Some("2026-09-23"), Some("2026-10-04")),
            ],
        );
        let open = open_archives(&snap, jst_epoch("2026-10-01 00:00"));
        let names: Vec<(&str, &[String])> = open.iter().map(|o| (o.event_name.as_str(), o.show_labels.as_slice())).collect();
        assert_eq!(names.len(), 3);
        assert_eq!(names[0], ("B", &["DAY1".to_string()][..]));
        assert_eq!(names[1], ("B", &["DAY2".to_string()][..]));
        assert_eq!(names[2].0, "A");
        assert!(names[2].1.is_empty(), "公演が 1 つのライブは短い名を付けない");
        assert_eq!(open[2].ends_label, "10/10 (土) まで", "日付だけの終わりは時刻を付けない");
    }

    #[test]
    fn missing_start_falls_back_to_first_show_and_missing_end_is_dropped() {
        let snap = snapshot(
            vec![event("ev", "E")],
            vec![show("s", 0, "E", "2026-10-10")],
            vec![archive("t1", 0, None, Some("2026-10-17")), archive("t2", 0, Some("2026-10-11"), None)],
        );
        let windows = archive_windows(&snap);
        assert_eq!(windows.len(), 1, "終わりの無い窓は出さない");
        assert_eq!(lower_bound(windows[0].start), NaiveDate::from_ymd_opt(2026, 10, 10).unwrap().and_hms_opt(0, 0, 0).unwrap());
        assert!(open_archives(&snap, jst_epoch("2026-10-09 23:59")).is_empty(), "公演より前は見られない");
        assert_eq!(open_archives(&snap, jst_epoch("2026-10-10 00:00")).len(), 1);
    }

    #[test]
    fn broken_or_reversed_periods_are_dropped() {
        let snap = snapshot(
            vec![event("ev", "E")],
            vec![show("s", 0, "E", "2026-10-10")],
            vec![archive("t1", 0, Some("10月11日"), Some("あとで")), archive("t2", 0, Some("2026-10-20"), Some("2026-10-12"))],
        );
        assert!(archive_windows(&snap).is_empty());
    }
}
