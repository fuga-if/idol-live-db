//! カレンダー表示のクエリ群 (SQL 時代の一覧を Snapshot 上の純粋関数へ移送)。
//!
//! SQL 時代の対応: iOS `AppDatabase+CalendarQueries.fetchCalendarEntriesAsync`
//! (= `CalendarReading` ポートの唯一のメソッド `calendarEntries(in:)` の全実装)。
//! 6 系統を 1 呼び出しで返す (FFI は 1 ユーザー操作 = 1 呼び出し):
//! - 公演:   `SELECT s.*, e.name, e.brand_id, e.kind, b.color FROM shows s JOIN events e
//!            LEFT JOIN brands b WHERE s.date >= ? AND s.date <= ? ORDER BY s.date, s.sort_order`
//! - リリース: `songs WHERE release_date BETWEEN 範囲 AND parent_song_id IS NULL
//!            ORDER BY release_date, title_kana` を同日 1 エントリへグループ化
//! - 誕生日 (アイドル / スタッフ): birthday `'--MM-DD'` を表示範囲の年に展開 (Swift 側ロジック)
//! - 記念日: anniversaries.date `'YYYY-MM-DD'` の月日を表示範囲の年に展開し、起点年以降のみ
//! - チケット: events のチケット 3 日付から受付期間帯 / 締切点 / 当落点を導出
//!
//! ## 範囲の受け方
//! **JST の日付文字列 (YYYY-MM-DD)・両端含む** で受ける。SQL 時代の比較は
//! 公演・チケットが文字列、誕生日・記念日が JST 深夜 0 時の `Date` だったが、
//! 深夜 0 時同士の Date 比較は同じ表記の文字列比較と一致する。端末が非 JST のときだけ
//! Swift 版は interval 境界が現地深夜になり半日ずれ得たが、それは「日付判定は JST 固定」
//! 方針 (jst_day.rs) からの逸脱なので、本移送で全カテゴリを文字列比較に統一して固定する。
//!
//! ## SQL / Foundation の暗黙挙動をコードで明示して固定する
//! - `ORDER BY` の NULL 位置: ASC で NULL 先頭 (title_kana)。Rust の `Option` (None < Some) と同じ。
//! - 文字列比較は BINARY 照合 = バイト列比較。Rust の `str` の `Ord` と同じ。
//! - 非閏年の 2/29 (誕生日・記念日) は 2/28 に出す ([`month_day_in_year`]、Q-08j)。
//!   出現日は `occurs_on` に入れて返すので、View 側で月日を展開し直さない。
//! - SQL が未規定だった同順位の並びは投入順 (= テーブル出現順 = 読み込み順。主キー順) を
//!   安定ソートで保って決定的にする (プラットフォーム間で同一結果を返すのが共有コアの目的)。
//!
//! ## 最終整列 (Swift `assembleCalendarEntries` の写し)
//! (ソート日付, カテゴリ順位) の安定ソート。ソート日付は誕生日系のみ「展開した実出現日」、
//! 記念日は **起点日そのもの** (`CalendarEntry.dateString` = `ann.date`)。起点日は表示範囲より
//! 過去年なので、記念日は日グループ化後に常にその日の先頭へ来る — これは SQL 時代からの
//! 表示仕様であり、ここでも変えずに固定する。

use crate::domain::snapshot::Snapshot;
use chrono::NaiveDate;

/// チケット日程の種別 (iOS `TicketDateKind` の 1:1 対応)。
///
/// 名前を iOS 側と揃えていないのは意図的: 生成バインディングがアプリと同一モジュールに
/// 入るため、既存 Swift 型と衝突する (song_list_queries.rs の前例と同じ判断)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CalendarTicketKind {
    /// 申込締切
    Deadline,
    /// 当落発表
    Lottery,
}

/// カレンダー 1 エントリの射影 (iOS `CalendarEntry` 対応。`personal` はアプリ内専用なので無い)。
///
/// 公演は SQL の SELECT 列をそのまま射影で持つ (JOIN 済みなのでプラットフォーム側の
/// 再クエリ不要)。リリース / 誕生日 / 記念日は id で返し、実体化 (Record 取得) は
/// プラットフォーム側が自国の store で行う (Phase 2 の一覧系と同じ流儀)。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq, Hash)]
pub enum CalendarEntryRecord {
    /// 公演 (iOS `CalendarShowRow`)。
    Show {
        show_id: String,
        event_id: String,
        name: String,
        /// YYYY-MM-DD
        date: String,
        venue: Option<String>,
        venue_city: Option<String>,
        start_time: Option<String>,
        sort_order: i64,
        performer_type: Option<String>,
        event_name: String,
        brand_id: Option<String>,
        brand_color: Option<String>,
        /// 親イベントの kind ("live" / "festival" / "release_event" / "radio" / "stream")
        event_kind: String,
    },
    /// 同日リリース曲まとめ。song_ids は title_kana 昇順 (NULL 先頭)。
    Release { date: String, song_ids: Vec<String> },
    /// アイドル誕生日。occurs_on は '--MM-DD' を表示範囲の年に展開した実出現日。
    Birthday { idol_id: String, occurs_on: String },
    /// スタッフ (アイドル本人ではない関係者) の誕生日。
    StaffBirthday { staff_id: String, occurs_on: String },
    /// ブランド/アプリ記念日。occurs_on は展開後の出現日 (N 周年の当日)。
    Anniversary { anniversary_id: String, occurs_on: String },
    /// チケットの期限日 (申込締切 / 当落発表)。1 つの受付 (`ticket_sales` の 1 行) につき
    /// 0〜2 点。受付の期間そのもの (いつからいつまで) はカレンダーには引かず、
    /// チケットの画面 ([`crate::domain::ticket_sales::ticket_board`]) にまとめる。
    Ticket {
        event_id: String,
        event_name: String,
        brand_color: Option<String>,
        date: String,
        kind: CalendarTicketKind,
        /// 申込リンク (`ticket_sales.url`)。
        url: Option<String>,
        sale_id: String,
        sale_name: String,
        sale_kind: crate::domain::ticket_sales::TicketSaleKind,
        /// 表示文字列 (`"{event_name} ({sale_name})"`、M2)。プラットフォーム側は
        /// `event_name` / `sale_name` から組み立て直さず、これをそのまま出す。
        label: String,
    },
    /// 配信のアーカイブ (見逃し配信) を見られる最後の日。同じライブで期間の同じ券種は
    /// 1 つにまとめてある ([`crate::domain::stream_archives`])。
    ArchiveEnd {
        event_id: String,
        event_name: String,
        brand_color: Option<String>,
        /// YYYY-MM-DD
        date: String,
        /// 対象の公演 (日付順)。
        show_ids: Vec<String>,
        /// 対象公演の短い名 (`DAY1` 等)。公演が 1 つしかないライブでは空。
        show_labels: Vec<String>,
        /// 表示文字列 (`"{event_name} (DAY1・DAY2 アーカイブ)"`)。
        label: String,
    },
}

// 同日内の表示順位 (iOS `CalendarEntry.sortOrder` と同じ数値。personal=7 はアプリ内のみ)。
// 0 は以前の受付期間の帯 (廃止) が使っていた。
const RANK_TICKET: u8 = 1;
const RANK_SHOW: u8 = 2;
const RANK_RELEASE: u8 = 3;
const RANK_ANNIVERSARY: u8 = 4;
const RANK_BIRTHDAY: u8 = 5;
const RANK_STAFF_BIRTHDAY: u8 = 6;

/// (ソートキー, 順位, エントリ)。ソートキーは Swift `sortDateString` の再現
/// (誕生日系 = 展開した実出現日 / 記念日 = 起点日 / それ以外 = 開始日付)。
type Keyed = (String, u8, CalendarEntryRecord);

/// 記念日の周年 (出現日の年 − 起点の年)。iOS `Anniversary.anniversaryYears(in:)` と同じ引き算。
/// 当年は 0。
pub fn anniversary_years(origin_date: &str, occurs_on: &str) -> i32 {
    let year = |d: &str| d.get(0..4).and_then(|y| y.parse::<i32>().ok()).unwrap_or(0);
    year(occurs_on) - year(origin_date)
}

/// 表示範囲 [start_day, end_day] (JST 日付・両端含む) の全カレンダーエントリ。
/// SQL 時代の `fetchCalendarEntriesAsync(in:)` 相当。
pub fn calendar_entries(snap: &Snapshot, start_day: &str, end_day: &str) -> Vec<CalendarEntryRecord> {
    let mut keyed: Vec<Keyed> = Vec::new();
    // 投入順は Swift `assembleCalendarEntries` の連結順。安定ソートなので
    // (キー, 順位) が同値の並びはこの投入順のまま残り、決定的になる。
    collect_shows(snap, start_day, end_day, &mut keyed);
    collect_releases(snap, start_day, end_day, &mut keyed);
    collect_birthdays(snap, start_day, end_day, &mut keyed);
    collect_staff_birthdays(snap, start_day, end_day, &mut keyed);
    collect_anniversaries(snap, start_day, end_day, &mut keyed);
    collect_tickets(snap, start_day, end_day, &mut keyed);
    collect_archives(snap, start_day, end_day, &mut keyed);
    keyed.sort_by(|a, b| (a.0.as_str(), a.1).cmp(&(b.0.as_str(), b.1)));
    keyed.into_iter().map(|(_, _, entry)| entry).collect()
}

/// [start_day, end_day] を両端含む範囲判定 (SQL の `>= ? AND <= ?` と同じ)。
fn in_range(day: &str, start_day: &str, end_day: &str) -> bool {
    day >= start_day && day <= end_day
}

// ---- 公演 ----

/// `WHERE s.date >= ? AND s.date <= ? ORDER BY s.date, s.sort_order` を
/// 前計算済みの並び (shows_in_date_order) の二分探索で切り出す。
fn collect_shows(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    let order = &snap.shows_in_date_order;
    let lo = order.partition_point(|&i| snap.shows[i as usize].date.as_str() < start_day);
    let hi = order.partition_point(|&i| snap.shows[i as usize].date.as_str() <= end_day);
    // start > end の逆転範囲は lo > hi になり得る (SQL なら空)。get で空に落とす。
    for &si in order.get(lo..hi).unwrap_or(&[]) {
        let show = &snap.shows[si as usize];
        // JOIN events: スナップショットは FK 孤児をロード時に捨てるので必ず居る。
        let event = &snap.events[show.event as usize];
        out.push((
            show.date.clone(),
            RANK_SHOW,
            CalendarEntryRecord::Show {
                show_id: show.id.clone(),
                event_id: event.id.clone(),
                name: show.name.clone(),
                date: show.date.clone(),
                venue: show.venue.clone(),
                venue_city: show.venue_city.clone(),
                start_time: show.start_time.clone(),
                sort_order: show.sort_order,
                performer_type: show.performer_type.clone(),
                event_name: event.name.clone(),
                brand_id: event.brand_id.clone(),
                brand_color: brand_color(snap, event.brand_id.as_deref()),
                event_kind: event.kind.clone(),
            },
        ));
    }
}

/// `LEFT JOIN brands b ON e.brand_id = b.id` の b.color 相当 (不明ブランドは NULL)。
fn brand_color(snap: &Snapshot, brand_id: Option<&str>) -> Option<String> {
    brand_id.and_then(|id| snap.brand(id)).and_then(|b| b.color.clone())
}

// ---- リリース ----

/// リリース日が範囲内の原曲 (parent_song_id IS NULL) を同日 1 エントリへ。
///
/// Swift は Dictionary でグループ化して順序不定のまま最終整列に任せていた
/// (日付はグループ内で一意なので結果は決定的)。ここでは最初から日付順に積む。
fn collect_releases(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    let mut hits: Vec<u32> = (0..snap.songs.len() as u32)
        .filter(|&i| {
            let song = &snap.songs[i as usize];
            song.parent_song_id.is_none()
                && song
                    .release_date
                    .as_deref()
                    .is_some_and(|d| in_range(d, start_day, end_day))
        })
        .collect();
    // ORDER BY release_date, title_kana (ASC = NULL 先頭)。同値は添字 (= 読み込み順。主キー順) で決定的に。
    hits.sort_by(|&a, &b| {
        let (sa, sb) = (&snap.songs[a as usize], &snap.songs[b as usize]);
        (&sa.release_date, &sa.title_kana, a).cmp(&(&sb.release_date, &sb.title_kana, b))
    });
    let mut i = 0;
    while i < hits.len() {
        let date = snap.songs[hits[i] as usize]
            .release_date
            .clone()
            .expect("release_date 有りで絞り込み済み");
        let mut song_ids = Vec::new();
        while i < hits.len()
            && snap.songs[hits[i] as usize].release_date.as_deref() == Some(date.as_str())
        {
            song_ids.push(snap.songs[hits[i] as usize].id.clone());
            i += 1;
        }
        out.push((date.clone(), RANK_RELEASE, CalendarEntryRecord::Release { date, song_ids }));
    }
}

// ---- 誕生日 (アイドル / スタッフ共通の月日展開) ----

/// 範囲先頭日の年。Swift は `jst.component(.year, from: interval.start)` だが、
/// start_day は同じ瞬間の JST 表記なので先頭 4 桁と常に一致する。
fn grid_year(start_day: &str) -> Option<i32> {
    start_day.get(..4)?.parse().ok()
}

/// "MM-DD" を (月, 日) へ。Swift `split(separator:)` は空要素を捨てるので同じ挙動に固定。
fn parse_month_day(md: &str) -> Option<(u32, i64)> {
    let mut parts = md.split('-').filter(|p| !p.is_empty());
    let month = parts.next()?.parse().ok()?;
    let day = parts.next()?.parse().ok()?;
    // 3 要素以上は Swift の parts.count == 2 ガードで弾かれていた。
    if parts.next().is_some() {
        return None;
    }
    Some((month, day))
}

/// 毎年めぐる月日 (誕生日・記念日) の、その年の日付 (Q-08j / Q-08m)。
///
/// **非閏年の 2/29 は 2/28** に出す (2 月のうちに祝う。3/1 に繰り越すと月が変わる)。
/// それ以外の実在しない月日 (2/30 など) は `None`。カレンダーと通知の予定表が同じ規則を使う。
///
/// 以前は Foundation の `Calendar.date(from:)` の繰り越しを写して 3/1 に出し、
/// 「繰り越し先が範囲外のときだけ 2/28」に落としていた (閏年でも 2/29 が範囲外なら
/// 2/28 に出る、という到達条件の副作用まであった)。iOS の View とコアのコメントが
/// 逆のことを言っていたのを、ここで 1 つに決める。
pub fn month_day_in_year(year: i32, month: u32, day: u32) -> Option<String> {
    let date = NaiveDate::from_ymd_opt(year, month, day).or_else(|| {
        (month == 2 && day == 29).then(|| NaiveDate::from_ymd_opt(year, 2, 28)).flatten()
    })?;
    Some(date.format("%Y-%m-%d").to_string())
}

/// '--MM-DD' を表示範囲内の年に展開する (iOS `expandMonthDay` の写し)。
///
/// WHY 候補 2 年: 月グリッドが前年 12 月から始まる月 (特に 1 月) では範囲先頭の年だけで
/// 解決すると年がずれて誕生日が丸ごと消える。範囲年 / 範囲年+1 の両方を試す。
fn expand_month_day(month_day: &str, start_day: &str, end_day: &str) -> Option<String> {
    let md = month_day.strip_prefix("--")?;
    let (month, day) = parse_month_day(md)?;
    let year = grid_year(start_day)?;
    [year, year + 1]
        .into_iter()
        .filter_map(|y| month_day_in_year(y, month, day.try_into().ok()?))
        .find(|date| in_range(date, start_day, end_day))
}

/// アイドル誕生日 (`Idol.filter(birthday != nil)` — is_external も対象。SQL 時代と同じ)。
fn collect_birthdays(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    for idol in &snap.idols {
        let Some(birthday) = idol.birthday.as_deref() else { continue };
        let Some(occurs_on) = expand_month_day(birthday, start_day, end_day) else { continue };
        out.push((
            occurs_on.clone(),
            RANK_BIRTHDAY,
            CalendarEntryRecord::Birthday { idol_id: idol.id.clone(), occurs_on },
        ));
    }
}

/// スタッフ誕生日 (アイドルと同じ月日展開)。
fn collect_staff_birthdays(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    for staff in &snap.staff {
        let Some(birthday) = staff.birthday.as_deref() else { continue };
        let Some(occurs_on) = expand_month_day(birthday, start_day, end_day) else { continue };
        out.push((
            occurs_on.clone(),
            RANK_STAFF_BIRTHDAY,
            CalendarEntryRecord::StaffBirthday { staff_id: staff.id.clone(), occurs_on },
        ));
    }
}

// ---- 記念日 ----

/// "YYYY-MM-DD" (ゼロ埋め 10 桁) の厳密な暦日か。
///
/// Swift は DateFormatter "yyyy-MM-dd" (非 lenient) で検証していた。実データは全て
/// ゼロ埋め 10 桁の実在日 (照合テストで確認) なので、この形へ明示的に固定する。
fn is_strict_day(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return false;
    }
    if !b.iter().enumerate().all(|(i, &c)| matches!(i, 4 | 7) || c.is_ascii_digit()) {
        return false;
    }
    let year: i32 = s[..4].parse().expect("全桁数字を確認済み");
    let month: u32 = s[5..7].parse().expect("全桁数字を確認済み");
    let day: u32 = s[8..10].parse().expect("全桁数字を確認済み");
    NaiveDate::from_ymd_opt(year, month, day).is_some()
}

/// "YYYY-MM-DD" から (月, 日)。Swift の `parts.count == 3` ガードと同じ。
fn parse_anniversary_month_day(date: &str) -> Option<(u32, i64)> {
    let mut parts = date.split('-').filter(|p| !p.is_empty());
    let _year = parts.next()?;
    let month = parts.next()?.parse().ok()?;
    let day = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((month, day))
}

/// 記念日: 起点日 YYYY-MM-DD の MM-DD を範囲内の年に展開し、起点年以降だけ採用
/// (起点より前の年は周年として意味を成さない。起点年当日 = 0 周年は出す)。
///
/// ソートキーは起点日そのもの (Swift `CalendarEntry.dateString` の仕様。誕生日と違い
/// resolvedOccurrence に退避されないため、記念日は日グループ内で常に先頭へ来る)。
/// 非閏年の 2/29 起点は 2/28 に出る ([`month_day_in_year`])。
fn collect_anniversaries(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    let Some(year) = grid_year(start_day) else { return };
    for ann in &snap.anniversaries {
        // Swift: parseDate(ann.date) 失敗 (= 厳密な暦日でない) は guard で捨てる。
        if !is_strict_day(&ann.date) {
            continue;
        }
        let Some((month, day)) = parse_anniversary_month_day(&ann.date) else { continue };
        for y in [year, year + 1] {
            let Some(recurring) = u32::try_from(day).ok().and_then(|d| month_day_in_year(y, month, d)) else { continue };
            if recurring.as_str() < ann.date.as_str() {
                continue;
            }
            if in_range(&recurring, start_day, end_day) {
                out.push((
                    ann.date.clone(),
                    RANK_ANNIVERSARY,
                    CalendarEntryRecord::Anniversary {
                        anniversary_id: ann.id.clone(),
                        occurs_on: recurring,
                    },
                ));
                break;
            }
        }
    }
}

// ---- チケット ----

/// `ticket_sales` の日時列は `YYYY-MM-DD` か `YYYY-MM-DD HH:MM`。カレンダーは日単位なので
/// 時刻は落とし、厳密な暦日にパースできた値だけ採用する。
fn sale_day(raw: Option<&str>) -> Option<&str> {
    let raw = raw?;
    let day = raw.split(' ').next().unwrap_or(raw);
    is_strict_day(day).then_some(day)
}

/// チケットの期限日。1 つの受付 (席種だけ違う受付は束ねて 1 つ) につき、申込締切と当落発表を
/// それぞれ単日点にする (どちらも無ければ何も出さない)。受付開始と期間の帯は出さない:
/// 受付が何本も並ぶライブでカレンダーが帯で埋まり、公演が読めなくなるため。
///
/// 走査順は `ticket_sales_by_event` (= `ticket_sales::sort_sales` と同じ並び) で、
/// SQL 時代と同じく明示の ORDER BY は無い。同 (日付, 順位) の並びは走査順のまま残る。
fn collect_tickets(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    for (ei, event) in snap.events.iter().enumerate() {
        let color = brand_color(snap, event.brand_id.as_deref());
        // 席種だけ違う受付は 1 点にまとめる (同じ日に同じライブの点が並ばないように)。
        for group in crate::domain::ticket_sales::sale_groups(snap, ei as u32) {
            let sale = &snap.ticket_sales[group.members[0] as usize];
            let label = crate::domain::ticket_sales::calendar_sale_label(&event.name, &group.name_label);
            let points = [
                (sale_day(sale.ends_at.as_deref()), CalendarTicketKind::Deadline),
                (sale_day(sale.result_at.as_deref()), CalendarTicketKind::Lottery),
            ];
            for (day, kind) in points {
                let Some(date) = day.filter(|d| in_range(d, start_day, end_day)) else { continue };
                out.push((
                    date.to_owned(),
                    RANK_TICKET,
                    CalendarEntryRecord::Ticket {
                        event_id: event.id.clone(),
                        event_name: event.name.clone(),
                        brand_color: color.clone(),
                        date: date.to_owned(),
                        kind,
                        url: sale.url.clone(),
                        sale_id: sale.id.clone(),
                        sale_name: group.name_label.clone(),
                        sale_kind: sale.kind,
                        label: label.clone(),
                    },
                ));
            }
        }
    }
}

// ---- 配信のアーカイブ ----

/// アーカイブを見られる最後の日 (チケットの期限日と同じ順位)。
fn collect_archives(snap: &Snapshot, start_day: &str, end_day: &str, out: &mut Vec<Keyed>) {
    use crate::domain::stream_archives::{archive_windows, calendar_archive_label, window_show_labels};
    for window in archive_windows(snap) {
        let date = window.end.0.format("%Y-%m-%d").to_string();
        if !in_range(&date, start_day, end_day) {
            continue;
        }
        let event = &snap.events[window.event as usize];
        let show_labels = window_show_labels(snap, &window);
        out.push((
            date.clone(),
            RANK_TICKET,
            CalendarEntryRecord::ArchiveEnd {
                event_id: event.id.clone(),
                event_name: event.name.clone(),
                brand_color: brand_color(snap, event.brand_id.as_deref()),
                show_ids: window.shows.iter().map(|&si| snap.shows[si as usize].id.clone()).collect(),
                label: calendar_archive_label(&event.name, &show_labels),
                show_labels,
                date,
            },
        ));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{bundle_conn, bundle_snapshot};
    use std::collections::HashSet;

    /// ORDER BY キーが同値の区間を集合として比較する等価判定 (song_list_queries の前例と同じ)。
    /// SQLite のソータは安定でなく同値行の並びは未規定のため、キー列の一致 + 同値区間の
    /// メンバー一致を等価とみなす。
    fn assert_matches_up_to_ties<K>(label: &str, actual: &[(K, String)], expected: &[(K, String)])
    where
        K: PartialEq + std::fmt::Debug,
    {
        assert_eq!(actual.len(), expected.len(), "{label}: 件数");
        let mut start = 0;
        while start < expected.len() {
            let k = &expected[start].0;
            let mut end = start;
            while end < expected.len() && &expected[end].0 == k {
                end += 1;
            }
            let expected_group: HashSet<&String> =
                expected[start..end].iter().map(|(_, row)| row).collect();
            let actual_group: HashSet<&String> = actual[start..end]
                .iter()
                .inspect(|(ak, _)| assert_eq!(ak, k, "{label}: キー列"))
                .map(|(_, row)| row)
                .collect();
            assert_eq!(actual_group, expected_group, "{label}: キー {k:?} の同順位グループ");
            start = end;
        }
    }

    // ---- 公演の照合 (元 SQL vs スナップショット) ----

    /// iOS calendarShowsQuery の SQL をそのまま実行し、射影列を行文字列にして返す。
    fn run_original_shows_sql(start: &str, end: &str) -> Vec<((String, i64), String)> {
        let c = bundle_conn();
        let mut stmt = c
            .prepare(
                "SELECT s.id, s.event_id, s.name, s.date, s.venue, s.venue_city,
                        s.start_time, s.sort_order, s.performer_type,
                        e.name AS event_name, e.brand_id, e.kind AS event_kind,
                        b.color AS brand_color
                 FROM shows s
                 JOIN events e ON s.event_id = e.id
                 LEFT JOIN brands b ON e.brand_id = b.id
                 WHERE s.date >= ? AND s.date <= ?
                 ORDER BY s.date, s.sort_order",
            )
            .unwrap();
        stmt.query_map([start, end], |r| {
            let date: String = r.get(3)?;
            let sort_order: i64 = r.get(7)?;
            // 13 列はタプル 1 個に収まらない (Debug は 12 要素まで) ので 2 分割で文字列化。
            let row = format!(
                "{:?}|{:?}",
                (
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    &date,
                    r.get::<_, Option<String>>(4)?,
                    r.get::<_, Option<String>>(5)?,
                    r.get::<_, Option<String>>(6)?,
                ),
                (
                    sort_order,
                    r.get::<_, Option<String>>(8)?,
                    r.get::<_, String>(9)?,
                    r.get::<_, Option<String>>(10)?,
                    r.get::<_, String>(11)?,
                    r.get::<_, Option<String>>(12)?,
                )
            );
            Ok(((date, sort_order), row))
        })
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap()
    }

    /// 出力から Show エントリだけを SQL と同じ行文字列に落とす。
    fn show_rows(entries: &[CalendarEntryRecord]) -> Vec<((String, i64), String)> {
        entries
            .iter()
            .filter_map(|e| match e {
                CalendarEntryRecord::Show {
                    show_id,
                    event_id,
                    name,
                    date,
                    venue,
                    venue_city,
                    start_time,
                    sort_order,
                    performer_type,
                    event_name,
                    brand_id,
                    brand_color,
                    event_kind,
                } => Some((
                    (date.clone(), *sort_order),
                    format!(
                        "{:?}|{:?}",
                        (show_id, event_id, name, date, venue, venue_city, start_time),
                        (*sort_order, performer_type, event_name, brand_id, event_kind, brand_color)
                    ),
                )),
                _ => None,
            })
            .collect()
    }

    fn assert_shows_match(start: &str, end: &str, expect_nonempty: bool) {
        let entries = calendar_entries(bundle_snapshot(), start, end);
        let actual = show_rows(&entries);
        let expected = run_original_shows_sql(start, end);
        if expect_nonempty {
            assert!(!expected.is_empty(), "[{start}..{end}] に公演が無い前提が崩れた");
        }
        assert_matches_up_to_ties(&format!("shows {start}..{end}"), &actual, &expected);
    }

    #[test]
    fn shows_match_sql_over_a_full_year() {
        assert_shows_match("2018-01-01", "2018-12-31", true);
    }

    #[test]
    fn shows_match_sql_at_history_boundaries() {
        // 最古公演 (2004-12-27) を境界に含む / データ以前は空
        assert_shows_match("2004-12-01", "2004-12-27", true);
        assert_shows_match("1990-01-01", "2003-12-31", false);
        let entries = calendar_entries(bundle_snapshot(), "1990-01-01", "2003-12-31");
        assert!(show_rows(&entries).is_empty());
    }

    // ---- リリースの照合 ----

    /// 日付グループ 1 つ: (release_date, [(title_kana, song_id)])。
    type ReleaseGroup = (String, Vec<(Option<String>, String)>);

    /// 元 SQL: release_date 範囲 + 原曲のみ + ORDER BY release_date, title_kana。
    /// 日付グループ (エントリ単位) に畳んで返す。
    fn run_original_releases_sql(start: &str, end: &str) -> Vec<ReleaseGroup> {
        let c = bundle_conn();
        let mut stmt = c
            .prepare(
                "SELECT release_date, title_kana, id FROM songs
                 WHERE release_date >= ? AND release_date <= ? AND parent_song_id IS NULL
                 ORDER BY release_date, title_kana",
            )
            .unwrap();
        let rows: Vec<(String, Option<String>, String)> = stmt
            .query_map([start, end], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let mut groups: Vec<ReleaseGroup> = Vec::new();
        for (date, kana, id) in rows {
            match groups.last_mut() {
                Some((d, ids)) if *d == date => ids.push((kana, id)),
                _ => groups.push((date, vec![(kana, id)])),
            }
        }
        groups
    }

    fn assert_releases_match(start: &str, end: &str, expect_nonempty: bool) {
        let entries = calendar_entries(bundle_snapshot(), start, end);
        let actual: Vec<(String, Vec<String>)> = entries
            .iter()
            .filter_map(|e| match e {
                CalendarEntryRecord::Release { date, song_ids } => {
                    Some((date.clone(), song_ids.clone()))
                }
                _ => None,
            })
            .collect();
        let expected = run_original_releases_sql(start, end);
        if expect_nonempty {
            assert!(!expected.is_empty(), "[{start}..{end}] にリリースが無い前提が崩れた");
        }
        assert_eq!(actual.len(), expected.len(), "releases {start}..{end}: 日数");
        for ((a_date, a_ids), (e_date, e_rows)) in actual.iter().zip(expected.iter()) {
            assert_eq!(a_date, e_date, "releases {start}..{end}: 日付順");
            // グループ内は title_kana 順。同かなは未規定 → キー付きで同値区間を集合比較。
            let a_rows: Vec<(Option<String>, String)> = a_ids
                .iter()
                .map(|id| {
                    let song = &bundle_snapshot().songs[bundle_snapshot().song_index_by_id[id] as usize];
                    (song.title_kana.clone(), id.clone())
                })
                .collect();
            assert_matches_up_to_ties(&format!("releases {e_date}"), &a_rows, e_rows);
        }
    }

    #[test]
    fn releases_match_sql_over_full_history() {
        assert_releases_match("0000-01-01", "9999-12-31", true);
    }

    #[test]
    fn releases_match_sql_on_a_single_day() {
        // 1 か月レンジの先頭グループと単日レンジが一致する (境界の含み方の固定)
        let month = run_original_releases_sql("2015-04-01", "2015-04-30");
        let (first_day, _) = &month[0];
        assert_releases_match(first_day, first_day, true);
        assert_releases_match("2015-04-31", "2015-04-31", false); // 実在しない日は空 (文字列比較)
    }

    // ---- チケットの照合 ----
    //
    // 同梱 DB の ticket_sales は空 (移行データの投入は別担当) なので、bundle_snapshot() との
    // SQL 照合ではなく、手組みのスナップショット (snapshot_build::build) で仕様を固定する。

    fn ticket_test_snapshot(sales: Vec<crate::domain::snapshot::TicketSaleRow>) -> Snapshot {
        archive_test_snapshot(sales, vec![], vec![])
    }

    fn archive_test_snapshot(
        sales: Vec<crate::domain::snapshot::TicketSaleRow>,
        shows: Vec<crate::domain::snapshot::Show>,
        show_archives: Vec<crate::domain::snapshot::ShowArchiveRow>,
    ) -> Snapshot {
        use crate::domain::snapshot::{Brand, Event};
        use crate::domain::snapshot_build::{build, RawTables};
        let event = |id: &str, name: &str| Event {
            id: id.into(),
            brand_id: Some("cg".into()),
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
        };
        build(RawTables {
            songs: vec![],
            idols: vec![],
            events: vec![event("e1", "10th LIVE")],
            units: vec![],
            brands: vec![Brand {
                id: "cg".into(),
                name: "シンデレラガールズ".into(),
                short_name: "デレマス".into(),
                color: Some("#ff69b4".into()),
                sort_order: 0,
                icon_url: None,
            }],
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
            ticket_sales: sales,
            show_archives,
            idol_facets: vec![],
            idol_hairstyles: vec![],
            song_artists: vec![],
            setlist_performers: vec![],
            show_cast: vec![],
            show_cast_performers: vec![],
            unit_members: vec![],
            idol_brands: vec![],
        })
    }

    #[test]
    fn archive_end_folds_same_period_tickets() {
        use crate::domain::snapshot::{Show, ShowArchiveRow};
        let show = |id: &str, name: &str, date: &str| Show {
            id: id.into(),
            event: 0,
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
        };
        let archive = |ticket_id: &str, show: u32| ShowArchiveRow {
            ticket_id: ticket_id.into(),
            show,
            archive_starts_at: Some("2026-09-28 18:00".into()),
            archive_ends_at: Some("2026-10-05 23:59".into()),
        };
        let snap = archive_test_snapshot(
            vec![],
            vec![show("s1", "10th LIVE DAY1", "2026-09-27"), show("s2", "10th LIVE DAY2", "2026-09-28")],
            vec![archive("t1", 0), archive("t2", 1), archive("t3", 1)],
        );
        let ends: Vec<_> = calendar_entries(&snap, "2026-10-01", "2026-10-31")
            .into_iter()
            .filter(|e| matches!(e, CalendarEntryRecord::ArchiveEnd { .. }))
            .collect();
        assert_eq!(ends.len(), 1, "期間の同じ券種は 1 つにまとめ、終わりの日だけ出す");
        match &ends[0] {
            CalendarEntryRecord::ArchiveEnd { date, show_ids, show_labels, label, brand_color, .. } => {
                assert_eq!(date, "2026-10-05");
                assert_eq!(show_ids, &vec!["s1".to_string(), "s2".to_string()]);
                assert_eq!(show_labels, &vec!["DAY1".to_string(), "DAY2".to_string()]);
                assert_eq!(label, "10th LIVE (DAY1・DAY2 アーカイブ)");
                assert_eq!(brand_color.as_deref(), Some("#ff69b4"));
            }
            other => panic!("unexpected {other:?}"),
        }
        assert!(calendar_entries(&snap, "2026-09-01", "2026-10-04")
            .iter()
            .all(|e| !matches!(e, CalendarEntryRecord::ArchiveEnd { .. })), "期間の途中の日には出さない");
    }

    fn sale_row(
        id: &str,
        kind: crate::domain::ticket_sales::TicketSaleKind,
        name: &str,
        starts_at: Option<&str>,
        ends_at: Option<&str>,
        result_at: Option<&str>,
    ) -> crate::domain::snapshot::TicketSaleRow {
        crate::domain::snapshot::TicketSaleRow {
            id: id.into(),
            event: 0,
            show_ids: vec![],
            kind,
            name: name.into(),
            starts_at: starts_at.map(str::to_string),
            ends_at: ends_at.map(str::to_string),
            result_at: result_at.map(str::to_string),
            url: Some("https://example.com/apply".into()),
            note: None,
            source_url: "https://example.com/info".into(),
            sort_order: 0,
        }
    }

    fn ticket_entries(snap: &Snapshot, start: &str, end: &str) -> Vec<CalendarEntryRecord> {
        calendar_entries(snap, start, end)
            .into_iter()
            .filter(|e| matches!(e, CalendarEntryRecord::Ticket { .. }))
            .collect()
    }

    #[test]
    fn a_sale_shows_only_its_deadline_and_result_days() {
        use crate::domain::ticket_sales::TicketSaleKind;
        let snap = ticket_test_snapshot(vec![sale_row(
            "t1", TicketSaleKind::Lottery, "先行抽選", Some("2026-04-01"), Some("2026-04-12 23:59"), Some("2026-04-20"),
        )]);
        let entries = ticket_entries(&snap, "2026-01-01", "2026-12-31");
        assert_eq!(entries.len(), 2, "締切と当落の 2 点だけ (受付開始と期間は出さない)");
        match &entries[0] {
            CalendarEntryRecord::Ticket { date, kind, sale_id, sale_name, sale_kind, url, label, .. } => {
                assert_eq!(date, "2026-04-12", "時刻は落として日付で出す");
                assert_eq!(*kind, CalendarTicketKind::Deadline);
                assert_eq!(sale_id, "t1");
                assert_eq!(sale_name, "先行抽選");
                assert_eq!(*sale_kind, TicketSaleKind::Lottery);
                assert_eq!(url.as_deref(), Some("https://example.com/apply"));
                // M2: 表示文字列はコアで組み切る (ライブ名が抜け落ちないようにする)。
                assert_eq!(label, "10th LIVE (先行抽選)");
            }
            other => panic!("締切の点を期待: {other:?}"),
        }
        assert!(matches!(
            &entries[1],
            CalendarEntryRecord::Ticket { date, kind: CalendarTicketKind::Lottery, .. } if date == "2026-04-20"
        ));
        assert!(ticket_entries(&snap, "2026-04-02", "2026-04-11").is_empty(), "受付期間の途中の日には出さない");
    }

    #[test]
    fn a_sale_without_deadline_or_result_has_no_point() {
        // 受付開始だけの受付 (当日券など) はカレンダーに出さない。期間はチケットの画面で見る。
        use crate::domain::ticket_sales::TicketSaleKind;
        let snap = ticket_test_snapshot(vec![sale_row(
            "t1", TicketSaleKind::SameDay, "当日券", Some("2026-04-20"), None, None,
        )]);
        assert!(ticket_entries(&snap, "2026-01-01", "2026-12-31").is_empty());
    }

    #[test]
    fn multiple_sales_on_the_same_event_all_appear_independently() {
        // 1 つのライブに複数受付があっても、それぞれ別のエントリとして出る
        // (受付を event 単位に潰していた旧実装では後発が先発を上書きしていた)。
        use crate::domain::ticket_sales::TicketSaleKind;
        let snap = ticket_test_snapshot(vec![
            sale_row("t1", TicketSaleKind::Lottery, "先行抽選", Some("2026-03-01"), Some("2026-03-10"), Some("2026-03-15")),
            sale_row("t2", TicketSaleKind::FirstCome, "一般先着", Some("2026-03-20"), Some("2026-03-25"), None),
        ]);
        let entries = ticket_entries(&snap, "2026-01-01", "2026-12-31");
        let keys: Vec<(String, u8)> = entries.iter().map(sort_key_of).collect();
        assert!(keys.windows(2).all(|w| w[0] <= w[1]), "チケットも他カテゴリと同じ (日付, 順位) 安定ソートに従う");
        let sale_ids: HashSet<&str> = entries
            .iter()
            .map(|e| match e {
                CalendarEntryRecord::Ticket { sale_id, .. } => sale_id.as_str(),
                _ => unreachable!(),
            })
            .collect();
        assert_eq!(sale_ids, HashSet::from(["t1", "t2"]));
    }

    #[test]
    fn a_sale_with_no_dates_produces_no_calendar_entry() {
        use crate::domain::ticket_sales::TicketSaleKind;
        let snap = ticket_test_snapshot(vec![sale_row("t1", TicketSaleKind::Resale, "リセール", None, None, None)]);
        assert!(ticket_entries(&snap, "2000-01-01", "2100-12-31").is_empty());
    }

    // ---- 誕生日の照合 (アイドル / スタッフ) ----

    /// substr ベースの独立オラクル: 同一年内レンジ [Y-a, Y-b] なら
    /// 「MM-DD が [a, b] に入る行」が出現し、出現日は Y-MM-DD になる。
    /// (2/29 の繰り越しが絡まないレンジでのみ成立 — 各呼び出し側で保証する。)
    fn birthday_oracle_same_year(table: &str, year: &str, md_lo: &str, md_hi: &str) -> HashSet<(String, String)> {
        let c = bundle_conn();
        let mut stmt = c
            .prepare(&format!(
                "SELECT id, substr(birthday, 3) FROM {table}
                 WHERE birthday IS NOT NULL
                   AND substr(birthday, 3) >= ? AND substr(birthday, 3) <= ?"
            ))
            .unwrap();
        stmt.query_map([md_lo, md_hi], |r| {
            let id: String = r.get(0)?;
            let md: String = r.get(1)?;
            Ok((id, format!("{year}-{md}")))
        })
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap()
    }

    fn birthday_entries(entries: &[CalendarEntryRecord]) -> HashSet<(String, String)> {
        entries
            .iter()
            .filter_map(|e| match e {
                CalendarEntryRecord::Birthday { idol_id, occurs_on } => {
                    Some((idol_id.clone(), occurs_on.clone()))
                }
                _ => None,
            })
            .collect()
    }

    fn staff_birthday_entries(entries: &[CalendarEntryRecord]) -> HashSet<(String, String)> {
        entries
            .iter()
            .filter_map(|e| match e {
                CalendarEntryRecord::StaffBirthday { staff_id, occurs_on } => {
                    Some((staff_id.clone(), occurs_on.clone()))
                }
                _ => None,
            })
            .collect()
    }

    #[test]
    fn birthdays_match_sql_across_year_boundary() {
        // 1 月の月グリッド相当: 前年 12 月末〜当年 2 月頭。前年分は年 2025、当年分は 2026 に展開される。
        let entries = calendar_entries(bundle_snapshot(), "2025-12-28", "2026-02-07");
        let mut expected = birthday_oracle_same_year("idols", "2025", "12-28", "12-31");
        expected.extend(birthday_oracle_same_year("idols", "2026", "01-01", "02-07"));
        assert!(!expected.is_empty());
        assert_eq!(birthday_entries(&entries), expected);
        let mut staff_expected = birthday_oracle_same_year("staff", "2025", "12-28", "12-31");
        staff_expected.extend(birthday_oracle_same_year("staff", "2026", "01-01", "02-07"));
        assert_eq!(staff_birthday_entries(&entries), staff_expected);
    }

    #[test]
    fn birthdays_full_year_covers_everyone() {
        // 通年レンジでは誕生日持ち全員が 1 回ずつ出現する (2/29 も 3/1 繰り越しで年内に収まる)。
        // '--' 前置きの無い不正形式 (実データに 1 件: '07-26') は Swift の hasPrefix ガードと
        // 同じく出現しないので、オラクル側も GLOB で除外する。
        let c = bundle_conn();
        let idol_count: usize = c
            .query_row("SELECT COUNT(*) FROM idols WHERE birthday GLOB '--*'", [], |r| {
                r.get::<_, i64>(0)
            })
            .unwrap() as usize;
        let staff_count: usize = c
            .query_row("SELECT COUNT(*) FROM staff WHERE birthday GLOB '--*'", [], |r| {
                r.get::<_, i64>(0)
            })
            .unwrap() as usize;
        let entries = calendar_entries(bundle_snapshot(), "2026-01-01", "2026-12-31");
        let birthdays = birthday_entries(&entries);
        assert_eq!(birthdays.len(), idol_count);
        assert_eq!(staff_birthday_entries(&entries).len(), staff_count);
        assert!(birthdays.iter().all(|(_, d)| d.starts_with("2026-")));
    }

    #[test]
    fn expand_month_day_puts_feb_29_on_feb_28_in_common_years() {
        // 閏年: 2/29 はそのまま
        assert_eq!(
            expand_month_day("--02-29", "2024-02-01", "2024-03-10"),
            Some("2024-02-29".into())
        );
        // 非閏年: 2/28 に出る (Q-08j。以前は 3/1 に繰り越していた)
        assert_eq!(
            expand_month_day("--02-29", "2025-02-01", "2025-03-10"),
            Some("2025-02-28".into())
        );
        assert_eq!(expand_month_day("--02-29", "2025-03-01", "2025-03-31"), None, "3 月には出ない");
        // 閏年で 2/29 が範囲外なら出ない (2/28 に落とさない)
        assert_eq!(expand_month_day("--02-29", "2024-02-01", "2024-02-28"), None);
        assert_eq!(month_day_in_year(2025, 2, 30), None, "実在しない月日は出さない");
        // 12 月開始グリッドの 1 月誕生日は範囲年+1 に展開される
        assert_eq!(
            expand_month_day("--01-15", "2025-12-28", "2026-02-07"),
            Some("2026-01-15".into())
        );
        // 範囲に出現しない月日は None
        assert_eq!(expand_month_day("--06-15", "2025-12-28", "2026-02-07"), None);
        // '--' 前置きが無い形式は誕生日として扱わない
        assert_eq!(expand_month_day("02-29", "2024-02-01", "2024-03-10"), None);
    }

    // ---- 記念日の照合 ----

    /// substr ベースの独立オラクル: 同一年内レンジなら「MM-DD がレンジ内 かつ 起点年 <= Y」。
    /// (起点年以降ガード `recurring >= ann.date` は、月日が同じなので年比較に等しい。)
    fn anniversary_oracle_same_year(year: &str, md_lo: &str, md_hi: &str) -> HashSet<(String, String)> {
        let c = bundle_conn();
        let mut stmt = c
            .prepare(
                "SELECT id, substr(date, 6) FROM anniversaries
                 WHERE substr(date, 6) >= ? AND substr(date, 6) <= ?
                   AND substr(date, 1, 4) <= ?",
            )
            .unwrap();
        stmt.query_map([md_lo, md_hi, year], |r| {
            let id: String = r.get(0)?;
            let md: String = r.get(1)?;
            Ok((id, format!("{year}-{md}")))
        })
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap()
    }

    fn anniversary_entries(entries: &[CalendarEntryRecord]) -> Vec<(String, String)> {
        entries
            .iter()
            .filter_map(|e| match e {
                CalendarEntryRecord::Anniversary { anniversary_id, occurs_on } => {
                    Some((anniversary_id.clone(), occurs_on.clone()))
                }
                _ => None,
            })
            .collect()
    }

    #[test]
    fn anniversaries_match_sql_over_full_year() {
        // オラクルの前提: 2/29 起点の記念日が無い (あると繰り越しが絡み substr では表せない)
        let c = bundle_conn();
        let leap: i64 = c
            .query_row("SELECT COUNT(*) FROM anniversaries WHERE substr(date, 6) = '02-29'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(leap, 0, "2/29 起点が現れたらこのオラクルを見直すこと");

        let entries = calendar_entries(bundle_snapshot(), "2026-01-01", "2026-12-31");
        let actual = anniversary_entries(&entries);
        let expected = anniversary_oracle_same_year("2026", "01-01", "12-31");
        assert!(!expected.is_empty());
        assert_eq!(actual.iter().cloned().collect::<HashSet<_>>(), expected);
        // 並びは起点日 (ann.date) 昇順 — Swift dateString ソートの固定
        let origins: Vec<String> = actual
            .iter()
            .map(|(id, _)| {
                bundle_snapshot()
                    .anniversaries
                    .iter()
                    .find(|a| &a.id == id)
                    .expect("スナップショットに居る")
                    .date
                    .clone()
            })
            .collect();
        assert!(origins.windows(2).all(|w| w[0] <= w[1]), "起点日昇順が崩れている");
    }

    #[test]
    fn anniversaries_before_origin_year_are_hidden() {
        // 2006 年のレンジには起点 2006 年以前の記念日しか出ない (0 周年未満は非表示)
        let entries = calendar_entries(bundle_snapshot(), "2006-01-01", "2006-12-31");
        let expected = anniversary_oracle_same_year("2006", "01-01", "12-31");
        let actual = anniversary_entries(&entries);
        assert_eq!(actual.iter().cloned().collect::<HashSet<_>>(), expected);
        let full: i64 = bundle_conn()
            .query_row("SELECT COUNT(*) FROM anniversaries", [], |r| r.get(0))
            .unwrap();
        assert!(
            (actual.len() as i64) < full,
            "起点年ガードが効いていれば全 {full} 件は出ない"
        );
    }

    #[test]
    fn anniversaries_match_sql_across_year_boundary() {
        let entries = calendar_entries(bundle_snapshot(), "2026-12-27", "2027-02-06");
        let mut expected = anniversary_oracle_same_year("2026", "12-27", "12-31");
        expected.extend(anniversary_oracle_same_year("2027", "01-01", "02-06"));
        assert_eq!(
            anniversary_entries(&entries).into_iter().collect::<HashSet<_>>(),
            expected
        );
    }

    // ---- 最終整列の固定 ----

    /// 出力エントリから Swift `sortDateString` / `sortOrder` を再計算する。
    fn sort_key_of(entry: &CalendarEntryRecord) -> (String, u8) {
        match entry {
            CalendarEntryRecord::Show { date, .. } => (date.clone(), RANK_SHOW),
            CalendarEntryRecord::Release { date, .. } => (date.clone(), RANK_RELEASE),
            CalendarEntryRecord::Birthday { occurs_on, .. } => (occurs_on.clone(), RANK_BIRTHDAY),
            CalendarEntryRecord::StaffBirthday { occurs_on, .. } => {
                (occurs_on.clone(), RANK_STAFF_BIRTHDAY)
            }
            CalendarEntryRecord::Anniversary { anniversary_id, .. } => {
                let origin = bundle_snapshot()
                    .anniversaries
                    .iter()
                    .find(|a| &a.id == anniversary_id)
                    .expect("スナップショットに居る")
                    .date
                    .clone();
                (origin, RANK_ANNIVERSARY)
            }
            CalendarEntryRecord::Ticket { date, .. } => (date.clone(), RANK_TICKET),
            CalendarEntryRecord::ArchiveEnd { date, .. } => (date.clone(), RANK_TICKET),
        }
    }

    #[test]
    fn entries_are_sorted_like_swift_assemble() {
        let entries = calendar_entries(bundle_snapshot(), "2026-04-01", "2026-05-31");
        // 全カテゴリが混ざる busy レンジであること (テストの実効性の担保)
        assert!(entries.iter().any(|e| matches!(e, CalendarEntryRecord::Show { .. })));
        assert!(entries.iter().any(|e| matches!(e, CalendarEntryRecord::Birthday { .. })));
        // ticket_sales は同梱 DB では空 (移行データの投入は別担当) なので、チケットの
        // 混在は ticket_test_snapshot ベースの各テストで固定する。
        let keys: Vec<(String, u8)> = entries.iter().map(sort_key_of).collect();
        assert!(
            keys.windows(2).all(|w| w[0] <= w[1]),
            "(ソート日付, カテゴリ順位) の安定ソートが崩れている"
        );
        // 記念日は起点日 (過去年) がキーなので、範囲内日付のどのエントリよりも前に来る
        if let Some(first_non_ann) = entries
            .iter()
            .position(|e| !matches!(e, CalendarEntryRecord::Anniversary { .. }))
        {
            assert!(
                entries[first_non_ann..]
                    .iter()
                    .all(|e| !matches!(e, CalendarEntryRecord::Anniversary { .. })),
                "記念日 (起点日キー) が先頭ブロックに固まる現行仕様が崩れている"
            );
        }
    }

    #[test]
    fn inverted_range_yields_nothing() {
        // start > end は SQL なら空。二分探索の lo > hi で落ちないことの固定。
        let entries = calendar_entries(bundle_snapshot(), "2026-05-10", "2026-05-01");
        assert!(entries.is_empty());
    }

    #[test]
    fn strict_day_rejects_free_text() {
        assert!(is_strict_day("2026-06-13"));
        assert!(!is_strict_day("2026-06-31")); // 実在しない日
        assert!(!is_strict_day("2026-6-13")); // ゼロ埋めなし
        assert!(!is_strict_day("2026-06-13 以降順次")); // 自由記述
        assert!(!is_strict_day("未定"));
        assert!(!is_strict_day(""));
    }
}
