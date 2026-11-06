//! 今年の P 活動報告 (1 年の参加の記録を、年末にめくって見せる物語) の集計。
//!
//! 2026-11 ユーザー「全部すすめて」(P名刺の続き、見本 = P 活動報告のモック)。
//! ページは ① 参加した公演 ② 現場カレンダー ③ 遠征 ④ いちばん聴いた曲 ⑤ まとめ (SNS に貼る 1 枚)。
//! 来年の現場は入れない。数えるのは参加マークの付いた公演 (show 単位・event 単位) のうち、回収と同じく
//! リアルライブの公演だけ ([`crate::domain::collection_gap::is_real_live`])。
//!
//! - 現地 / 配信: 形態に「現地」が付いていれば現地、付いていなければ配信 (配信・LV)。形態を持たない古い
//!   マークは現地 ([`crate::domain::attendance::attendance_types`])。
//! - はじめて生で聴いた曲: その年の**現地**の公演で聴いた曲のうち、前の年までの現地の公演で聴いていない曲。
//! - 回収した曲: その年に初めて回収した曲 (回収に配信を含めるかは端末の設定。一覧の回収と同じ規則)。
//! - 担当の歌: その年の公演で担当が歌った披露の数 (セトリの歌唱メンバーに担当がいる行)。
//! - いちばん聴いた曲: その年の公演で披露された回数がいちばん多い曲 (2 回以上のときだけ)。
//! - 遠征: 現地の公演の会場の都道府県と会場。灯す順は初めて行った順。
//! - 遠征費: 収支を付けている人だけ。その年の遠征の費目 (チケット・交通・宿) の合計。

use std::collections::{HashMap, HashSet};

use crate::domain::attendance::{attendance_types, LOCAL_ATTENDANCE};
use crate::domain::collection_gap::{collection_attendance_types, is_real_live};
use crate::domain::event_list_queries::AttendanceMarkRecord;
use crate::domain::idol_facets::PREFECTURES;
use crate::domain::ledger::{expense_categories, format_yen, ExpenseEntry};
use crate::domain::show_naming::show_title;
use crate::domain::snapshot::Snapshot;

/// 報告を組む材料 (端末が参加マーク・担当・帳簿を射影して渡す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReportInput {
    pub year: u16,
    /// まとめの題に出す名前 (P名刺の名前。空なら「わたし」)。
    pub name: String,
    /// show 単位の参加マーク (形態つき)。
    pub show_marks: Vec<AttendanceMarkRecord>,
    /// event 単位の参加マーク (配下の公演すべてに効く)。
    pub event_marks: Vec<AttendanceMarkRecord>,
    /// 担当 (担当の歌を数える)。
    pub oshi_idol_ids: Vec<String>,
    /// 回収に配信の参加も数えるか (端末の設定)。
    pub collection_includes_stream: bool,
    /// 収支を付けているか (付けていなければ遠征費を出さない)。
    pub uses_ledger: bool,
    /// 帳簿ぜんぶ (その年の分だけ数える)。
    pub expenses: Vec<ExpenseEntry>,
}

/// ① 参加した公演の半券の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReportShow {
    pub show_id: String,
    pub date: String,
    pub month: u8,
    pub day: u8,
    /// 半券の月の刻印 (「SEP」)。
    pub month_imprint: String,
    pub title: String,
    pub venue: Option<String>,
    /// 現地で参加したか (偽なら配信・LV)。
    pub is_local: bool,
}

/// ② 現場カレンダーの 1 か月。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReportMonth {
    pub month: u8,
    pub count: u32,
}

/// ③ 行った都道府県 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReportPrefecture {
    /// JIS の都道府県コード (1 = 北海道 … 47 = 沖縄)。地図の升の位置。
    pub code: u8,
    /// 都道府県名 (「埼玉県」)。
    pub name: String,
    /// その都道府県での現地の公演の数。
    pub count: u32,
}

/// ④ いちばん聴いた曲。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReportSong {
    pub song_id: String,
    pub title: String,
    pub artwork_url: Option<String>,
    pub count: u32,
}

/// ⑤ まとめの 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReportRow {
    pub label: String,
    pub value: String,
    /// 値が数か (数なら数字の書体で大きく、曲名などは本文の書体)。
    pub is_number: bool,
}

/// めくるページ。材料の無いページは入れない (遠征の無い年に地図を出さない)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum YearReportPage {
    Shows,
    Calendar,
    Travel,
    Song,
    Summary,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YearReport {
    pub year: u16,
    /// 参加した公演が 1 つも無い (報告を出さない)。
    pub is_empty: bool,
    pub pages: Vec<YearReportPage>,
    /// ① 古い順。
    pub shows: Vec<YearReportShow>,
    pub show_count: u32,
    pub local_count: u32,
    pub stream_count: u32,
    /// ① の題 (「2026 年に参加した公演」)。
    pub shows_title: String,
    /// ① の数の横 (「公演 · 現地 17 · 配信 6」)。
    pub shows_caption: String,
    /// ② 1〜12 月 (現場の無い月も 0 で入る)。
    pub months: Vec<YearReportMonth>,
    /// ② の題 (「いちばん通ったのは 9 月」)。
    pub calendar_title: String,
    /// ③ 初めて行った順。
    pub prefectures: Vec<YearReportPrefecture>,
    pub venue_count: u32,
    /// ③ の題 (「7 都道府県、12 会場へ」)。
    pub travel_title: String,
    /// ③ の下の 1 行 (「最多 さいたまスーパーアリーナ 3 回」)。2 回以上通った会場が無ければ無し。
    pub travel_note: Option<String>,
    pub top_song: Option<YearReportSong>,
    pub first_live_song_count: u32,
    pub oshi_song_count: u32,
    pub collected_song_count: u32,
    /// ④ の下の 1 行 (「はじめて生で聴いた曲 41 曲 · 担当の歌 18 回」)。
    pub song_note: String,
    /// 遠征費 (円)。収支を付けていなければ無し。
    pub travel_cost: Option<i64>,
    /// ⑤ の題 (「ふがP の 2026 年」)。
    pub summary_title: String,
    pub summary_rows: Vec<YearReportRow>,
    /// ⑤ を書き出すときの投稿文の候補。
    pub share_text: String,
}

const MONTH_IMPRINTS: [&str; 12] = [
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
];

/// 公演ごとの参加形態 (show 単位・event 単位のマークを合わせる)。
fn attended_types(
    snap: &Snapshot,
    show_marks: &[AttendanceMarkRecord],
    event_marks: &[AttendanceMarkRecord],
) -> HashMap<u32, HashSet<String>> {
    let mut out: HashMap<u32, HashSet<String>> = HashMap::new();
    for m in show_marks {
        if let Some(&show) = snap.show_index_by_id.get(&m.entity_id) {
            out.entry(show)
                .or_default()
                .extend(attendance_types(m.attendance_type.as_deref()));
        }
    }
    for m in event_marks {
        if let Some(&e) = snap.event_index_by_id.get(&m.entity_id) {
            for &show in &snap.shows_by_event[e as usize] {
                out.entry(show)
                    .or_default()
                    .extend(attendance_types(m.attendance_type.as_deref()));
            }
        }
    }
    out.retain(|&show, _| is_real_live(snap, show));
    out
}

/// 「東京都」「大阪府」「埼玉県」「北海道」→ JIS コード。
fn prefecture_code(name: &str) -> Option<u8> {
    let t = name.trim();
    let stem = if t == "北海道" {
        t
    } else {
        t.strip_suffix('都')
            .or_else(|| t.strip_suffix('府'))
            .or_else(|| t.strip_suffix('県'))
            .unwrap_or(t)
    };
    PREFECTURES
        .iter()
        .position(|(p, _)| *p == stem)
        .map(|i| (i + 1) as u8)
}

fn parse_month_day(date: &str) -> Option<(u8, u8)> {
    let month = date.get(5..7)?.parse().ok()?;
    let day = date.get(8..10)?.parse().ok()?;
    Some((month, day))
}

/// 公演の披露 (setlist_items の添字)。
fn items_of(snap: &Snapshot, show: u32) -> impl Iterator<Item = u32> + '_ {
    snap.setlist_items_by_show[show as usize].iter().copied()
}

pub fn year_report(snap: &Snapshot, input: &YearReportInput) -> YearReport {
    let year_prefix = format!("{:04}-", input.year);
    let year_start = format!("{:04}-01-01", input.year);
    let types = attended_types(snap, &input.show_marks, &input.event_marks);
    let is_local = |show: u32| {
        types
            .get(&show)
            .is_some_and(|t| t.contains(LOCAL_ATTENDANCE))
    };
    let collect_kinds = collection_attendance_types(input.collection_includes_stream);
    let collects = |show: u32| {
        collect_kinds.is_empty()
            || types
                .get(&show)
                .is_some_and(|t| collect_kinds.iter().any(|k| t.contains(k)))
    };

    let mut year_shows: Vec<u32> = types
        .keys()
        .copied()
        .filter(|&s| snap.shows[s as usize].date.starts_with(&year_prefix))
        .collect();
    year_shows.sort_by(|&a, &b| {
        let (sa, sb) = (&snap.shows[a as usize], &snap.shows[b as usize]);
        sa.date
            .cmp(&sb.date)
            .then(sa.sort_order.cmp(&sb.sort_order))
            .then_with(|| sa.id.cmp(&sb.id))
    });
    let before: Vec<u32> = types
        .keys()
        .copied()
        .filter(|&s| snap.shows[s as usize].date.as_str() < year_start.as_str())
        .collect();

    // ① 参加した公演
    let shows: Vec<YearReportShow> = year_shows
        .iter()
        .map(|&show| {
            let s = &snap.shows[show as usize];
            let (month, day) = parse_month_day(&s.date).unwrap_or((1, 1));
            YearReportShow {
                show_id: s.id.clone(),
                date: s.date.clone(),
                month,
                day,
                month_imprint: MONTH_IMPRINTS[(month.clamp(1, 12) - 1) as usize].to_string(),
                title: show_title(snap, &s.id).unwrap_or_else(|| s.name.clone()),
                venue: s.venue.clone(),
                is_local: is_local(show),
            }
        })
        .collect();
    let show_count = shows.len() as u32;
    let local_count = shows.iter().filter(|s| s.is_local).count() as u32;
    let stream_count = show_count - local_count;
    let shows_caption = match (local_count, stream_count) {
        (_, 0) => "公演 · すべて現地".to_string(),
        (0, _) => "公演 · すべて配信".to_string(),
        (l, s) => format!("公演 · 現地 {l} · 配信 {s}"),
    };

    // ② 現場カレンダー
    let mut month_counts = [0u32; 12];
    for s in &shows {
        month_counts[(s.month.clamp(1, 12) - 1) as usize] += 1;
    }
    let months: Vec<YearReportMonth> = month_counts
        .iter()
        .enumerate()
        .map(|(i, &count)| YearReportMonth {
            month: (i + 1) as u8,
            count,
        })
        .collect();
    let busiest = months
        .iter()
        .filter(|m| m.count > 0)
        .max_by(|a, b| a.count.cmp(&b.count).then(b.month.cmp(&a.month)));
    let active_months = months.iter().filter(|m| m.count > 0).count();
    let calendar_title = match busiest {
        None => String::new(),
        Some(m) if active_months == 1 => format!("{} 月が現場の月", m.month),
        Some(m) => format!("いちばん通ったのは {} 月", m.month),
    };

    // ③ 遠征 (現地だけ)
    let mut prefectures: Vec<YearReportPrefecture> = Vec::new();
    let mut venues: Vec<(String, u32)> = Vec::new();
    for &show in year_shows.iter().filter(|&&s| is_local(s)) {
        let s = &snap.shows[show as usize];
        let venue = s
            .venue_id
            .as_deref()
            .and_then(|id| snap.venue_index_by_id.get(id))
            .map(|&v| &snap.venues[v as usize]);
        let key = venue.map(|v| v.id.clone()).or_else(|| s.venue.clone());
        if let Some(key) = key {
            match venues.iter_mut().find(|(k, _)| *k == key) {
                Some((_, n)) => *n += 1,
                None => venues.push((key, 1)),
            }
        }
        if let Some(name) = venue.and_then(|v| v.prefecture.as_deref()) {
            if let Some(code) = prefecture_code(name) {
                match prefectures.iter_mut().find(|p| p.code == code) {
                    Some(p) => p.count += 1,
                    None => prefectures.push(YearReportPrefecture {
                        code,
                        name: name.trim().to_string(),
                        count: 1,
                    }),
                }
            }
        }
    }
    let venue_count = venues.len() as u32;
    let travel_title = match prefectures.len() {
        0 if venue_count == 0 => String::new(),
        0 => format!("{venue_count} 会場へ"),
        1 => format!("{}の {venue_count} 会場へ", prefectures[0].name),
        n => format!("{n} 都道府県、{venue_count} 会場へ"),
    };
    let travel_note = venues
        .iter()
        .enumerate()
        .filter(|(_, (_, n))| *n >= 2)
        .max_by(|(ia, (_, a)), (ib, (_, b))| a.cmp(b).then(ib.cmp(ia)))
        .map(|(_, (key, n))| {
            let name = snap
                .venue_index_by_id
                .get(key)
                .map(|&v| snap.venues[v as usize].name.clone())
                .unwrap_or_else(|| key.clone());
            format!("最多 {name} {n} 回")
        });

    // ④ 曲
    let oshi: HashSet<u32> = input
        .oshi_idol_ids
        .iter()
        .filter_map(|id| snap.idol_index_by_id.get(id).copied())
        .collect();
    let mut song_counts: HashMap<u32, (u32, usize)> = HashMap::new();
    let mut oshi_song_count = 0u32;
    for (order, &show) in year_shows.iter().enumerate() {
        for item in items_of(snap, show) {
            let song = snap.setlist_items[item as usize].song;
            song_counts.entry(song).or_insert((0, order)).0 += 1;
            if snap.performers_by_item[item as usize]
                .iter()
                .any(|i| oshi.contains(i))
            {
                oshi_song_count += 1;
            }
        }
    }
    let top_song = song_counts
        .iter()
        .filter(|(_, (n, _))| *n >= 2)
        .max_by(|(sa, (na, oa)), (sb, (nb, ob))| na.cmp(nb).then(ob.cmp(oa)).then(sb.cmp(sa)))
        .map(|(&song, &(count, _))| {
            let s = &snap.songs[song as usize];
            YearReportSong {
                song_id: s.id.clone(),
                title: s.title.clone(),
                artwork_url: s.artwork_url.clone(),
                count,
            }
        });
    let songs_in = |shows: &mut dyn Iterator<Item = u32>| -> HashSet<u32> {
        shows
            .flat_map(|show| items_of(snap, show).map(|i| snap.setlist_items[i as usize].song))
            .collect()
    };
    let heard_live_before = songs_in(&mut before.iter().copied().filter(|&s| is_local(s)));
    let first_live_song_count = songs_in(&mut year_shows.iter().copied().filter(|&s| is_local(s)))
        .difference(&heard_live_before)
        .count() as u32;
    let collected_before = songs_in(&mut before.iter().copied().filter(|&s| collects(s)));
    let collected_song_count = songs_in(&mut year_shows.iter().copied().filter(|&s| collects(s)))
        .difference(&collected_before)
        .count() as u32;
    let mut song_note_parts = vec![format!("はじめて生で聴いた曲 {first_live_song_count} 曲")];
    if !oshi.is_empty() {
        song_note_parts.push(format!("担当の歌 {oshi_song_count} 回"));
    }
    let song_note = song_note_parts.join(" · ");

    // 遠征費
    let travel_categories: Vec<_> = expense_categories()
        .into_iter()
        .filter(|c| c.is_travel)
        .map(|c| c.category)
        .collect();
    let travel_cost = input.uses_ledger.then(|| {
        input
            .expenses
            .iter()
            .filter(|e| e.date.starts_with(&year_prefix) && travel_categories.contains(&e.category))
            .map(|e| e.amount.max(0))
            .sum::<i64>()
    });

    // ⑤ まとめ
    let name = if input.name.trim().is_empty() {
        "わたし".to_string()
    } else {
        input.name.trim().to_string()
    };
    let summary_title = format!("{name} の {} 年", input.year);
    let mut rows = vec![YearReportRow {
        label: "参加公演".into(),
        value: show_count.to_string(),
        is_number: true,
    }];
    if local_count > 0 && stream_count > 0 {
        rows.push(YearReportRow {
            label: "現地 / 配信".into(),
            value: format!("{local_count} / {stream_count}"),
            is_number: true,
        });
    }
    rows.push(YearReportRow {
        label: "はじめて生で聴いた曲".into(),
        value: first_live_song_count.to_string(),
        is_number: true,
    });
    rows.push(YearReportRow {
        label: "回収した曲".into(),
        value: collected_song_count.to_string(),
        is_number: true,
    });
    if !oshi.is_empty() {
        rows.push(YearReportRow {
            label: "担当の歌".into(),
            value: oshi_song_count.to_string(),
            is_number: true,
        });
    }
    if !prefectures.is_empty() {
        rows.push(YearReportRow {
            label: "遠征した都道府県".into(),
            value: prefectures.len().to_string(),
            is_number: true,
        });
    }
    if let Some(song) = &top_song {
        rows.push(YearReportRow {
            label: "いちばん聴いた曲".into(),
            value: song.title.clone(),
            is_number: false,
        });
    }
    if let Some(cost) = travel_cost.filter(|&c| c > 0) {
        rows.push(YearReportRow {
            label: "遠征費".into(),
            value: format_yen(cost),
            is_number: true,
        });
    }

    let is_empty = show_count == 0;
    let mut pages = Vec::new();
    if !is_empty {
        pages.push(YearReportPage::Shows);
        pages.push(YearReportPage::Calendar);
        if venue_count > 0 {
            pages.push(YearReportPage::Travel);
        }
        if top_song.is_some() {
            pages.push(YearReportPage::Song);
        }
        pages.push(YearReportPage::Summary);
    }

    YearReport {
        year: input.year,
        is_empty,
        pages,
        shows,
        show_count,
        local_count,
        stream_count,
        shows_title: format!("{} 年に参加した公演", input.year),
        shows_caption,
        months,
        calendar_title,
        prefectures,
        venue_count,
        travel_title,
        travel_note,
        top_song,
        first_live_song_count,
        oshi_song_count,
        collected_song_count,
        song_note,
        travel_cost,
        summary_title,
        summary_rows: rows,
        share_text: format!("#P活動報告{} #アイドルライブDB", input.year),
    }
}

/// 参加した公演のある年 (新しい順)。過去の年の報告を開く入口に使う。
pub fn year_report_years(
    snap: &Snapshot,
    show_marks: &[AttendanceMarkRecord],
    event_marks: &[AttendanceMarkRecord],
    today: &str,
) -> Vec<u16> {
    let this_year: u16 = today.get(0..4).and_then(|y| y.parse().ok()).unwrap_or(0);
    let mut years: Vec<u16> = attended_types(snap, show_marks, event_marks)
        .keys()
        .filter(|&&s| snap.shows[s as usize].date.as_str() <= today)
        .filter_map(|&s| snap.shows[s as usize].date.get(0..4)?.parse().ok())
        .filter(|&y| y <= this_year)
        .collect();
    years.sort_unstable_by(|a, b| b.cmp(a));
    years.dedup();
    years
}

/// P名刺の画面とスケジュールに「今年の P 活動報告」を出す年。12 月は今年、1 月は去年 (年が明けても
/// しばらく開けるように)。ほかの月は出さない (過去の年は [`year_report_years`] から開く)。
pub fn year_report_offer_year(today: &str) -> Option<u16> {
    let year: u16 = today.get(0..4)?.parse().ok()?;
    let month: u8 = today.get(5..7)?.parse().ok()?;
    match month {
        12 => Some(year),
        1 => year.checked_sub(1),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ledger::ExpenseCategory;
    use crate::test_support::bundle_snapshot;

    fn mark(id: &str, t: Option<&str>) -> AttendanceMarkRecord {
        AttendanceMarkRecord {
            entity_id: id.into(),
            attendance_type: t.map(Into::into),
        }
    }

    fn input(year: u16, show_marks: Vec<AttendanceMarkRecord>) -> YearReportInput {
        YearReportInput {
            year,
            name: "ふがP".into(),
            show_marks,
            event_marks: vec![],
            oshi_idol_ids: vec![],
            collection_includes_stream: false,
            uses_ledger: false,
            expenses: vec![],
        }
    }

    /// 同じ年のリアルライブで、会場に都道府県があり、セトリのある公演を n 個 (古い順)。
    fn shows_in_a_year(n: usize) -> (u16, Vec<String>) {
        let snap = bundle_snapshot();
        let mut by_year: HashMap<String, Vec<u32>> = HashMap::new();
        for (i, s) in snap.shows.iter().enumerate() {
            let i = i as u32;
            let has_pref = s
                .venue_id
                .as_deref()
                .and_then(|id| snap.venue_index_by_id.get(id))
                .and_then(|&v| snap.venues[v as usize].prefecture.as_deref())
                .and_then(prefecture_code)
                .is_some();
            if is_real_live(&snap, i)
                && has_pref
                && !snap.setlist_items_by_show[i as usize].is_empty()
            {
                by_year.entry(s.date[0..4].to_string()).or_default().push(i);
            }
        }
        let (year, mut shows) = by_year
            .into_iter()
            .filter(|(_, v)| v.len() >= n)
            .max_by_key(|(y, _)| y.clone())
            .unwrap();
        shows.sort_by_key(|&s| snap.shows[s as usize].date.clone());
        (
            year.parse().unwrap(),
            shows
                .into_iter()
                .take(n)
                .map(|s| snap.shows[s as usize].id.clone())
                .collect(),
        )
    }

    #[test]
    fn prefecture_names_map_to_jis_codes() {
        assert_eq!(prefecture_code("北海道"), Some(1));
        assert_eq!(prefecture_code("東京都"), Some(13));
        assert_eq!(prefecture_code("京都府"), Some(26));
        assert_eq!(prefecture_code("大阪府"), Some(27));
        assert_eq!(prefecture_code("埼玉県"), Some(11));
        assert_eq!(prefecture_code("沖縄県"), Some(47));
        assert_eq!(prefecture_code("ソウル"), None);
    }

    #[test]
    fn counts_local_and_stream_and_pages() {
        let snap = bundle_snapshot();
        let (year, ids) = shows_in_a_year(3);
        let marks = vec![
            mark(&ids[0], None),
            mark(&ids[1], Some("live,stream")),
            mark(&ids[2], Some("stream")),
        ];
        let r = year_report(&snap, &input(year, marks));
        assert!(!r.is_empty);
        assert_eq!((r.show_count, r.local_count, r.stream_count), (3, 2, 1));
        assert_eq!(r.shows_caption, "公演 · 現地 2 · 配信 1");
        assert_eq!(
            r.shows
                .iter()
                .map(|s| s.show_id.clone())
                .collect::<Vec<_>>(),
            ids
        );
        assert_eq!(r.months.len(), 12);
        assert_eq!(r.months.iter().map(|m| m.count).sum::<u32>(), 3);
        // 配信だけの公演の会場は遠征に入れない。
        assert!(r.venue_count >= 1 && r.venue_count <= 2);
        assert!(!r.prefectures.is_empty());
        assert_eq!(r.pages.first(), Some(&YearReportPage::Shows));
        assert_eq!(r.pages.last(), Some(&YearReportPage::Summary));
        assert!(r.pages.contains(&YearReportPage::Travel));
        assert_eq!(r.summary_title, format!("ふがP の {year} 年"));
        // 遠征費は収支を付けている人だけ。
        assert_eq!(r.travel_cost, None);
        assert!(!r.summary_rows.iter().any(|row| row.label == "遠征費"));
        assert!(r.first_live_song_count > 0);
        assert!(r.collected_song_count >= r.first_live_song_count);
    }

    #[test]
    fn other_years_and_stream_only_years() {
        let snap = bundle_snapshot();
        let (year, ids) = shows_in_a_year(1);
        assert!(year_report(&snap, &input(year + 1, vec![mark(&ids[0], None)])).is_empty);
        let r = year_report(&snap, &input(year, vec![mark(&ids[0], Some("stream"))]));
        assert_eq!(r.shows_caption, "公演 · すべて配信");
        assert!(!r.pages.contains(&YearReportPage::Travel));
        // 回収は既定で現地だけ。配信も数える設定なら回収に入る。
        assert_eq!(r.collected_song_count, 0);
        let with_stream = year_report(
            &snap,
            &YearReportInput {
                collection_includes_stream: true,
                ..input(year, vec![mark(&ids[0], Some("stream"))])
            },
        );
        assert!(with_stream.collected_song_count > 0);
        assert_eq!(r.first_live_song_count, 0);
    }

    #[test]
    fn songs_heard_in_earlier_years_are_not_first() {
        let snap = bundle_snapshot();
        let (year, ids) = shows_in_a_year(1);
        let this = year_report(&snap, &input(year, vec![mark(&ids[0], None)]));
        // 同じ公演を前の年に見ていたことにはできないので、同じ年の 2 公演目で確かめる:
        // 1 公演目の曲は、それより前に聴いていなければ「はじめて」。
        let total = snap.setlist_items_by_show[snap.show_index_by_id[&ids[0]] as usize]
            .iter()
            .map(|&i| snap.setlist_items[i as usize].song)
            .collect::<HashSet<_>>()
            .len() as u32;
        assert_eq!(this.first_live_song_count, total);
    }

    #[test]
    fn travel_cost_counts_only_travel_categories_of_the_year() {
        let snap = bundle_snapshot();
        let (year, ids) = shows_in_a_year(1);
        let e = |date: String, category, amount| ExpenseEntry {
            id: format!("{date}{amount}"),
            date,
            category,
            amount,
            show_id: None,
            event_id: None,
            show_label: None,
            note: None,
        };
        let r = year_report(
            &snap,
            &YearReportInput {
                uses_ledger: true,
                expenses: vec![
                    e(format!("{year}-03-01"), ExpenseCategory::Transport, 12_000),
                    e(format!("{year}-03-01"), ExpenseCategory::Lodging, 8_000),
                    e(format!("{year}-03-01"), ExpenseCategory::Goods, 5_000),
                    e(
                        format!("{}-03-01", year - 1),
                        ExpenseCategory::Transport,
                        9_000,
                    ),
                ],
                ..input(year, vec![mark(&ids[0], None)])
            },
        );
        assert_eq!(r.travel_cost, Some(20_000));
        assert!(r
            .summary_rows
            .iter()
            .any(|row| row.label == "遠征費" && row.value == format_yen(20_000)));
    }

    #[test]
    fn offer_year_is_december_and_january() {
        assert_eq!(year_report_offer_year("2026-12-01"), Some(2026));
        assert_eq!(year_report_offer_year("2027-01-20"), Some(2026));
        assert_eq!(year_report_offer_year("2026-11-30"), None);
        assert_eq!(year_report_offer_year("壊れた"), None);
    }

    #[test]
    fn years_are_newest_first_and_not_in_the_future() {
        let snap = bundle_snapshot();
        let (year, ids) = shows_in_a_year(1);
        let marks = vec![mark(&ids[0], None)];
        assert_eq!(
            year_report_years(&snap, &marks, &[], &format!("{year}-12-31")),
            vec![year]
        );
        assert!(year_report_years(&snap, &marks, &[], &format!("{}-12-31", year - 1)).is_empty());
    }
}
