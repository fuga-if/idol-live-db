//! 通知の予定表 (R-B-05): 担当アイドルの誕生日・月曜のミーム・ライブ 1 週間前・
//! チケットの申込締切と当落。
//!
//! 両 OS に写経されていた (iOS `NotificationService`、Android `NotificationPlanner`。
//! Android は「iOS の写経」と明記していた)。ここは**何をいつ出すか**だけを決める。
//! OS の通知の API (UNUserNotificationCenter / AlarmManager)・画像の添付・設定の保存先は各 OS。
//!
//! 守る決まり (§3-26):
//! - 予定表は毎回**全部消して積み直す**前提で、1 回ぶんを丸ごと返す。
//! - 上限 60 件。カテゴリ (誕生日 / 月曜 / ライブとチケット) の間は round-robin で配る
//!   (単純に繋いで先頭 60 件にすると、担当の多い人は誕生日が枠を食い尽くす)。
//!
//! 時刻は**端末のその地の暦** (日付 + 時・分) で返す。タイムゾーンへの換算は OS。
//!
//! 変えたところ:
//! - 誕生日は次の 1 回の日付に加えて `repeats_yearly` を返す。2/29 以外は真で、OS は今までどおり
//!   毎年くり返しで登録する (アプリを開かなくても翌年も鳴る。§3-26)。2/29 生まれだけ偽で、
//!   非閏年は 2/28 の 1 回を登録し、積み直しのたびに次の年へ進む (Q-08m。iOS の毎年くり返しは
//!   閏年にしか鳴らなかった)。
//! - 誕生日の並びは近い順 (上限で切られるなら遠い方から落ちる)。以前は取得順。
//! - 月曜のミームのレア抽選はシードで決める (同じシードなら両 OS で同じ出方)。

use chrono::{Datelike, NaiveDate};

use crate::domain::calendar_queries::month_day_in_year;
use crate::domain::prng::SplitMix64;
use crate::domain::snapshot::Snapshot;

/// 一度に積む通知の上限。
pub const MAX_SCHEDULED_NOTIFICATIONS: usize = 60;
/// 月曜のミームを積む週数。
pub const MONDAY_MEME_WEEKS: u32 = 8;
/// 月曜のミームのレア文言の確率 (1/500)。
pub const MONDAY_MEME_RARE_DENOMINATOR: u64 = 500;
/// 月曜のミームの主 (画像を添えるときの参照先)。
pub const CHIYOKO_IDOL_ID: &str = "sc_園田智代子";

const BIRTHDAY_HOUR: u32 = 9;
const MONDAY_HOUR: u32 = 20;
const LIVE_WEEK_HOUR: u32 = 10;
const TICKET_DEADLINE_HOUR: u32 = 18;
const LOTTERY_HOUR: u32 = 9;

/// 通知の種類 (設定の切り替えの単位)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum NotificationKind {
    OshiBirthday,
    Monday,
    LiveWeek,
    Ticket,
}

/// 予定表を組む材料。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct NotificationPlanInput {
    /// 端末のその地の今日 (`YYYY-MM-DD`)。
    pub today: String,
    /// 端末のその地の今の時刻 (0:00 からの分)。
    pub now_minutes: u32,
    pub birthday_enabled: bool,
    pub monday_enabled: bool,
    pub live_week_enabled: bool,
    pub ticket_enabled: bool,
    /// 担当アイドル (誕生日の対象)。
    pub pick_idol_ids: Vec<String>,
    /// お気に入り ∪ 参加マークのイベント (ライブ・チケットの対象)。
    pub event_ids: Vec<String>,
    /// 月曜のミームのレア抽選のシード。
    pub seed: u64,
}

/// 積む通知 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PlannedNotificationRecord {
    /// 通知の識別子 (`bday_<idol>` / `monday_meme_<n>` / `live_<event>` / `ticketdl_<event>` / `lottery_<event>`)。
    pub id: String,
    pub kind: NotificationKind,
    pub title: String,
    pub body: Option<String>,
    /// 鳴らす日 (端末のその地の暦、`YYYY-MM-DD`)。
    pub date: String,
    pub hour: u32,
    pub minute: u32,
    /// 添える画像の元になるアイドル (ユーザーが取り込んだ画像があれば)。
    pub image_idol_id: Option<String>,
    /// 毎年同じ月日・時刻にくり返してよいか。真なら OS は毎年くり返しのトリガで登録する
    /// (アプリを開かなくても翌年も鳴る)。2/29 生まれの誕生日は非閏年に 2/28 へ動くので偽 —
    /// `date` の 1 回だけを登録し、積み直しのたびに次の年へ進める。誕生日以外も偽。
    pub repeats_yearly: bool,
}

/// 予定表 1 回ぶん (上限 60 件、カテゴリ間は round-robin)。
pub fn notification_plan(snap: &Snapshot, input: &NotificationPlanInput) -> Vec<PlannedNotificationRecord> {
    let Some(today) = parse_day(&input.today) else { return Vec::new() };
    let now = (today, input.now_minutes);
    let birthdays = if input.birthday_enabled { birthday_plans(snap, &input.pick_idol_ids, now) } else { Vec::new() };
    let monday = if input.monday_enabled { monday_plans(now, input.seed) } else { Vec::new() };
    let events = event_plans(snap, &input.event_ids, input.live_week_enabled, input.ticket_enabled, today);
    round_robin_merge(vec![birthdays, monday, events], MAX_SCHEDULED_NOTIFICATIONS)
}

/// 複数の列を round-robin で 1 列に混ぜ、`cap` 件で打ち切る (各列の中の順は保つ)。
pub fn round_robin_merge<T>(groups: Vec<Vec<T>>, cap: usize) -> Vec<T> {
    let mut iters: Vec<std::vec::IntoIter<T>> = groups.into_iter().map(Vec::into_iter).collect();
    let mut out = Vec::new();
    loop {
        let mut took = false;
        for it in &mut iters {
            if out.len() >= cap {
                return out;
            }
            if let Some(item) = it.next() {
                out.push(item);
                took = true;
            }
        }
        if !took {
            return out;
        }
    }
}

type Moment = (NaiveDate, u32);

fn parse_day(value: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()
}

fn day_key(date: NaiveDate) -> String {
    date.format("%Y-%m-%d").to_string()
}

fn plan(id: String, kind: NotificationKind, title: String, body: Option<String>, at: Moment, image: Option<String>) -> PlannedNotificationRecord {
    PlannedNotificationRecord {
        id,
        kind,
        title,
        body,
        date: day_key(at.0),
        hour: at.1 / 60,
        minute: at.1 % 60,
        image_idol_id: image,
        repeats_yearly: false,
    }
}

/// その月日の誕生日を毎年くり返しで登録してよいか。2/29 だけは年によって日付が動く (非閏年は 2/28)。
fn repeats_yearly_for(month: u32, day: u32) -> bool {
    (month, day) != (2, 29)
}

/// `--MM-DD` (素の `MM-DD` も受ける) → (月, 日)。
fn birthday_month_day(raw: &str) -> Option<(u32, u32)> {
    let body = raw.strip_prefix("--").unwrap_or(raw);
    let mut parts = body.split('-').filter(|p| !p.is_empty());
    let month: u32 = parts.next()?.parse().ok()?;
    let day: u32 = parts.next()?.parse().ok()?;
    (parts.next().is_none() && (1..=12).contains(&month) && (1..=31).contains(&day)).then_some((month, day))
}

/// 担当アイドルの誕生日: 次に来る誕生日の 9:00。近い順 (同じ日はアイドルの並び順)。
fn birthday_plans(snap: &Snapshot, idol_ids: &[String], now: Moment) -> Vec<PlannedNotificationRecord> {
    let at = BIRTHDAY_HOUR * 60;
    let mut idols: Vec<u32> = idol_ids.iter().filter_map(|id| snap.idol_index_by_id.get(id).copied()).collect();
    idols.sort_unstable();
    idols.dedup();
    let mut plans: Vec<(NaiveDate, u32, PlannedNotificationRecord)> = idols
        .into_iter()
        .filter_map(|i| {
            let idol = &snap.idols[i as usize];
            let (month, day) = birthday_month_day(idol.birthday.as_deref()?)?;
            let date = next_birthday(month, day, now)?;
            let name = &idol.name;
            let mut record = plan(
                format!("bday_{}", idol.id),
                NotificationKind::OshiBirthday,
                format!("🎂 今日は{name}の誕生日！"),
                Some(format!("{name}、お誕生日おめでとう！")),
                (date, at),
                Some(idol.id.clone()),
            );
            record.repeats_yearly = repeats_yearly_for(month, day);
            Some((date, idol_rank(snap, i), record))
        })
        .collect();
    plans.sort_by_key(|(date, rank, _)| (*date, *rank));
    plans.into_iter().map(|(_, _, p)| p).collect()
}

/// 次に来る誕生日 (9:00 より前なら今日も入る)。非閏年の 2/29 は 2/28 ([`month_day_in_year`])。
fn next_birthday(month: u32, day: u32, now: Moment) -> Option<NaiveDate> {
    (now.0.year()..=now.0.year() + 1)
        .filter_map(|y| month_day_in_year(y, month, day).and_then(|d| parse_day(&d)))
        .find(|&d| (d, BIRTHDAY_HOUR * 60) > now)
}

/// アイドルの表示順での位置。
fn idol_rank(snap: &Snapshot, idol: u32) -> u32 {
    snap.idol_order.iter().position(|&i| i == idol).map_or(u32::MAX, |p| p as u32)
}

/// 月曜のミーム: 次の日曜 20:00 から 8 週ぶん。回ごとに 1/500 でレアの文言。
fn monday_plans(now: Moment, seed: u64) -> Vec<PlannedNotificationRecord> {
    let at = MONDAY_HOUR * 60;
    let days_to_sunday = (7 - now.0.weekday().num_days_from_sunday()) % 7;
    let mut first = now.0 + chrono::Duration::days(days_to_sunday.into());
    if (first, at) <= now {
        first += chrono::Duration::weeks(1);
    }
    let mut rng = SplitMix64(seed);
    (0..MONDAY_MEME_WEEKS)
        .map(|i| {
            let rare = rng.next_below(MONDAY_MEME_RARE_DENOMINATOR) == 0;
            plan(
                format!("monday_meme_{i}"),
                NotificationKind::Monday,
                if rare { "どぅいどぅいどぅ〜" } else { "月曜が近いよ" }.to_string(),
                None,
                (first + chrono::Duration::weeks(i.into()), at),
                Some(CHIYOKO_IDOL_ID.to_string()),
            )
        })
        .collect()
}

/// ライブ 1 週間前 (初日の 7 日前 10:00)・申込締切の前日 18:00・当落発表の当日 9:00。
/// 初日が今日より後のイベントだけ。近い順 (同じ時刻は識別子の順)。
fn event_plans(snap: &Snapshot, event_ids: &[String], live_week: bool, ticket: bool, today: NaiveDate) -> Vec<PlannedNotificationRecord> {
    if !live_week && !ticket {
        return Vec::new();
    }
    let mut events: Vec<u32> = event_ids.iter().filter_map(|id| snap.event_index_by_id.get(id).copied()).collect();
    events.sort_unstable();
    events.dedup();
    let mut plans: Vec<PlannedNotificationRecord> = Vec::new();
    for e in events {
        let event = &snap.events[e as usize];
        let Some(first) = snap.shows_by_event[e as usize]
            .iter()
            .map(|&s| snap.shows[s as usize].date.as_str())
            .min()
            .and_then(parse_day)
        else {
            continue;
        };
        if first <= today {
            continue;
        }
        let name = &event.name;
        if live_week {
            let day = first - chrono::Duration::days(7);
            if day > today {
                plans.push(plan(
                    format!("live_{}", event.id),
                    NotificationKind::LiveWeek,
                    "もうすぐライブ！".to_string(),
                    Some(format!("{name} まであと1週間！準備はOK？")),
                    (day, LIVE_WEEK_HOUR * 60),
                    None,
                ));
            }
        }
        if ticket {
            if let Some(deadline) = event.ticket_deadline.as_deref().and_then(parse_day) {
                let day = deadline - chrono::Duration::days(1);
                if deadline > today && day > today {
                    plans.push(plan(
                        format!("ticketdl_{}", event.id),
                        NotificationKind::Ticket,
                        "チケット申込は明日まで！".to_string(),
                        Some(format!("{name} のチケット申込締切は明日です。お忘れなく！")),
                        (day, TICKET_DEADLINE_HOUR * 60),
                        None,
                    ));
                }
            }
            if let Some(lottery) = event.ticket_lottery_date.as_deref().and_then(parse_day) {
                if lottery > today {
                    plans.push(plan(
                        format!("lottery_{}", event.id),
                        NotificationKind::Ticket,
                        "当落発表日です！".to_string(),
                        Some(format!("{name} の当落発表日。ドキドキしながら確認してみよう！")),
                        (lottery, LOTTERY_HOUR * 60),
                        None,
                    ));
                }
            }
        }
    }
    plans.sort_by(|a, b| (&a.date, a.hour, a.minute, &a.id).cmp(&(&b.date, b.hour, b.minute, &b.id)));
    plans
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn input(today: &str, now_minutes: u32) -> NotificationPlanInput {
        NotificationPlanInput {
            today: today.into(),
            now_minutes,
            birthday_enabled: true,
            monday_enabled: true,
            live_week_enabled: true,
            ticket_enabled: true,
            pick_idol_ids: Vec::new(),
            event_ids: Vec::new(),
            seed: 1,
        }
    }

    #[test]
    fn round_robin_spreads_the_cap_across_groups() {
        let merged = round_robin_merge(vec![vec![1, 2, 3, 4], vec![10], vec![20, 21]], 5);
        assert_eq!(merged, vec![1, 10, 20, 2, 21]);
        assert_eq!(round_robin_merge(vec![vec![1, 2], Vec::new()], 10), vec![1, 2]);
    }

    #[test]
    fn monday_meme_starts_at_the_next_sunday_evening() {
        // 2026-09-20 は日曜。20:00 より前なら当日から、過ぎていれば翌週から。
        let before = monday_plans((parse_day("2026-09-20").unwrap(), 19 * 60), 1);
        assert_eq!(before.len(), 8);
        assert_eq!((before[0].date.as_str(), before[0].hour), ("2026-09-20", 20));
        assert_eq!(before[7].date, "2026-11-08");
        let after = monday_plans((parse_day("2026-09-20").unwrap(), 20 * 60), 1);
        assert_eq!(after[0].date, "2026-09-27");
        let wednesday = monday_plans((parse_day("2026-09-23").unwrap(), 0), 1);
        assert_eq!(wednesday[0].date, "2026-09-27");
        assert!(before.iter().all(|p| p.title == "月曜が近いよ" || p.title == "どぅいどぅいどぅ〜"));
        assert_eq!(monday_plans((parse_day("2026-09-23").unwrap(), 0), 7), monday_plans((parse_day("2026-09-23").unwrap(), 0), 7), "同じシードなら同じ");
    }

    #[test]
    fn rare_monday_title_is_about_one_in_five_hundred() {
        let rare = (0..5_000u64)
            .flat_map(|seed| monday_plans((parse_day("2026-09-23").unwrap(), 0), seed))
            .filter(|p| p.title == "どぅいどぅいどぅ〜")
            .count();
        assert!((40..=120).contains(&rare), "40000 回で {rare} 回");
    }

    #[test]
    fn birthdays_are_the_next_occurrence_at_nine_and_feb_29_falls_on_feb_28() {
        assert_eq!(birthday_month_day("--02-29"), Some((2, 29)));
        assert_eq!(birthday_month_day("02-29"), Some((2, 29)));
        assert_eq!(birthday_month_day("13-01"), None);
        let at = |d: &str, minutes: u32| (parse_day(d).unwrap(), minutes);
        assert_eq!(next_birthday(2, 29, at("2026-01-10", 0)).map(day_key).as_deref(), Some("2026-02-28"), "非閏年は 2/28");
        assert_eq!(next_birthday(2, 29, at("2028-01-10", 0)).map(day_key).as_deref(), Some("2028-02-29"));
        assert_eq!(next_birthday(2, 29, at("2027-03-01", 0)).map(day_key).as_deref(), Some("2028-02-29"));
        assert_eq!(next_birthday(2, 30, at("2026-01-10", 0)), None, "実在しない月日は出さない");
    }

    #[test]
    fn birthdays_repeat_yearly_except_feb_29_and_nothing_else_repeats() {
        let snap = bundle_snapshot();
        let mut inp = input("2026-01-10", 0);
        inp.pick_idol_ids = snap.idols.iter().filter(|i| i.birthday.is_some()).take(30).map(|i| i.id.clone()).collect();
        inp.event_ids = snap.events.iter().map(|e| e.id.clone()).collect();
        let plan = notification_plan(snap, &inp);
        assert!(plan.iter().any(|p| p.kind == NotificationKind::OshiBirthday));
        for p in &plan {
            let expected = p.kind == NotificationKind::OshiBirthday && !p.id.is_empty() && {
                let idol = &snap.idols[snap.idol_index_by_id[p.id.trim_start_matches("bday_")] as usize];
                birthday_month_day(idol.birthday.as_deref().unwrap()) != Some((2, 29))
            };
            assert_eq!(p.repeats_yearly, expected, "{}", p.id);
        }
        assert!(repeats_yearly_for(3, 1) && !repeats_yearly_for(2, 29), "2/29 だけ毎年くり返さない");
    }

    #[test]
    fn birthday_today_before_nine_is_today_and_after_nine_is_next_year() {
        let snap = bundle_snapshot();
        let idol = snap
            .idols
            .iter()
            .find(|i| i.birthday.as_deref().and_then(birthday_month_day).is_some_and(|(m, d)| (m, d) != (2, 29)))
            .unwrap();
        let (m, d) = birthday_month_day(idol.birthday.as_deref().unwrap()).unwrap();
        let today = NaiveDate::from_ymd_opt(2026, m, d).unwrap();
        let early = birthday_plans(snap, std::slice::from_ref(&idol.id), (today, 8 * 60));
        assert_eq!(early[0].date, day_key(today));
        assert_eq!(early[0].id, format!("bday_{}", idol.id));
        let late = birthday_plans(snap, std::slice::from_ref(&idol.id), (today, 9 * 60));
        assert_eq!(late[0].date, day_key(NaiveDate::from_ymd_opt(2027, m, d).unwrap()));
    }

    #[test]
    fn event_notifications_follow_the_first_show_and_ticket_dates() {
        let snap = bundle_snapshot();
        let (e, first) = snap
            .events
            .iter()
            .enumerate()
            .filter_map(|(e, _)| {
                let first = snap.shows_by_event[e].iter().map(|&s| snap.shows[s as usize].date.clone()).min()?;
                parse_day(&first).map(|d| (e, d))
            })
            .next()
            .unwrap();
        let id = snap.events[e].id.clone();
        let today = first - chrono::Duration::days(30);
        let plans = event_plans(snap, std::slice::from_ref(&id), true, false, today);
        assert_eq!(plans.len(), 1);
        assert_eq!(plans[0].id, format!("live_{id}"));
        assert_eq!((plans[0].date.clone(), plans[0].hour), (day_key(first - chrono::Duration::days(7)), 10));
        // 1 週間を切っていれば出さない。初日を過ぎたイベントも出さない。
        assert!(event_plans(snap, std::slice::from_ref(&id), true, true, first - chrono::Duration::days(7)).iter().all(|p| p.kind != NotificationKind::LiveWeek));
        assert!(event_plans(snap, &[id], true, true, first).is_empty());
    }

    #[test]
    fn the_plan_is_capped_and_every_category_gets_a_share() {
        let snap = bundle_snapshot();
        let mut inp = input("2020-01-01", 0);
        inp.pick_idol_ids = snap.idols.iter().filter(|i| i.birthday.is_some()).map(|i| i.id.clone()).collect();
        inp.event_ids = snap.events.iter().map(|e| e.id.clone()).collect();
        let plan = notification_plan(snap, &inp);
        assert_eq!(plan.len(), MAX_SCHEDULED_NOTIFICATIONS);
        for kind in [NotificationKind::OshiBirthday, NotificationKind::Monday] {
            assert!(plan.iter().any(|p| p.kind == kind), "{kind:?}");
        }
        assert!(plan.iter().any(|p| matches!(p.kind, NotificationKind::LiveWeek | NotificationKind::Ticket)));
        let ids: std::collections::HashSet<&str> = plan.iter().map(|p| p.id.as_str()).collect();
        assert_eq!(ids.len(), plan.len(), "識別子は重ならない");

        inp.birthday_enabled = false;
        inp.monday_enabled = false;
        inp.live_week_enabled = false;
        inp.ticket_enabled = false;
        assert!(notification_plan(snap, &inp).is_empty());
        assert!(notification_plan(snap, &input("壊れた日付", 0)).is_empty());
    }
}
