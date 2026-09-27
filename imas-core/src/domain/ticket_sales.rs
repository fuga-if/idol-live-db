//! チケット受付 (`ticket_sales`) の規則。純粋ロジック。
//!
//! # なぜ events の 3 列 (`ticket_open_date` / `ticket_deadline` / `ticket_lottery_date`) から
//! この表に切り出したか
//!
//! 1 つのライブに受付が複数あることが普通にある (先行抽選 → 一般先着 → リセール、等)。
//! イベント 1 行に日付 3 つでは 1 件しか持てず、複数受付のライブでは後発の受付が
//! 先発を上書きしてしまっていた。**受付は 1 件 1 行**にし、イベントとは 1 対多にする。
//!
//! # ここに置く判断
//!
//! - 日時の解釈: `YYYY-MM-DD` (その日の 00:00〜23:59 として扱う) と
//!   `YYYY-MM-DD HH:MM` (分刻みの厳密な時刻) のどちらも受ける。
//! - 段階の判定 (upcoming / open / awaiting_result / ended)。
//! - 並び順・「注目受付」(一番近い・一番大事なもの 1 件) の選び方。
//! - 編集フォームの入力検査と、その文言 (Swift/Kotlin に文言を二重管理させない)。
//!
//! 「今」は常に `now_epoch_seconds` で受け取り、[`crate::domain::jst_day`] と同じく
//! JST (UTC+9 固定) に直してから比べる。呼ぶたびに計算するのは、キャッシュすると
//! 日をまたいだときに段階が古いまま残るため。

use chrono::{DateTime, NaiveDate, NaiveDateTime};
use std::collections::HashSet;

use crate::domain::jst_day::jst;
use crate::domain::show_naming::distinguishing_show_name;
use crate::domain::snapshot::{Event, Snapshot};

// ---------------------------------------------------------------------------
// 型
// ---------------------------------------------------------------------------

/// 受付の種別 (`ticket_sales.kind`)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TicketSaleKind {
    /// 抽選。
    Lottery,
    /// 先着。
    FirstCome,
    /// リセール (公式の譲渡・再販売)。
    Resale,
    /// 当日券。
    SameDay,
}

/// 受付の段階。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TicketSaleStage {
    /// 受付開始より前。
    Upcoming,
    /// 受付中 (開始 〜 締切)。
    Open,
    /// 締切は過ぎたが、当落発表がまだ (または今日)。
    AwaitingResult,
    /// 終了 (発表済み、または発表の予定が無いまま締切を過ぎた)。
    Ended,
}

/// 検査・文言で使うフィールドの識別。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TicketSaleField {
    Name,
    StartsAt,
    EndsAt,
    ResultAt,
    Url,
    SourceUrl,
    ShowIds,
}

/// 画面用の 1 件の射影。段階・表示文字列はここで決め切って渡す
/// (Swift/Kotlin は組み立てず、そのまま出すだけにする)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketSale {
    pub id: String,
    pub event_id: String,
    pub event_name: String,
    /// 空 = 全公演対象。
    pub show_ids: Vec<String>,
    /// 対象公演の短い名 (`DAY1` 等)。全公演対象、または対象公演がマスタに見つからない場合は空。
    pub show_labels: Vec<String>,
    pub kind: TicketSaleKind,
    pub kind_label: String,
    pub name: String,
    pub starts_at: Option<String>,
    pub ends_at: Option<String>,
    pub result_at: Option<String>,
    pub url: Option<String>,
    pub note: Option<String>,
    pub source_url: String,
    pub sort_order: i64,
    pub stage: TicketSaleStage,
    pub stage_label: String,
    /// `"4/1 (水) 12:00 〜 4/12 (日) 23:59"`。日程が 1 つも無ければ `None`。
    pub period_label: Option<String>,
    /// `"4/15 (水)"`。`result_at` が無ければ `None`。
    pub result_label: Option<String>,
}

/// ウィジェット・通知の「締切一覧」用の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketSaleDeadline {
    pub sale_id: String,
    pub sale_name: String,
    pub event_id: String,
    pub event_name: String,
    pub brand_color: Option<String>,
    /// `YYYY-MM-DD`。
    pub deadline_day: String,
    /// `HH:MM`。時刻の指定が無い日付だけの締切は `None`。
    pub deadline_time: Option<String>,
}

/// 編集フォーム → 検査の材料。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketSaleDraft {
    pub event_id: String,
    /// 空 = 全公演対象。
    pub show_ids: Vec<String>,
    pub kind: TicketSaleKind,
    pub name: String,
    pub starts_at: Option<String>,
    pub ends_at: Option<String>,
    pub result_at: Option<String>,
    pub url: Option<String>,
    pub note: Option<String>,
    pub source_url: String,
    pub sort_order: i64,
}

/// 入力検査で見つかる問題。1 回の検査で複数出うる。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum TicketSaleIssue {
    Missing { field: TicketSaleField },
    BadMoment { field: TicketSaleField },
    NotHttp { field: TicketSaleField },
    EndsBeforeStarts,
    ResultBeforeEnds,
    UnknownShow { show_id: String },
    /// 受付開始・申込締切・当落発表のいずれも入力されていない。
    NoDates,
}

// ---------------------------------------------------------------------------
// 生値の変換
// ---------------------------------------------------------------------------

/// 受付種別の保存値 (`lottery` / `first_come` / `resale` / `same_day`)。
pub fn ticket_sale_kind_raw(kind: TicketSaleKind) -> String {
    ticket_sale_kind_raw_str(kind).to_string()
}

fn ticket_sale_kind_raw_str(kind: TicketSaleKind) -> &'static str {
    match kind {
        TicketSaleKind::Lottery => "lottery",
        TicketSaleKind::FirstCome => "first_come",
        TicketSaleKind::Resale => "resale",
        TicketSaleKind::SameDay => "same_day",
    }
}

/// 保存値 → 種別。知らない値は `None` (捏造しない。ローダはこれで落として件数だけ記録する)。
pub fn ticket_sale_kind_from_raw(raw: &str) -> Option<TicketSaleKind> {
    match raw {
        "lottery" => Some(TicketSaleKind::Lottery),
        "first_come" => Some(TicketSaleKind::FirstCome),
        "resale" => Some(TicketSaleKind::Resale),
        "same_day" => Some(TicketSaleKind::SameDay),
        _ => None,
    }
}

fn ticket_sale_stage_raw(stage: TicketSaleStage) -> &'static str {
    match stage {
        TicketSaleStage::Upcoming => "upcoming",
        TicketSaleStage::Open => "open",
        TicketSaleStage::AwaitingResult => "awaiting_result",
        TicketSaleStage::Ended => "ended",
    }
}

fn kind_label(kind: TicketSaleKind) -> String {
    let raw = ticket_sale_kind_raw_str(kind);
    crate::domain::vocabulary::TICKET_SALE_KINDS
        .iter()
        .find(|t| t.value == raw)
        .map(|t| t.label.to_string())
        .unwrap_or_default()
}

fn stage_label(stage: TicketSaleStage) -> String {
    let raw = ticket_sale_stage_raw(stage);
    crate::domain::vocabulary::TICKET_SALE_STAGES
        .iter()
        .find(|t| t.value == raw)
        .map(|t| t.label.to_string())
        .unwrap_or_default()
}

// ---------------------------------------------------------------------------
// 日時の解釈
// ---------------------------------------------------------------------------

/// `YYYY-MM-DD` または `YYYY-MM-DD HH:MM` を解釈する。前後の空白は許すが、
/// それ以外の形は `None` (捏造しない)。
pub fn parse_sale_moment(raw: &str) -> Option<(NaiveDate, Option<(u32, u32)>)> {
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    match raw.split_once(' ') {
        Some((d, t)) => {
            let date = NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()?;
            let (h, m) = t.split_once(':')?;
            let h: u32 = h.parse().ok()?;
            let m: u32 = m.parse().ok()?;
            if h > 23 || m > 59 {
                return None;
            }
            Some((date, Some((h, m))))
        }
        None => {
            let date = NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok()?;
            Some((date, None))
        }
    }
}

type Moment = (NaiveDate, Option<(u32, u32)>);

/// 開始側の既定時刻: 日付だけなら 00:00。
fn lower_bound(m: Moment) -> NaiveDateTime {
    let (h, mi) = m.1.unwrap_or((0, 0));
    m.0.and_hms_opt(h, mi, 0).expect("時刻は parse_sale_moment で検査済み")
}

/// 終端側の既定時刻: 日付だけなら 23:59 (その日いっぱいは有効)。
fn upper_bound(m: Moment) -> NaiveDateTime {
    let (h, mi) = m.1.unwrap_or((23, 59));
    m.0.and_hms_opt(h, mi, 59).expect("時刻は parse_sale_moment で検査済み")
}

/// epoch 秒 → JST の素の日時 (タイムゾーン情報を持たない比較用)。
fn now_naive(now_epoch_seconds: i64) -> NaiveDateTime {
    let utc = DateTime::from_timestamp(now_epoch_seconds, 0).unwrap_or(DateTime::UNIX_EPOCH);
    utc.with_timezone(&jst()).naive_local()
}

/// 段階の判定。
///
/// - 受付開始 (`starts_at`) より前 → [`TicketSaleStage::Upcoming`]。
/// - 開始から締切 (`ends_at`) まで (両端含む) → [`TicketSaleStage::Open`]。
/// - 締切の後で `result_at` が今より後 (未到来、または当日) → [`TicketSaleStage::AwaitingResult`]。
/// - それ以外 → [`TicketSaleStage::Ended`]。
/// - `ends_at` も `result_at` も無ければ、開始済みの受付は締切無しの [`TicketSaleStage::Open`]
///   として扱う (情報が無いことを終了扱いにしない)。
pub fn sale_stage(
    now_epoch_seconds: i64,
    starts_at: Option<&str>,
    ends_at: Option<&str>,
    result_at: Option<&str>,
) -> TicketSaleStage {
    let now = now_naive(now_epoch_seconds);
    let start = starts_at.and_then(parse_sale_moment);
    let end = ends_at.and_then(parse_sale_moment);
    let result = result_at.and_then(parse_sale_moment);

    if let Some(s) = start {
        if now < lower_bound(s) {
            return TicketSaleStage::Upcoming;
        }
    }
    match end {
        Some(e) => {
            if now <= upper_bound(e) {
                return TicketSaleStage::Open;
            }
        }
        None if result.is_none() => return TicketSaleStage::Open,
        None => {}
    }
    match result {
        Some(r) if now < upper_bound(r) => TicketSaleStage::AwaitingResult,
        _ => TicketSaleStage::Ended,
    }
}

/// 自由記述の日時を正規化する (`"2026/4/12 23:59"` → `"2026-04-12 23:59"`)。
/// 実在しない日付・壊れた時刻は `None`。編集フォームの入力補助用。
pub fn normalize_moment(input: &str) -> Option<String> {
    let input = input.trim();
    if input.is_empty() {
        return None;
    }
    let (date_part, time_part) = match input.split_once(' ') {
        Some((d, t)) => (d, Some(t)),
        None => (input, None),
    };
    let date = normalize_date_part(date_part)?;
    match time_part {
        Some(t) => Some(format!("{date} {}", normalize_time_part(t)?)),
        None => Some(date),
    }
}

fn normalize_date_part(s: &str) -> Option<String> {
    let sep = if s.contains('/') {
        '/'
    } else if s.contains('-') {
        '-'
    } else {
        return None;
    };
    let mut it = s.split(sep);
    let y: i32 = it.next()?.parse().ok()?;
    let m: u32 = it.next()?.parse().ok()?;
    let d: u32 = it.next()?.parse().ok()?;
    if it.next().is_some() {
        return None;
    }
    NaiveDate::from_ymd_opt(y, m, d)?;
    Some(format!("{y:04}-{m:02}-{d:02}"))
}

fn normalize_time_part(s: &str) -> Option<String> {
    let mut it = s.split(':');
    let h: u32 = it.next()?.parse().ok()?;
    let mi: u32 = it.next()?.parse().ok()?;
    if it.next().is_some() {
        return None;
    }
    if h > 23 || mi > 59 {
        return None;
    }
    Some(format!("{h:02}:{mi:02}"))
}

// ---------------------------------------------------------------------------
// 表示文字列
// ---------------------------------------------------------------------------

fn moment_label_from_raw(raw: &str) -> String {
    match parse_sale_moment(raw) {
        Some((date, time)) => moment_label(date, time),
        // 検査を経ていない (CloudKit 取り込みは寛容にする方針) 壊れた値は原文のまま出す。
        None => raw.to_string(),
    }
}

fn moment_label(date: NaiveDate, time: Option<(u32, u32)>) -> String {
    let day = crate::domain::date_display::short_with_weekday(&date.format("%Y-%m-%d").to_string());
    match time {
        Some((h, m)) => format!("{day} {h:02}:{m:02}"),
        None => day,
    }
}

fn period_label(starts_at: Option<&str>, ends_at: Option<&str>) -> Option<String> {
    match (starts_at, ends_at) {
        (Some(s), Some(e)) => Some(format!("{} 〜 {}", moment_label_from_raw(s), moment_label_from_raw(e))),
        (Some(s), None) => Some(format!("{} 〜", moment_label_from_raw(s))),
        (None, Some(e)) => Some(format!("〜 {}", moment_label_from_raw(e))),
        (None, None) => None,
    }
}

// ---------------------------------------------------------------------------
// 並び・注目受付
// ---------------------------------------------------------------------------

/// `sort_order` → `starts_at` (無いものは最後) → `id` の順に並べ替える。
pub fn sort_sales(mut sales: Vec<TicketSale>) -> Vec<TicketSale> {
    sales.sort_by(|a, b| sort_key(a).cmp(&sort_key(b)));
    sales
}

fn sort_key(sale: &TicketSale) -> (i64, bool, &str, &str) {
    (sale.sort_order, sale.starts_at.is_none(), sale.starts_at.as_deref().unwrap_or(""), sale.id.as_str())
}

/// イベント配下の受付一覧 (並び済み)。
pub fn sales_for_event(snap: &Snapshot, event_id: &str, now_epoch_seconds: i64) -> Vec<TicketSale> {
    let Some(&ei) = snap.event_index_by_id.get(event_id) else { return Vec::new() };
    let event = &snap.events[ei as usize];
    // `ticket_sales_by_event` は snapshot_build が既に sort_sales と同じ規約で並べているので、
    // ここで並べ直す必要は無い (二重にソートしない)。
    snap.ticket_sales_by_event[ei as usize]
        .iter()
        .map(|&si| to_ticket_sale(snap, event, &snap.ticket_sales[si as usize], now_epoch_seconds))
        .collect()
}

/// 「一番近い・一番大事な受付」1 件。
///
/// 優先順:
/// 1. 受付中のうち、締切が最も近いもの。
/// 2. 無ければ結果待ちのうち、当落 (発表) が最も近いもの。
/// 3. 無ければ受付前のうち、開始が最も近いもの。
/// 4. どれも無ければ `None`。
pub fn spotlight(snap: &Snapshot, event_id: &str, now_epoch_seconds: i64) -> Option<TicketSale> {
    pick_spotlight(&sales_for_event(snap, event_id, now_epoch_seconds))
}

fn opt_key(o: &Option<String>) -> (bool, &str) {
    (o.is_none(), o.as_deref().unwrap_or(""))
}

fn pick_spotlight(sales: &[TicketSale]) -> Option<TicketSale> {
    let mut open: Vec<&TicketSale> =
        sales.iter().filter(|s| s.stage == TicketSaleStage::Open).collect();
    open.sort_by_key(|s| opt_key(&s.ends_at));
    if let Some(&s) = open.first() {
        return Some(s.clone());
    }

    let mut awaiting: Vec<&TicketSale> =
        sales.iter().filter(|s| s.stage == TicketSaleStage::AwaitingResult).collect();
    awaiting.sort_by_key(|s| opt_key(&s.result_at));
    if let Some(&s) = awaiting.first() {
        return Some(s.clone());
    }

    let mut upcoming: Vec<&TicketSale> =
        sales.iter().filter(|s| s.stage == TicketSaleStage::Upcoming).collect();
    upcoming.sort_by_key(|s| opt_key(&s.starts_at));
    upcoming.first().map(|&s| s.clone())
}

/// 全イベント横断の「締切一覧」(ウィジェット・通知の材料)。
///
/// 対象は**まだ動きが要る受付**だけ: 受付中は締切、結果待ちは当落発表。
/// 受付前・終了は出さない (受付前は「まだやることが無い」、終了は「もう関係ない」)。
/// 近い順、上限 `limit` 件。
pub fn deadlines(snap: &Snapshot, now_epoch_seconds: i64, limit: u32) -> Vec<TicketSaleDeadline> {
    struct Row {
        day: String,
        time_minutes: u32,
        record: TicketSaleDeadline,
    }
    let mut rows: Vec<Row> = Vec::new();
    for (ei, event) in snap.events.iter().enumerate() {
        for &si in &snap.ticket_sales_by_event[ei] {
            let row = &snap.ticket_sales[si as usize];
            let stage = sale_stage(
                now_epoch_seconds,
                row.starts_at.as_deref(),
                row.ends_at.as_deref(),
                row.result_at.as_deref(),
            );
            let raw = match stage {
                TicketSaleStage::Open => row.ends_at.as_deref(),
                TicketSaleStage::AwaitingResult => row.result_at.as_deref(),
                TicketSaleStage::Upcoming | TicketSaleStage::Ended => None,
            };
            let Some((date, time)) = raw.and_then(parse_sale_moment) else { continue };
            let brand_color = event.brand_id.as_deref().and_then(|b| snap.brand(b)).and_then(|b| b.color.clone());
            let day = date.format("%Y-%m-%d").to_string();
            rows.push(Row {
                day: day.clone(),
                time_minutes: time.map_or(0, |(h, m)| h * 60 + m),
                record: TicketSaleDeadline {
                    sale_id: row.id.clone(),
                    sale_name: row.name.clone(),
                    event_id: event.id.clone(),
                    event_name: event.name.clone(),
                    brand_color,
                    deadline_day: day,
                    deadline_time: time.map(|(h, m)| format!("{h:02}:{m:02}")),
                },
            });
        }
    }
    rows.sort_by(|a, b| {
        (a.day.as_str(), a.time_minutes, a.record.sale_id.as_str())
            .cmp(&(b.day.as_str(), b.time_minutes, b.record.sale_id.as_str()))
    });
    rows.into_iter().take(limit as usize).map(|r| r.record).collect()
}

fn to_ticket_sale(
    snap: &Snapshot,
    event: &Event,
    row: &crate::domain::snapshot::TicketSaleRow,
    now_epoch_seconds: i64,
) -> TicketSale {
    let stage = sale_stage(
        now_epoch_seconds,
        row.starts_at.as_deref(),
        row.ends_at.as_deref(),
        row.result_at.as_deref(),
    );
    let show_labels: Vec<String> = row
        .show_ids
        .iter()
        .filter_map(|id| snap.show(id))
        .map(|show| distinguishing_show_name(&event.name, &show.name).unwrap_or(&show.name).to_string())
        .collect();
    TicketSale {
        id: row.id.clone(),
        event_id: event.id.clone(),
        event_name: event.name.clone(),
        show_ids: row.show_ids.clone(),
        show_labels,
        kind: row.kind,
        kind_label: kind_label(row.kind),
        name: row.name.clone(),
        starts_at: row.starts_at.clone(),
        ends_at: row.ends_at.clone(),
        result_at: row.result_at.clone(),
        url: row.url.clone(),
        note: row.note.clone(),
        source_url: row.source_url.clone(),
        sort_order: row.sort_order,
        stage,
        stage_label: stage_label(stage),
        period_label: period_label(row.starts_at.as_deref(), row.ends_at.as_deref()),
        result_label: row.result_at.as_deref().map(moment_label_from_raw),
    }
}

// ---------------------------------------------------------------------------
// 入力検査
// ---------------------------------------------------------------------------

fn is_http(s: &str) -> bool {
    s.starts_with("http://") || s.starts_with("https://")
}

fn trimmed_or_none(raw: Option<&str>) -> Option<&str> {
    raw.map(str::trim).filter(|s| !s.is_empty())
}

fn parse_moment_field(
    raw: Option<&str>,
    field: TicketSaleField,
    issues: &mut Vec<TicketSaleIssue>,
) -> Option<Moment> {
    let raw = trimmed_or_none(raw)?;
    match parse_sale_moment(raw) {
        Some(m) => Some(m),
        None => {
            issues.push(TicketSaleIssue::BadMoment { field });
            None
        }
    }
}

/// 編集フォームの入力検査。通れば空の `Vec`。
///
/// `event_show_ids` はその受付が属するイベントの公演 id 一覧 (検査の材料。
/// [`crate::domain::event_detail_queries::shows_by_event`] 等で引いたものを渡す)。
pub fn validate_draft(draft: &TicketSaleDraft, event_show_ids: &[String]) -> Vec<TicketSaleIssue> {
    let mut issues = Vec::new();

    if draft.name.trim().is_empty() {
        issues.push(TicketSaleIssue::Missing { field: TicketSaleField::Name });
    }

    let source_url = draft.source_url.trim();
    if source_url.is_empty() {
        issues.push(TicketSaleIssue::Missing { field: TicketSaleField::SourceUrl });
    } else if !is_http(source_url) {
        issues.push(TicketSaleIssue::NotHttp { field: TicketSaleField::SourceUrl });
    }

    if let Some(url) = trimmed_or_none(draft.url.as_deref()) {
        if !is_http(url) {
            issues.push(TicketSaleIssue::NotHttp { field: TicketSaleField::Url });
        }
    }

    let start = parse_moment_field(draft.starts_at.as_deref(), TicketSaleField::StartsAt, &mut issues);
    let end = parse_moment_field(draft.ends_at.as_deref(), TicketSaleField::EndsAt, &mut issues);
    let result = parse_moment_field(draft.result_at.as_deref(), TicketSaleField::ResultAt, &mut issues);

    if trimmed_or_none(draft.starts_at.as_deref()).is_none()
        && trimmed_or_none(draft.ends_at.as_deref()).is_none()
        && trimmed_or_none(draft.result_at.as_deref()).is_none()
    {
        issues.push(TicketSaleIssue::NoDates);
    }

    if let (Some(s), Some(e)) = (start, end) {
        if lower_bound(e) < lower_bound(s) {
            issues.push(TicketSaleIssue::EndsBeforeStarts);
        }
    }
    if let (Some(e), Some(r)) = (end, result) {
        if lower_bound(r) < lower_bound(e) {
            issues.push(TicketSaleIssue::ResultBeforeEnds);
        }
    }

    let known: HashSet<&str> = event_show_ids.iter().map(String::as_str).collect();
    for show_id in &draft.show_ids {
        if !known.contains(show_id.as_str()) {
            issues.push(TicketSaleIssue::UnknownShow { show_id: show_id.clone() });
        }
    }

    issues
}

fn field_label(field: TicketSaleField) -> &'static str {
    match field {
        TicketSaleField::Name => "名前",
        TicketSaleField::StartsAt => "受付開始",
        TicketSaleField::EndsAt => "申込締切",
        TicketSaleField::ResultAt => "当落発表",
        TicketSaleField::Url => "申込リンク",
        TicketSaleField::SourceUrl => "出典URL",
        TicketSaleField::ShowIds => "対象公演",
    }
}

/// 検査結果 1 件の文言。Swift/Kotlin に文言を二重管理させないための入口。
pub fn issue_message(issue: TicketSaleIssue) -> String {
    match issue {
        TicketSaleIssue::Missing { field } => format!("{}を入力してください", field_label(field)),
        TicketSaleIssue::BadMoment { field } => {
            format!("{}の形式が正しくありません (YYYY-MM-DD または YYYY-MM-DD HH:MM)", field_label(field))
        }
        TicketSaleIssue::NotHttp { field } => {
            format!("{}は http:// または https:// で始まる URL にしてください", field_label(field))
        }
        TicketSaleIssue::EndsBeforeStarts => "申込締切が受付開始より前になっています".to_string(),
        TicketSaleIssue::ResultBeforeEnds => "当落発表が申込締切より前になっています".to_string(),
        TicketSaleIssue::UnknownShow { show_id } => format!("{show_id} はこのライブの公演ではありません"),
        TicketSaleIssue::NoDates => "受付開始・申込締切・当落発表のいずれかを入力してください".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Brand, Event, Show, TicketSaleRow};
    use crate::domain::snapshot_build::{build, RawTables};

    /// JST の `y-m-d h:mi` を epoch 秒に (テスト専用。jst_day.rs のテストと同じ組み方)。
    fn epoch(y: i32, m: u32, d: u32, h: u32, mi: u32) -> i64 {
        NaiveDate::from_ymd_opt(y, m, d)
            .unwrap()
            .and_hms_opt(h, mi, 0)
            .unwrap()
            .and_utc()
            .timestamp()
            - 9 * 3600
    }

    // ---- 日時の解釈 ----

    #[test]
    fn parses_date_only_and_date_with_time() {
        assert_eq!(parse_sale_moment("2026-04-12"), Some((NaiveDate::from_ymd_opt(2026, 4, 12).unwrap(), None)));
        assert_eq!(
            parse_sale_moment("2026-04-12 23:59"),
            Some((NaiveDate::from_ymd_opt(2026, 4, 12).unwrap(), Some((23, 59))))
        );
        assert_eq!(parse_sale_moment(""), None);
        assert_eq!(parse_sale_moment("2026/04/12"), None, "正規化前のスラッシュ表記は受けない");
        assert_eq!(parse_sale_moment("2026-04-12 24:00"), None, "時刻は 0-23:0-59");
        assert_eq!(parse_sale_moment("2026-04-31"), None, "実在しない日付");
    }

    #[test]
    fn normalizes_free_text_moments() {
        assert_eq!(normalize_moment("2026/4/12 23:59"), Some("2026-04-12 23:59".to_string()));
        assert_eq!(normalize_moment("2026-4-1"), Some("2026-04-01".to_string()));
        assert_eq!(normalize_moment("  2026-04-12  "), Some("2026-04-12".to_string()));
        assert_eq!(normalize_moment(""), None);
        assert_eq!(normalize_moment("2026/13/01"), None, "実在しない月");
        assert_eq!(normalize_moment("2026/4/12 25:00"), None, "実在しない時刻");
        assert_eq!(normalize_moment("未定"), None);
    }

    // ---- 段階の境界 ----

    #[test]
    fn date_only_deadline_stays_open_through_the_end_of_that_day() {
        // 締切 (ends_at) が日付だけなら、その日の 23:59 まで Open。
        let stage = |now| sale_stage(now, Some("2026-04-01"), Some("2026-04-12"), None);
        assert_eq!(stage(epoch(2026, 4, 12, 0, 0)), TicketSaleStage::Open, "締切当日の朝はまだ受付中");
        assert_eq!(stage(epoch(2026, 4, 12, 23, 59)), TicketSaleStage::Open, "締切当日の 23:59 もまだ");
        assert_eq!(stage(epoch(2026, 4, 13, 0, 0)), TicketSaleStage::Ended, "翌日になれば終了 (当落予定無し)");
    }

    #[test]
    fn lottery_result_day_is_awaiting_result_and_ends_the_next_day() {
        // 締切を過ぎていて、当落発表 (result_at) が日付だけなら、その日いっぱいは結果待ち。
        let stage = |now| sale_stage(now, Some("2026-04-01"), Some("2026-04-05"), Some("2026-04-15"));
        assert_eq!(stage(epoch(2026, 4, 10, 12, 0)), TicketSaleStage::AwaitingResult, "締切後・当落前");
        assert_eq!(stage(epoch(2026, 4, 15, 0, 0)), TicketSaleStage::AwaitingResult, "当落発表の当日はまだ結果待ち");
        assert_eq!(stage(epoch(2026, 4, 15, 23, 59)), TicketSaleStage::AwaitingResult, "当落当日の 23:59 も");
        assert_eq!(stage(epoch(2026, 4, 16, 0, 0)), TicketSaleStage::Ended, "翌日になれば終了");
    }

    #[test]
    fn lottery_without_a_result_date_ends_right_after_the_deadline() {
        // result_at が無い抽選は、締切を過ぎた時点で Ended (いつまでも結果待ちにしない)。
        let stage = |now| sale_stage(now, Some("2026-04-01"), Some("2026-04-05"), None);
        assert_eq!(stage(epoch(2026, 4, 5, 23, 59)), TicketSaleStage::Open);
        assert_eq!(stage(epoch(2026, 4, 6, 0, 0)), TicketSaleStage::Ended);
    }

    #[test]
    fn time_of_day_boundaries_are_exact_to_the_minute() {
        // 時刻付きの締切は分刻みの厳密な境界。
        let stage = |now| sale_stage(now, None, Some("2026-04-12 23:59"), None);
        assert_eq!(stage(epoch(2026, 4, 12, 23, 59)), TicketSaleStage::Open, "締切の分ちょうどはまだ受付中");
        assert_eq!(stage(epoch(2026, 4, 13, 0, 0)), TicketSaleStage::Ended, "1 分でも過ぎれば終了");

        // 開始も時刻付きなら分刻みで判定。
        let starts = |now| sale_stage(now, Some("2026-04-01 12:00"), Some("2026-04-12"), None);
        assert_eq!(starts(epoch(2026, 4, 1, 11, 59)), TicketSaleStage::Upcoming);
        assert_eq!(starts(epoch(2026, 4, 1, 12, 0)), TicketSaleStage::Open, "開始の分ちょうどから受付中");
    }

    #[test]
    fn before_the_start_is_upcoming_regardless_of_other_dates() {
        let stage = sale_stage(epoch(2026, 3, 1, 0, 0), Some("2026-04-01"), Some("2026-04-12"), Some("2026-04-15"));
        assert_eq!(stage, TicketSaleStage::Upcoming);
    }

    #[test]
    fn no_dates_at_all_defaults_to_open_rather_than_hiding_as_ended() {
        assert_eq!(sale_stage(epoch(2026, 1, 1, 0, 0), None, None, None), TicketSaleStage::Open);
    }

    // ---- 並び ----

    fn sale(id: &str, sort_order: i64, starts_at: Option<&str>) -> TicketSale {
        TicketSale {
            id: id.into(),
            event_id: "e1".into(),
            event_name: "イベント".into(),
            show_ids: vec![],
            show_labels: vec![],
            kind: TicketSaleKind::Lottery,
            kind_label: "抽選".into(),
            name: id.into(),
            starts_at: starts_at.map(str::to_string),
            ends_at: None,
            result_at: None,
            url: None,
            note: None,
            source_url: "https://example.com".into(),
            sort_order,
            stage: TicketSaleStage::Open,
            stage_label: "受付中".into(),
            period_label: None,
            result_label: None,
        }
    }

    #[test]
    fn sort_order_wins_then_starts_at_with_none_last_then_id() {
        let sales = vec![
            sale("z", 0, Some("2026-04-02")),
            sale("a", 0, None),
            sale("b", 0, Some("2026-04-01")),
            sale("first", -1, Some("2026-05-01")),
        ];
        let sorted = sort_sales(sales);
        let ids: Vec<&str> = sorted.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(ids, ["first", "b", "z", "a"], "sort_order 最優先、次に starts_at (無いものは最後)");
    }

    // ---- 注目受付 ----

    fn with_stage(mut s: TicketSale, stage: TicketSaleStage, ends_at: Option<&str>, result_at: Option<&str>) -> TicketSale {
        s.stage = stage;
        s.ends_at = ends_at.map(str::to_string);
        s.result_at = result_at.map(str::to_string);
        s
    }

    #[test]
    fn spotlight_prefers_open_then_awaiting_result_then_upcoming() {
        let open_far = with_stage(sale("open_far", 0, None), TicketSaleStage::Open, Some("2026-05-01"), None);
        let open_near = with_stage(sale("open_near", 0, None), TicketSaleStage::Open, Some("2026-04-01"), None);
        let awaiting = with_stage(sale("awaiting", 0, None), TicketSaleStage::AwaitingResult, None, Some("2026-04-10"));
        let upcoming = with_stage(sale("upcoming", 0, Some("2026-06-01")), TicketSaleStage::Upcoming, None, None);

        // Open が 1 件でもあれば、締切が最も近い Open を選ぶ。
        assert_eq!(
            pick_spotlight(&[open_far.clone(), open_near.clone(), awaiting.clone(), upcoming.clone()]).map(|s| s.id),
            Some("open_near".to_string())
        );
        // Open が無ければ AwaitingResult。
        assert_eq!(
            pick_spotlight(&[awaiting.clone(), upcoming.clone()]).map(|s| s.id),
            Some("awaiting".to_string())
        );
        // どちらも無ければ Upcoming。
        assert_eq!(pick_spotlight(&[upcoming.clone()]).map(|s| s.id), Some("upcoming".to_string()));
        // 何も無ければ None (Ended だけの場合を含む)。
        let ended = with_stage(sale("ended", 0, None), TicketSaleStage::Ended, None, None);
        assert_eq!(pick_spotlight(&[ended]), None);
        assert_eq!(pick_spotlight(&[]), None);
    }

    // ---- Snapshot を使う関数 (sales_for_event / spotlight / deadlines) ----

    fn event(id: &str, name: &str, brand_id: Option<&str>) -> Event {
        Event {
            id: id.into(),
            brand_id: brand_id.map(str::to_string),
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
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn row(
        id: &str,
        event: u32,
        show_ids: Vec<String>,
        kind: TicketSaleKind,
        name: &str,
        starts_at: Option<&str>,
        ends_at: Option<&str>,
        result_at: Option<&str>,
        sort_order: i64,
    ) -> TicketSaleRow {
        TicketSaleRow {
            id: id.into(),
            event,
            show_ids,
            kind,
            name: name.into(),
            starts_at: starts_at.map(str::to_string),
            ends_at: ends_at.map(str::to_string),
            result_at: result_at.map(str::to_string),
            url: None,
            note: None,
            source_url: "https://example.com/info".into(),
            sort_order,
        }
    }

    fn test_snapshot(events: Vec<Event>, shows: Vec<Show>, ticket_sales: Vec<TicketSaleRow>) -> Snapshot {
        build(RawTables {
            songs: vec![],
            idols: vec![],
            events,
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
            ticket_sales,
            song_artists: vec![],
            setlist_performers: vec![],
            show_cast: vec![],
            unit_members: vec![],
            idol_brands: vec![],
        })
    }

    #[test]
    fn sales_for_event_projects_labels_and_ignores_other_events() {
        let events = vec![event("e1", "10th LIVE", Some("cg")), event("e2", "他のライブ", None)];
        let shows = vec![
            show("sh1", 0, "10th LIVE DAY1", "2026-04-20"),
            show("sh2", 0, "10th LIVE DAY2", "2026-04-21"),
        ];
        let sales = vec![
            row("t1", 0, vec!["sh1".into()], TicketSaleKind::Lottery, "先行抽選", Some("2026-03-01"), Some("2026-03-10"), Some("2026-03-15"), 0),
            row("t2", 1, vec![], TicketSaleKind::FirstCome, "他のライブの受付", None, Some("2026-03-05"), None, 0),
        ];
        let snap = test_snapshot(events, shows, sales);
        let now = epoch(2026, 3, 5, 0, 0);
        let result = sales_for_event(&snap, "e1", now);
        assert_eq!(result.len(), 1, "e2 の受付は混ざらない");
        assert_eq!(result[0].id, "t1");
        assert_eq!(result[0].show_labels, vec!["DAY1".to_string()], "対象公演の短い名");
        assert_eq!(result[0].kind_label, "抽選");
        assert_eq!(result[0].stage, TicketSaleStage::Open, "3/5 は開始(3/1)〜締切(3/10) の間");
        assert!(result[0].period_label.as_deref().unwrap().contains("〜"));
        assert_eq!(result[0].result_label.as_deref(), Some("3/15 (日)"));

        // 空イベント / 未知イベントは空。
        assert!(sales_for_event(&snap, "no-such-event", now).is_empty());
    }

    #[test]
    fn sales_for_event_reports_all_shows_label_as_empty_when_unscoped() {
        let events = vec![event("e1", "10th LIVE", Some("cg"))];
        let shows = vec![show("sh1", 0, "10th LIVE DAY1", "2026-04-20")];
        let sales = vec![row("t1", 0, vec![], TicketSaleKind::SameDay, "当日券", None, None, None, 0)];
        let snap = test_snapshot(events, shows, sales);
        let result = sales_for_event(&snap, "e1", epoch(2026, 4, 20, 0, 0));
        assert_eq!(result[0].show_labels, Vec::<String>::new(), "show_ids が空 = 全公演で短い名も空");
    }

    #[test]
    fn spotlight_picks_the_nearest_open_deadline_via_the_snapshot() {
        let events = vec![event("e1", "10th LIVE", Some("cg"))];
        let sales = vec![
            row("far", 0, vec![], TicketSaleKind::FirstCome, "一般先着", Some("2026-03-01"), Some("2026-05-01"), None, 0),
            row("near", 0, vec![], TicketSaleKind::Lottery, "先行抽選", Some("2026-03-01"), Some("2026-04-01"), None, 0),
        ];
        let snap = test_snapshot(events, vec![], sales);
        let spot = spotlight(&snap, "e1", epoch(2026, 3, 15, 0, 0)).expect("Open が 2 件ある");
        assert_eq!(spot.id, "near");
        assert!(spotlight(&snap, "no-such-event", epoch(2026, 3, 15, 0, 0)).is_none());
    }

    #[test]
    fn deadlines_lists_open_and_awaiting_across_events_nearest_first() {
        let events = vec![event("e1", "10th LIVE", Some("cg")), event("e2", "11th LIVE", None)];
        let sales = vec![
            row("t1", 0, vec![], TicketSaleKind::Lottery, "抽選A", Some("2026-03-01"), Some("2026-04-10"), Some("2026-04-20"), 0),
            row("t2", 1, vec![], TicketSaleKind::FirstCome, "先着B", Some("2026-03-01"), Some("2026-04-05 18:00"), None, 0),
            // 受付前 (Upcoming) は締切一覧には出さない。
            row("t3", 1, vec![], TicketSaleKind::Lottery, "抽選C", Some("2026-06-01"), Some("2026-06-10"), None, 0),
        ];
        let snap = test_snapshot(events, vec![], sales);
        let now = epoch(2026, 4, 1, 0, 0);
        let result = deadlines(&snap, now, 10);
        let ids: Vec<&str> = result.iter().map(|d| d.sale_id.as_str()).collect();
        // t1 は結果待ちではなくまだ Open (締切 4/10 > now)。近い順: t2 (4/5) → t1 (4/10)。
        assert_eq!(ids, ["t2", "t1"]);
        assert_eq!(result[0].deadline_time.as_deref(), Some("18:00"));
        assert_eq!(result[1].deadline_time, None);
        assert_eq!(result[0].brand_color, None, "e2 は brand_id 無し");
        assert_eq!(result[1].brand_color.as_deref(), Some("#ff69b4"));

        // 上限。
        assert_eq!(deadlines(&snap, now, 1).len(), 1);
    }

    // ---- 入力検査 ----

    fn draft() -> TicketSaleDraft {
        TicketSaleDraft {
            event_id: "e1".into(),
            show_ids: vec![],
            kind: TicketSaleKind::Lottery,
            name: "先行抽選".into(),
            starts_at: Some("2026-04-01".into()),
            ends_at: Some("2026-04-10".into()),
            result_at: Some("2026-04-15".into()),
            url: Some("https://example.com/apply".into()),
            note: None,
            source_url: "https://example.com/info".into(),
            sort_order: 0,
        }
    }

    #[test]
    fn a_well_formed_draft_has_no_issues() {
        assert_eq!(validate_draft(&draft(), &["sh1".to_string()]), vec![]);
    }

    #[test]
    fn missing_required_fields_are_reported() {
        let mut d = draft();
        d.name = "  ".into();
        d.source_url = "".into();
        let issues = validate_draft(&d, &[]);
        assert!(issues.contains(&TicketSaleIssue::Missing { field: TicketSaleField::Name }));
        assert!(issues.contains(&TicketSaleIssue::Missing { field: TicketSaleField::SourceUrl }));
    }

    #[test]
    fn urls_must_be_http() {
        let mut d = draft();
        d.source_url = "example.com/info".into();
        d.url = Some("ftp://example.com".into());
        let issues = validate_draft(&d, &[]);
        assert!(issues.contains(&TicketSaleIssue::NotHttp { field: TicketSaleField::SourceUrl }));
        assert!(issues.contains(&TicketSaleIssue::NotHttp { field: TicketSaleField::Url }));

        // url は任意項目: 空文字/空白は検査しない。
        d.url = Some("  ".into());
        d.source_url = "https://example.com".into();
        assert!(!validate_draft(&d, &[]).contains(&TicketSaleIssue::NotHttp { field: TicketSaleField::Url }));
    }

    #[test]
    fn malformed_moments_are_reported_per_field() {
        let mut d = draft();
        d.starts_at = Some("2026/04/01".into());
        d.ends_at = Some("来週".into());
        let issues = validate_draft(&d, &[]);
        assert!(issues.contains(&TicketSaleIssue::BadMoment { field: TicketSaleField::StartsAt }));
        assert!(issues.contains(&TicketSaleIssue::BadMoment { field: TicketSaleField::EndsAt }));
    }

    #[test]
    fn no_dates_at_all_is_its_own_issue() {
        let mut d = draft();
        d.starts_at = None;
        d.ends_at = None;
        d.result_at = None;
        assert!(validate_draft(&d, &[]).contains(&TicketSaleIssue::NoDates));
        // 1 つでもあれば NoDates は出ない。
        d.ends_at = Some("2026-04-10".into());
        assert!(!validate_draft(&d, &[]).contains(&TicketSaleIssue::NoDates));
    }

    #[test]
    fn ordering_between_the_three_dates_is_checked() {
        let mut d = draft();
        d.starts_at = Some("2026-04-10".into());
        d.ends_at = Some("2026-04-01".into());
        assert!(validate_draft(&d, &[]).contains(&TicketSaleIssue::EndsBeforeStarts));

        let mut d2 = draft();
        d2.ends_at = Some("2026-04-15".into());
        d2.result_at = Some("2026-04-10".into());
        assert!(validate_draft(&d2, &[]).contains(&TicketSaleIssue::ResultBeforeEnds));

        // 境界 (同時刻) は問題無し。
        let mut d3 = draft();
        d3.starts_at = Some("2026-04-01 12:00".into());
        d3.ends_at = Some("2026-04-01 12:00".into());
        assert!(!validate_draft(&d3, &[]).contains(&TicketSaleIssue::EndsBeforeStarts));
    }

    #[test]
    fn unknown_show_ids_are_reported_one_by_one() {
        let mut d = draft();
        d.show_ids = vec!["sh1".into(), "sh_ghost".into()];
        let issues = validate_draft(&d, &["sh1".to_string()]);
        assert_eq!(issues, vec![TicketSaleIssue::UnknownShow { show_id: "sh_ghost".to_string() }]);
    }

    #[test]
    fn issue_messages_are_non_empty_and_mention_the_field() {
        for issue in [
            TicketSaleIssue::Missing { field: TicketSaleField::Name },
            TicketSaleIssue::BadMoment { field: TicketSaleField::EndsAt },
            TicketSaleIssue::NotHttp { field: TicketSaleField::Url },
            TicketSaleIssue::EndsBeforeStarts,
            TicketSaleIssue::ResultBeforeEnds,
            TicketSaleIssue::UnknownShow { show_id: "sh1".to_string() },
            TicketSaleIssue::NoDates,
        ] {
            assert!(!issue_message(issue).is_empty());
        }
    }

    // ---- 生値の変換 ----

    #[test]
    fn kind_raw_round_trips() {
        for kind in [TicketSaleKind::Lottery, TicketSaleKind::FirstCome, TicketSaleKind::Resale, TicketSaleKind::SameDay] {
            let raw = ticket_sale_kind_raw(kind);
            assert_eq!(ticket_sale_kind_from_raw(&raw), Some(kind));
        }
        assert_eq!(ticket_sale_kind_from_raw("unknown"), None, "知らない値は捏造しない");
    }
}
