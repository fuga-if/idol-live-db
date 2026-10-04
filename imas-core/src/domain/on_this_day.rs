//! 「今日は何の日？」— ある日付と同じ月日に起きた過去の出来事と、その共有文。
//!
//! 拾うもの (どれも **起点より後の年** だけ。当年の当日は「今日の予定」でカレンダーが出す):
//! - 記念日 (`anniversaries`): サービス開始・アニメ放映開始・劇場版公開など。N 周年。
//! - ライブ: 同じ月日に開催された公演。ライブ (`kind = live`) とフェス (`festival`) だけ
//!   (発売記念イベントまで入れると、毎日のように小さな催しが並んで節目が埋もれる)。
//!   同じライブの同じ日の公演 (昼・夜) は 1 件にまとめる。
//! - リリース: 同じ月日に配信された原曲 (`parent_song_id IS NULL`)。同じ年の同じ日は 1 件。
//! - 誕生日: その日が誕生日のアイドル (外部ゲストは除く)。年は無いので毎年出る。
//!
//! 月日の合わせ方はカレンダーと同じ [`month_day_in_year`] (非閏年は 2/29 起点を 2/28 に出す)。
//! 日付は JST の `YYYY-MM-DD` で受ける (公演日と比べるので `jst_day` の方針に揃える)。
//!
//! 共有文もここで組む。X の文字数 (全角 2・URL 23 で 280) に収まるところまで並べ、
//! 残りは「ほか N 件」に畳む。本文を切られると末尾のハッシュタグと URL まで消えるため。

use crate::domain::calendar_queries::month_day_in_year;
use crate::domain::share_text::{SharePayload, HASHTAG, WEB_ORIGIN};
use crate::domain::show_naming::distinguishing_show_name;
use crate::domain::snapshot::Snapshot;

/// 「何の日」に出すライブの種類 (`events.kind`)。
const LIVE_KINDS: [&str; 2] = ["live", "festival"];

/// 記念日 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OnThisDayAnniversary {
    pub anniversary_id: String,
    pub brand_id: String,
    pub label: String,
    /// 起点日 `YYYY-MM-DD`。
    pub origin_date: String,
    pub years: u32,
    /// 数の後ろに付ける語。終わった出来事 (サービス終了) は「年」、それ以外は「周年」。
    pub unit: String,
}

/// 過去のライブ 1 件 (同じライブの同じ日の公演をまとめたもの)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OnThisDayLive {
    pub event_id: String,
    pub event_name: String,
    pub brand_id: Option<String>,
    /// 合同ライブ (複数ブランド名義)。行頭の帯を虹色にする。
    pub is_joint: bool,
    /// 公演日 `YYYY-MM-DD`。
    pub date: String,
    /// その日の公演 (公演順)。
    pub show_ids: Vec<String>,
    /// 公演を見分ける名前 (ライブ名と重なる部分を落としたもの。「DAY1」)。
    /// その日の公演が 1 つで、見分ける名前があるときだけ入る。
    pub show_label: Option<String>,
    pub venue: Option<String>,
    pub years: u32,
}

/// 過去のリリース 1 件 (同じ日に配信された曲をまとめたもの)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OnThisDayRelease {
    /// 配信日 `YYYY-MM-DD`。
    pub date: String,
    /// 曲 (よみ順)。
    pub song_ids: Vec<String>,
    pub years: u32,
    /// 共有文と行の題に出す名前 (全曲が同じ CD なら「CD名」、それ以外は先頭の曲名)。
    pub title: String,
}

/// 誕生日のアイドル 1 人。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OnThisDayBirthday {
    pub idol_id: String,
    pub name: String,
}

/// ある日の「何の日」。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct OnThisDay {
    /// 対象の日 `YYYY-MM-DD`。
    pub day: String,
    /// 見出し (「10月4日は何の日？」)。
    pub title: String,
    pub anniversaries: Vec<OnThisDayAnniversary>,
    pub birthdays: Vec<OnThisDayBirthday>,
    pub lives: Vec<OnThisDayLive>,
    pub releases: Vec<OnThisDayRelease>,
    /// 共有文。何も無い日は `None` (共有の導線ごと出さない)。
    pub share: Option<SharePayload>,
}

impl OnThisDay {
    pub fn is_empty(&self) -> bool {
        self.anniversaries.is_empty()
            && self.birthdays.is_empty()
            && self.lives.is_empty()
            && self.releases.is_empty()
    }
}

/// `YYYY-MM-DD` → (年, 月, 日)。
fn ymd(date: &str) -> Option<(i32, u32, u32)> {
    let mut parts = date.splitn(3, '-');
    let year = parts.next()?.parse().ok()?;
    let month = parts.next()?.parse().ok()?;
    let day = parts.next()?.get(..2)?.parse().ok()?;
    Some((year, month, day))
}

/// `origin` (`YYYY-MM-DD`) が `day` の何年前の同じ月日か。起点より後の年で月日が合うときだけ。
fn years_since(origin: &str, day: &str, target_year: i32) -> Option<u32> {
    let (year, month, d) = ymd(origin)?;
    if year >= target_year {
        return None;
    }
    let recurring = month_day_in_year(target_year, month, d)?;
    (recurring == day).then(|| (target_year - year) as u32)
}

/// `day` (JST `YYYY-MM-DD`) の「何の日」。読めない日付は空で返す。
pub fn on_this_day(snap: &Snapshot, day: &str) -> OnThisDay {
    let Some((target_year, month, d)) = ymd(day) else {
        return OnThisDay {
            day: day.to_string(),
            title: String::new(),
            anniversaries: vec![],
            birthdays: vec![],
            lives: vec![],
            releases: vec![],
            share: None,
        };
    };
    let mut out = OnThisDay {
        day: day.to_string(),
        title: format!("{month}月{d}日は何の日？"),
        anniversaries: collect_anniversaries(snap, day, target_year),
        birthdays: collect_birthdays(snap, day, target_year),
        lives: collect_lives(snap, day, target_year),
        releases: collect_releases(snap, day, target_year),
        share: None,
    };
    if !out.is_empty() {
        out.share = Some(share_payload(&out));
    }
    out
}

/// 記念日 (起点日の古い順)。
fn collect_anniversaries(snap: &Snapshot, day: &str, target_year: i32) -> Vec<OnThisDayAnniversary> {
    snap.anniversary_order
        .iter()
        .map(|&i| &snap.anniversaries[i as usize])
        .filter_map(|ann| {
            let years = years_since(&ann.date, day, target_year)?;
            Some(OnThisDayAnniversary {
                anniversary_id: ann.id.clone(),
                brand_id: ann.brand_id.clone(),
                label: ann.label.clone(),
                origin_date: ann.date.clone(),
                years,
                unit: if ann.kind == "service_end" { "年" } else { "周年" }.to_string(),
            })
        })
        .collect()
}

/// 誕生日 (アイドルの表示順)。誕生日は `--MM-DD` で年を持たない。
fn collect_birthdays(snap: &Snapshot, day: &str, target_year: i32) -> Vec<OnThisDayBirthday> {
    snap.idol_order
        .iter()
        .map(|&i| &snap.idols[i as usize])
        .filter(|idol| !idol.is_external)
        .filter(|idol| {
            idol.birthday
                .as_deref()
                .and_then(|b| b.strip_prefix("--"))
                .and_then(|md| {
                    let (m, dd) = md.split_once('-')?;
                    month_day_in_year(target_year, m.parse().ok()?, dd.parse().ok()?)
                })
                .is_some_and(|recurring| recurring == day)
        })
        .map(|idol| OnThisDayBirthday { idol_id: idol.id.clone(), name: idol.name.clone() })
        .collect()
}

/// 過去のライブ (古い順)。同じライブの同じ日の公演は 1 件にまとめる。
fn collect_lives(snap: &Snapshot, day: &str, target_year: i32) -> Vec<OnThisDayLive> {
    let mut out: Vec<OnThisDayLive> = Vec::new();
    // shows_in_date_order は (date, sort_order) 順なので、同じライブの同じ日は隣り合う。
    for &si in &snap.shows_in_date_order {
        let show = &snap.shows[si as usize];
        let Some(years) = years_since(&show.date, day, target_year) else { continue };
        let event = &snap.events[show.event as usize];
        if !LIVE_KINDS.contains(&event.kind.as_str()) {
            continue;
        }
        if let Some(last) = out.last_mut().filter(|l| l.event_id == event.id && l.date == show.date) {
            last.show_ids.push(show.id.clone());
            last.show_label = None;
            continue;
        }
        out.push(OnThisDayLive {
            event_id: event.id.clone(),
            event_name: event.name.clone(),
            brand_id: event.brand_id.clone(),
            is_joint: event.joint_brand_ids.as_deref().is_some_and(|j| !j.trim().is_empty()),
            date: show.date.clone(),
            show_ids: vec![show.id.clone()],
            show_label: distinguishing_show_name(&event.name, &show.name).map(str::to_string),
            venue: show.venue.clone(),
            years,
        });
    }
    out
}

/// 過去のリリース (古い順)。同じ日の曲はよみ順で 1 件にまとめる。
fn collect_releases(snap: &Snapshot, day: &str, target_year: i32) -> Vec<OnThisDayRelease> {
    let mut hits: Vec<(&str, u32, usize)> = snap
        .songs
        .iter()
        .enumerate()
        .filter(|(_, s)| s.parent_song_id.is_none())
        .filter_map(|(i, s)| {
            let date = s.release_date.as_deref()?;
            Some((date, years_since(date, day, target_year)?, i))
        })
        .collect();
    // 日付 → よみ (NULL 先頭) → 添字。カレンダーのリリースと同じ並び。
    hits.sort_by(|a, b| {
        (a.0, &snap.songs[a.2].title_kana, a.2).cmp(&(b.0, &snap.songs[b.2].title_kana, b.2))
    });
    let mut out: Vec<OnThisDayRelease> = Vec::new();
    for group in hits.chunk_by(|a, b| a.0 == b.0) {
        let songs: Vec<_> = group.iter().map(|&(_, _, i)| &snap.songs[i]).collect();
        let cd = songs[0].cd_title.as_deref().filter(|t| !t.trim().is_empty());
        let title = match cd {
            Some(cd) if songs.iter().all(|s| s.cd_title.as_deref() == Some(cd)) => cd.to_string(),
            _ => songs[0].title.clone(),
        };
        out.push(OnThisDayRelease {
            date: group[0].0.to_string(),
            song_ids: songs.iter().map(|s| s.id.clone()).collect(),
            years: group[0].1,
            title,
        });
    }
    out
}

// ---------------------------------------------------------------------------
// 共有文
// ---------------------------------------------------------------------------

/// X の上限 (重み付きの文字数)。
const X_LIMIT: usize = 280;
/// X が URL に数える長さ (t.co で短縮される)。
const X_URL_WEIGHT: usize = 23;

/// X の重み付き文字数 (twitter-text の既定: 下の範囲は 1、それ以外 (全角・絵文字) は 2)。
pub fn x_weighted_len(s: &str) -> usize {
    s.chars()
        .map(|c| match c as u32 {
            0x0000..=0x10FF | 0x2000..=0x200D | 0x2010..=0x201F | 0x2032..=0x2037 => 1,
            _ => 2,
        })
        .sum()
}

/// 共有文の 1 行ずつ (記念日 → 誕生日 → ライブ → リリースの順。節目を先に出す)。
fn share_lines(day: &OnThisDay) -> Vec<String> {
    let mut lines = Vec::new();
    for a in &day.anniversaries {
        lines.push(format!("・{}から{}{}", a.label, a.years, a.unit));
    }
    if !day.birthdays.is_empty() {
        let names: Vec<&str> = day.birthdays.iter().map(|b| b.name.as_str()).collect();
        lines.push(format!("・{}の誕生日", names.join("、")));
    }
    for l in &day.lives {
        let name = match &l.show_label {
            Some(label) => format!("{} {label}", l.event_name),
            None => l.event_name.clone(),
        };
        lines.push(format!("・{name}（{}年前）", l.years));
    }
    for r in &day.releases {
        let more = if r.song_ids.len() > 1 { format!("ほか{}曲", r.song_ids.len() - 1) } else { String::new() };
        lines.push(format!("・「{}」{more}発売（{}年前）", r.title, r.years));
    }
    lines
}

/// その日のカレンダー (Web の月のページ)。
fn calendar_url(day: &str) -> String {
    format!("{WEB_ORIGIN}/calendar/{}/", day.get(..7).unwrap_or(day))
}

/// 本文を X の上限に収める。入りきらない行は「ほか N 件」に畳む (見出しとタグは必ず残す)。
fn fit_message(title: &str, lines: &[String], has_url: bool) -> String {
    let budget = X_LIMIT - if has_url { X_URL_WEIGHT + 1 } else { 0 };
    let compose = |shown: &[String], rest: usize| {
        let mut body = vec![title.to_string(), String::new()];
        body.extend(shown.iter().cloned());
        if rest > 0 {
            body.push(format!("ほか{rest}件"));
        }
        body.push(String::new());
        body.push(HASHTAG.to_string());
        body.join("\n")
    };
    (1..=lines.len())
        .rev()
        .map(|n| compose(&lines[..n], lines.len() - n))
        .find(|m| x_weighted_len(m) <= budget)
        // 1 行目だけでも溢れる (極端に長いライブ名) ときは、その行を入れたまま X 側に任せる。
        .unwrap_or_else(|| compose(&lines[..lines.len().min(1)], lines.len().saturating_sub(1)))
}

fn share_payload(day: &OnThisDay) -> SharePayload {
    SharePayload {
        message: fit_message(&day.title, &share_lines(day), true),
        url: Some(calendar_url(&day.day)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn years_since_matches_month_day_only_after_origin_year() {
        assert_eq!(years_since("2024-10-04", "2026-10-04", 2026), Some(2));
        assert_eq!(years_since("2026-10-04", "2026-10-04", 2026), None, "当年の当日は出さない");
        assert_eq!(years_since("2024-10-05", "2026-10-04", 2026), None);
        // 閏日の起点は非閏年の 2/28 に出る (カレンダーと同じ)。
        assert_eq!(years_since("2024-02-29", "2027-02-28", 2027), Some(3));
        assert_eq!(years_since("2024-02-29", "2028-02-28", 2028), None, "閏年は 2/29 に出る");
        assert_eq!(years_since("2024-02-29", "2028-02-29", 2028), Some(4));
    }

    #[test]
    fn real_data_finds_shiny_colors_anime_second_season() {
        let day = on_this_day(bundle_snapshot(), "2026-10-04");
        assert_eq!(day.title, "10月4日は何の日？");
        let ann = day
            .anniversaries
            .iter()
            .find(|a| a.label.contains("シャニアニ2nd"))
            .expect("シャニアニ2nd season の放映開始が出る");
        assert_eq!((ann.years, ann.unit.as_str()), (2, "周年"));
        let share = day.share.expect("出来事がある日は共有文がある");
        assert!(share.message.contains("シャニアニ2nd season放映開始から2周年"), "{}", share.message);
        assert_eq!(share.url.as_deref(), Some("https://idollivedb.fugaapp.site/calendar/2026-10/"));
    }

    #[test]
    fn real_data_lives_merge_same_day_shows_and_skip_minor_kinds() {
        let snap = bundle_snapshot();
        // 毎年の結果が全部ライブ/フェスで、同じライブ・同じ日は 1 件。
        for day in ["2026-10-04", "2026-11-28", "2026-07-26"] {
            let lives = on_this_day(snap, day).lives;
            for l in &lives {
                let event = snap.events.iter().find(|e| e.id == l.event_id).unwrap();
                assert!(LIVE_KINDS.contains(&event.kind.as_str()), "{day}: {}", event.name);
                assert!(l.years >= 1);
                assert!(l.show_ids.len() == 1 || l.show_label.is_none());
            }
            let mut keys: Vec<_> = lives.iter().map(|l| (&l.event_id, &l.date)).collect();
            keys.dedup();
            assert_eq!(keys.len(), lives.len(), "{day}: 同じライブ・同じ日は 1 件");
        }
    }

    #[test]
    fn birthdays_exclude_external_guests() {
        let snap = bundle_snapshot();
        let day = on_this_day(snap, "2026-04-03");
        for b in &day.birthdays {
            assert!(!snap.idol(&b.idol_id).unwrap().is_external);
        }
    }

    #[test]
    fn unreadable_day_is_empty_without_share() {
        let day = on_this_day(bundle_snapshot(), "not-a-day");
        assert!(day.is_empty());
        assert!(day.share.is_none());
    }

    #[test]
    fn x_weight_counts_wide_chars_as_two() {
        assert_eq!(x_weighted_len("abc"), 3);
        assert_eq!(x_weighted_len("何の日"), 6);
        assert_eq!(x_weighted_len("・"), 2);
    }

    #[test]
    fn message_folds_overflow_into_count_and_keeps_hashtag() {
        let lines: Vec<String> = (0..40).map(|i| format!("・とても長いライブの名前その{i}（10年前）")).collect();
        let message = fit_message("10月4日は何の日？", &lines, true);
        assert!(x_weighted_len(&message) + X_URL_WEIGHT + 1 <= X_LIMIT, "{message}");
        assert!(message.ends_with(HASHTAG));
        assert!(message.contains("ほか"), "{message}");
        assert!(message.starts_with("10月4日は何の日？\n\n・"));
    }

    #[test]
    fn message_keeps_everything_when_it_fits() {
        let lines = vec!["・シャニアニ2nd season放映開始から2周年".to_string()];
        assert_eq!(
            fit_message("10月4日は何の日？", &lines, true),
            format!("10月4日は何の日？\n\n・シャニアニ2nd season放映開始から2周年\n\n{HASHTAG}")
        );
    }
}
