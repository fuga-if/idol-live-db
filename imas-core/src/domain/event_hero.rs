//! イベント詳細のヒーロー (開催期間・会場・今後か・参加予定 / 参加済みの札)。
//!
//! 両 OS に写経されていた (iOS `EventDetailView.heroSub` / `isFutureEvent` /
//! `AttendanceStatus.derive`、Android `EventDetailUiState.heroSub` / `isFutureEvent` /
//! `EventDetailScreen.attendanceStatus`)。
//!
//! - 開催期間は Web のイベント詳細と同じ書式 ([`range_with_weekday`]、Q-08e)。
//! - 会場は、公演の会場名を並べて最初のもの (iOS `Set(venues).sorted().first` と同じ。
//!   Q-08e は書式だけの許可なので、選び方は変えない。空の会場名は数えない)。
//! - 参加マークが event 単位にしか無いときは、全公演の日付で判定する (Q-08d)。

use chrono::NaiveDate;

use crate::domain::date_display::range_with_weekday;
use crate::domain::event_grouping::is_upcoming_on;
use crate::domain::snapshot::Snapshot;

/// 参加マークから見たイベントの状態。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum AttendanceState {
    /// 参加マークが無い。
    None,
    /// 今日以降の参加公演がある。
    Planned,
    /// 参加公演がすべて過去。
    Attended,
}

/// 参加予定 / 参加済みの札。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct AttendanceStatusRecord {
    pub state: AttendanceState,
    /// 参加予定の公演まで何日か (0 = 今日)。日付が年・月までしか無い公演では `None`。
    pub days_until: Option<u32>,
    /// `参加予定・あと3日` / `参加予定・今日` / `参加予定` / `参加済み`。マークが無ければ空。
    pub label: String,
}

/// 参加公演の日付から札を決める。
///
/// - `attended_show_dates`: 参加マークのある公演の日付 (空文字は無視)。
/// - `event_show_dates`: そのイベントの全公演の日付。`attended_show_dates` が空で
///   `event_marked` (event 単位の参加マーク) が真なら、こちらで判定する。
/// - `today`: JST の今日 (`YYYY-MM-DD`)。「今日以降」は [`is_upcoming_on`] で決める。
pub fn attendance_status(
    attended_show_dates: &[String],
    event_show_dates: &[String],
    event_marked: bool,
    today: &str,
) -> AttendanceStatusRecord {
    let non_empty = |dates: &[String]| -> Vec<String> { dates.iter().filter(|d| !d.is_empty()).cloned().collect() };
    let mut dates = non_empty(attended_show_dates);
    if dates.is_empty() && event_marked {
        dates = non_empty(event_show_dates);
    }
    if dates.is_empty() {
        // event 単位のマークだけで公演が 1 つも無いイベントは「参加済み」とする
        // (日付で判断できないが、マークは付いている)。
        return if event_marked {
            status(AttendanceState::Attended, None)
        } else {
            status(AttendanceState::None, None)
        };
    }
    match dates.iter().filter(|d| is_upcoming_on(d, today)).min() {
        Some(nearest) => status(AttendanceState::Planned, days_between(today, nearest)),
        None => status(AttendanceState::Attended, None),
    }
}

fn status(state: AttendanceState, days_until: Option<u32>) -> AttendanceStatusRecord {
    let label = match (state, days_until) {
        (AttendanceState::None, _) => String::new(),
        (AttendanceState::Attended, _) => "参加済み".to_string(),
        (AttendanceState::Planned, Some(0)) => "参加予定・今日".to_string(),
        (AttendanceState::Planned, Some(d)) => format!("参加予定・あと{d}日"),
        (AttendanceState::Planned, None) => "参加予定".to_string(),
    };
    AttendanceStatusRecord { state, days_until, label }
}

/// `from` から `to` まで何日か (どちらも `YYYY-MM-DD`)。読めない日付は `None`、過去は 0。
fn days_between(from: &str, to: &str) -> Option<u32> {
    let parse = |d: &str| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok();
    let days = (parse(to)? - parse(from)?).num_days();
    Some(days.max(0) as u32)
}

/// イベント詳細のヒーロー。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventHeroRecord {
    /// 開催期間 (`2026-09-19 (土) 〜 2026-09-20 (日)`)。公演が無ければ `None`。
    pub date_display: Option<String>,
    /// 会場名を並べて最初のもの (会場名が入っている公演のうち。コードポイント順)。
    pub venue: Option<String>,
    /// ヒーローのサブ行 (開催期間 ・ 会場)。
    pub sub_line: String,
    /// 最初の公演が今日以降か (チケット情報を出すか・参加予定の札の根拠)。
    pub is_upcoming: bool,
    pub attendance: AttendanceStatusRecord,
}

/// イベント詳細のヒーローを組む。未知の event_id は `None`。
///
/// `attended_show_ids` は参加マークのある公演 (他のイベントの公演が混ざっていてもよい)、
/// `event_marked` は event 単位の参加マークがあるか。
pub fn event_hero(
    snap: &Snapshot,
    event_id: &str,
    attended_show_ids: &[String],
    event_marked: bool,
    today: &str,
) -> Option<EventHeroRecord> {
    let &event = snap.event_index_by_id.get(event_id)?;
    let shows: Vec<&crate::domain::snapshot::Show> =
        snap.shows_by_event[event as usize].iter().map(|&s| &snap.shows[s as usize]).collect();
    let dates: Vec<String> = shows.iter().map(|s| s.date.clone()).filter(|d| !d.is_empty()).collect();
    let date_display = range_with_weekday(dates.first().map(String::as_str), dates.last().map(String::as_str));
    let venue = shows.iter().filter_map(|s| s.venue.as_deref().filter(|v| !v.is_empty())).min().map(str::to_owned);
    let sub_line = [date_display.clone(), venue.clone()].into_iter().flatten().collect::<Vec<_>>().join(" ・ ");
    let is_upcoming = dates.first().is_some_and(|d| is_upcoming_on(d, today));
    let attended: Vec<String> = shows
        .iter()
        .filter(|s| attended_show_ids.contains(&s.id))
        .map(|s| s.date.clone())
        .collect();
    Some(EventHeroRecord {
        date_display,
        venue,
        sub_line,
        is_upcoming,
        attendance: attendance_status(&attended, &dates, event_marked, today),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn d(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    #[test]
    fn planned_counts_days_to_the_nearest_upcoming_show() {
        let s = attendance_status(&d(&["2026-09-20", "2026-09-26", "2026-09-27"]), &[], false, "2026-09-23");
        assert_eq!(s.state, AttendanceState::Planned);
        assert_eq!(s.days_until, Some(3));
        assert_eq!(s.label, "参加予定・あと3日");
        let today = attendance_status(&d(&["2026-09-23"]), &[], false, "2026-09-23");
        assert_eq!(today.label, "参加予定・今日");
    }

    #[test]
    fn all_past_is_attended_and_no_marks_is_none() {
        let s = attendance_status(&d(&["2026-09-01", ""]), &[], false, "2026-09-23");
        assert_eq!((s.state, s.label.as_str()), (AttendanceState::Attended, "参加済み"));
        let none = attendance_status(&[], &d(&["2026-10-01"]), false, "2026-09-23");
        assert_eq!((none.state, none.label.as_str()), (AttendanceState::None, ""));
    }

    #[test]
    fn event_only_mark_is_judged_by_every_show_date() {
        // Q-08d: 公演単位のマークが無く event 単位のマークだけなら、全公演の日付で決める。
        let s = attendance_status(&[], &d(&["2026-09-20", "2026-09-30"]), true, "2026-09-23");
        assert_eq!((s.state, s.days_until), (AttendanceState::Planned, Some(7)));
        let past = attendance_status(&[], &d(&["2026-09-20"]), true, "2026-09-23");
        assert_eq!(past.state, AttendanceState::Attended);
        // 公演単位のマークがあればそちらが優先。
        let show = attendance_status(&d(&["2026-09-20"]), &d(&["2026-09-20", "2026-09-30"]), true, "2026-09-23");
        assert_eq!(show.state, AttendanceState::Attended);
    }

    #[test]
    fn partial_dates_are_planned_without_a_day_count() {
        let s = attendance_status(&d(&["2026-12"]), &[], false, "2026-09-23");
        assert_eq!((s.state, s.days_until, s.label.as_str()), (AttendanceState::Planned, None, "参加予定"));
        let this_year = attendance_status(&d(&["2026"]), &[], false, "2026-09-23");
        assert_eq!(this_year.state, AttendanceState::Planned, "年だけの今年の公演は今後");
    }

    /// 公演の順で先に来る会場ではなく、会場名の並びで先のものを出す (L-2。iOS と同じ)。
    #[test]
    fn hero_venue_is_the_first_by_name_not_by_show_order() {
        let snap = bundle_snapshot();
        let (event, by_name) = snap
            .shows_by_event
            .iter()
            .enumerate()
            .find_map(|(e, shows)| {
                let venues: Vec<&str> =
                    shows.iter().filter_map(|&s| snap.shows[s as usize].venue.as_deref()).collect();
                let min = *venues.iter().min()?;
                (venues[0] != min).then(|| (e, min.to_owned()))
            })
            .expect("公演順の先頭と名前順の先頭が違うイベントがある");
        let hero = event_hero(snap, &snap.events[event].id, &[], false, "2000-01-01").unwrap();
        assert_eq!(hero.venue, Some(by_name));
    }

    #[test]
    fn hero_uses_the_web_range_and_the_first_venue_by_name() {
        let snap = bundle_snapshot();
        let (event, shows) = snap
            .shows_by_event
            .iter()
            .enumerate()
            .find(|(_, shows)| {
                shows.len() >= 2 && {
                    let first = &snap.shows[shows[0] as usize];
                    let last = &snap.shows[*shows.last().unwrap() as usize];
                    first.date != last.date && first.venue.is_some()
                }
            })
            .expect("複数日のイベントがある");
        let event_id = snap.events[event].id.clone();
        let first = &snap.shows[shows[0] as usize];
        let last = &snap.shows[*shows.last().unwrap() as usize];
        let hero = event_hero(snap, &event_id, &[], false, "2000-01-01").unwrap();
        assert_eq!(hero.date_display, range_with_weekday(Some(&first.date), Some(&last.date)));
        let by_name = shows.iter().filter_map(|&s| snap.shows[s as usize].venue.clone()).min();
        assert_eq!(hero.venue, by_name);
        assert_eq!(hero.sub_line, format!("{} ・ {}", hero.date_display.clone().unwrap(), by_name.unwrap()));
        assert!(hero.is_upcoming);
        assert_eq!(hero.attendance.state, AttendanceState::None);

        let marked = event_hero(snap, &event_id, std::slice::from_ref(&last.id), false, "9999-01-01").unwrap();
        assert_eq!(marked.attendance.state, AttendanceState::Attended);
        assert!(!marked.is_upcoming);
        assert!(event_hero(snap, "存在しない", &[], false, "2026-01-01").is_none());
    }
}
