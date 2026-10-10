//! 公演のチケット価格 (席種・配信) の規則。純粋ロジック。
//!
//! 「どんな価格のチケットがあるか」を引けるようにし、参加を付けたときに
//! **その形態に合う券種**を候補として出す。金額の帳簿 (domain/ledger.rs) は
//! 端末ローカルだが、**価格表はマスタ** (みんなで共有する事実) なので別の表に持つ。
//!
//! # ここに置くもの
//!
//! 参加形態から券種を選ぶ規則・既定の 1 枚の決め方・価格帯の要約・並び。
//! どれも「判断」なので各 OS に書かない。iOS と Android で既定の券種が違うと、
//! 同じ公演で自動的に記録される額が端末ごとに変わる。
//!
//! # 券種の名前は自由文字列
//!
//! S席 / A席 / 立見 / アリーナ / スタンド / 見切れ / 配信 / アーカイブ付き…と
//! 公演ごとに呼び方が違い、固定の enum にすると必ず溢れる。**形態 (現地/配信/LV) だけ
//! を機械で扱い、席種は名前と並び順で持つ**。

use chrono::{Datelike, NaiveDateTime, Timelike};

use crate::domain::ledger::format_yen;
use crate::domain::ticket_sales::{lower_bound, now_naive, parse_sale_moment, upper_bound};

/// 券の形態。参加形態 (`user_marks.attended` の text_value) と同じ 3 つ。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TicketKind {
    /// 現地。
    Live,
    /// 配信。
    Stream,
    /// ライブビューイング。
    LiveViewing,
}

/// 券種 1 つ。`show_tickets` の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowTicket {
    pub id: String,
    pub show_id: String,
    pub kind: TicketKind,
    /// 券種名 (`S席` / `立見` / `配信 (アーカイブ付き)` 等)。
    pub name: String,
    /// 円。**税込・手数料抜き**の定価を入れる。
    pub price: i64,
    /// 公式に出ていない推定値か。推定を実額と同じ顔で出さないための札。
    pub is_estimate: bool,
    pub note: Option<String>,
    /// 並び順 (公式の表記順)。同値なら価格の高い順。
    pub sort_order: i64,
    /// 配信のアーカイブ (見逃し) が見られる期間の始まり。JST の `YYYY-MM-DD HH:MM`
    /// (受付の `ticket_sales.starts_at` と同じ書式。日付だけなら 00:00 から)。
    pub archive_starts_at: Option<String>,
    /// アーカイブ期間の終わり。日付だけならその日の 23:59 まで。
    pub archive_ends_at: Option<String>,
}

/// 価格帯の要約 (「この公演は 5,500〜13,200 円」)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketPriceRange {
    pub kind: TicketKind,
    pub min: i64,
    pub max: i64,
    pub count: u32,
    /// `¥5,500〜¥13,200`。1 種だけなら `¥5,500`。
    pub label: String,
    /// 1 件でも推定が混じるか (帯に「推定」を添えるため)。
    pub has_estimate: bool,
}

/// 参加形態から、その形態の券種だけを並び順で取り出す。
///
/// 並びは `sort_order` → 価格の高い順 → 名前。公式の表記順を保ちつつ、
/// 並び順が未設定 (全部 0) の行でも端末間でぶれないようにする。
pub fn tickets_for_kind(tickets: &[ShowTicket], kind: TicketKind) -> Vec<ShowTicket> {
    let mut list: Vec<ShowTicket> = tickets.iter().filter(|t| t.kind == kind).cloned().collect();
    list.sort_by(|a, b| {
        a.sort_order
            .cmp(&b.sort_order)
            .then_with(|| b.price.cmp(&a.price))
            .then_with(|| a.name.cmp(&b.name))
    });
    list
}

/// 参加を付けた直後に「チケット代を記録しますか」と聞くときの中身。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketExpensePrompt {
    /// 参加形態から決めた券の形態。
    pub kind: TicketKind,
    /// 選ばせる券種 ([`tickets_for_kind`] の並び)。1 つなら金額そのまま、複数なら選ばせる。
    pub tickets: Vec<ShowTicket>,
}

/// 公演の名前が分からないときにシートに出す呼び方。
pub const TICKET_PROMPT_FALLBACK_SHOW_LABEL: &str = "この公演";

/// 公演に記録済みの支出 1 件 (二重計上を避ける判定の材料)。各 OS が `expenses` から射影する。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct RecordedShowExpense {
    /// 費目キー (`expenses.category`)。
    pub category: String,
    /// チケット代を記録したときの券の形態 (`expenses.ticket_kind`。[`ticket_kind_raw`] の値)。
    /// 形態を持てるようにする前の行と、手で入れた行は `None`。
    pub ticket_kind: Option<String>,
    pub note: Option<String>,
}

/// その形態のチケット代を記録済みか。
///
/// 1 公演に複数の形態で参加できる (現地 + 配信のアーカイブ) ので、**形態ごとに**見る。
/// 現地のチケット代があっても、配信のチケット代はまだ、がありうる。
///
/// 形態を持たない古いチケット代の行は、メモが券種名 ([`ticket_expense_note`] の書式) と
/// 一致すればその券の形態とみなす。一致しなければ**どの形態も記録済み**とみなす —
/// 分からないまま聞くと二重計上になりうる (複数形態を持つ前の振る舞いと同じ)。
pub fn ticket_kind_recorded(
    kind: TicketKind,
    show_tickets: &[ShowTicket],
    existing_expenses: &[RecordedShowExpense],
) -> bool {
    let ticket_key = crate::domain::ledger::expense_category_key(
        crate::domain::ledger::ExpenseCategory::Ticket,
    );
    existing_expenses
        .iter()
        .filter(|e| e.category == ticket_key)
        .any(|e| match e.ticket_kind.as_deref().and_then(ticket_kind_from_raw) {
            Some(recorded) => recorded == kind,
            None => {
                let matched: Vec<TicketKind> = show_tickets
                    .iter()
                    .filter(|t| e.note.as_deref() == Some(ticket_expense_note(t).as_str())
                        || e.note.as_deref() == Some(t.name.as_str()))
                    .map(|t| t.kind)
                    .collect();
                matched.is_empty() || matched.contains(&kind)
            }
        })
}

/// 参加を付けた直後に、チケット代を記録するか聞くか。聞くなら候補の券種。
///
/// `attendance_type` は**いま付けた 1 つの形態** (現地に配信を足したなら `stream`)。
///
/// **聞かない理由が 1 つでもあれば `None`** (参加を付けるたびにシートが出ると、付ける作業が止まる):
/// - その形態の券種がマスタに無い
/// - その形態のチケット代を既に記録してある ([`ticket_kind_recorded`]。二重計上を防ぐ)
///
/// 記録済みかを**読めなかった**ときは OS が呼ばずに終わること (分からないまま聞くと
/// 二重計上になりうる。iOS の今の振る舞い)。
pub fn ticket_expense_prompt(
    show_tickets: &[ShowTicket],
    attendance_type: &str,
    existing_expenses: &[RecordedShowExpense],
) -> Option<TicketExpensePrompt> {
    let kind = ticket_kind_from_attendance(attendance_type);
    let tickets = tickets_for_kind(show_tickets, kind);
    let already_recorded = ticket_kind_recorded(kind, show_tickets, existing_expenses);
    (!tickets.is_empty() && !already_recorded).then_some(TicketExpensePrompt { kind, tickets })
}

/// 記録する行のメモ (`S席` / 推定値なら `S席 (推定)`)。
pub fn ticket_expense_note(ticket: &ShowTicket) -> String {
    if ticket.is_estimate {
        format!("{} (推定)", ticket.name)
    } else {
        ticket.name.clone()
    }
}

/// 過去の参加からチケット代を取り込むときの、公演 1 つぶんの材料。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketBackfillInput {
    pub show_id: String,
    /// 参加マークの保存値 (`user_marks.attended` の text_value そのまま。複数形態は
    /// `live,stream`。空なら現地。読み方は [`crate::domain::attendance::attendance_types`])。
    pub attendance_type: String,
    /// その公演の券種 (全形態)。
    pub tickets: Vec<ShowTicket>,
    /// その公演に記録済みの支出。
    pub existing_expenses: Vec<RecordedShowExpense>,
}

/// 取り込み候補 1 つ (公演 × 形態。現地と配信の両方で参加した公演は 2 つ出る)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketBackfillItem {
    pub show_id: String,
    pub kind: TicketKind,
    /// 選ばせる券種 ([`tickets_for_kind`] の並び)。
    pub tickets: Vec<ShowTicket>,
    /// 最初から選んでおく 1 枚。**券種が 1 つのときだけ**入る ([`default_ticket`])。
    /// 複数あるのに先頭を入れると、S席と立見の差額が黙って帳簿に乗る。
    pub preselected: Option<ShowTicket>,
}

/// 参加を付けてあるのにチケット代がまだ無い公演を、取り込み候補として並べる。
///
/// 候補にするかは参加を付けた直後の確認 ([`ticket_expense_prompt`]) と同じ規則
/// (その形態の券種があり、その形態のチケット代をまだ記録していない) を、付いている
/// 形態ごとに当てる。並びは渡された順のまま、1 公演の中は形態の語彙順。
pub fn ticket_expense_backfill(inputs: &[TicketBackfillInput]) -> Vec<TicketBackfillItem> {
    inputs
        .iter()
        .flat_map(|input| {
            crate::domain::attendance::attendance_types(Some(&input.attendance_type))
                .into_iter()
                .filter_map(|attendance| {
                    let prompt =
                        ticket_expense_prompt(&input.tickets, &attendance, &input.existing_expenses)?;
                    let preselected = default_ticket(&prompt.tickets, prompt.kind);
                    Some(TicketBackfillItem {
                        show_id: input.show_id.clone(),
                        kind: prompt.kind,
                        tickets: prompt.tickets,
                        preselected,
                    })
                })
                .collect::<Vec<_>>()
        })
        .collect()
}

/// 参加を付けたときに既定で提案する 1 枚。
///
/// **候補が 1 つのときだけ決める**。複数あるなら選ばせる — S席と立見で
/// 4,000 円違う公演があり、勝手にどちらかを入れると帳簿が静かに狂う。
pub fn default_ticket(tickets: &[ShowTicket], kind: TicketKind) -> Option<ShowTicket> {
    let list = tickets_for_kind(tickets, kind);
    match list.len() {
        1 => list.into_iter().next(),
        _ => None,
    }
}

/// その形態の価格帯。券種が無ければ `None`。
pub fn price_range(tickets: &[ShowTicket], kind: TicketKind) -> Option<TicketPriceRange> {
    let list = tickets_for_kind(tickets, kind);
    let min = list.iter().map(|t| t.price).min()?;
    let max = list.iter().map(|t| t.price).max()?;
    Some(TicketPriceRange {
        kind,
        min,
        max,
        count: list.len() as u32,
        label: if min == max {
            format_yen(min)
        } else {
            format!("{}〜{}", format_yen(min), format_yen(max))
        },
        has_estimate: list.iter().any(|t| t.is_estimate),
    })
}

/// 公演にある全形態の価格帯を、現地 → LV → 配信 の順で返す。
///
/// 現地が先なのは、参加者の多くが現地で、価格も一番高いため
/// (一覧で最初に目に入るべき数字)。
pub fn price_ranges(tickets: &[ShowTicket]) -> Vec<TicketPriceRange> {
    [TicketKind::Live, TicketKind::LiveViewing, TicketKind::Stream]
        .into_iter()
        .filter_map(|kind| price_range(tickets, kind))
        .collect()
}

/// アーカイブ期間の段階。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArchiveState {
    /// 公開前 (始まりより前)。
    Upcoming,
    /// いま見られる。
    Open,
    /// 終わった。
    Ended,
}

/// 配信チケット 1 枚のアーカイブ期間の表示。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TicketArchive {
    pub state: ArchiveState,
    /// `アーカイブ 9/28 18:00〜10/5 23:59`。始まりが無ければ `アーカイブ 〜10/5 23:59`、
    /// 終わりが無ければ `アーカイブ 9/28 18:00〜`。
    pub period_label: String,
    /// 段階の札 (`公開中` / `公開前` / `終了`)。
    pub state_label: String,
    /// 券種行の注記にそのまま置く 1 行 (`アーカイブ 9/28 18:00〜10/5 23:59・公開中`)。
    pub note: String,
}

/// 券種のアーカイブ期間。期間が 1 つも読めなければ `None` (書式の崩れた値を捏造して出さない)。
///
/// 判定は受付 ([`crate::domain::ticket_sales::sale_stage`]) と同じ約束: 日付だけの始まりは 00:00、
/// 日付だけの終わりはその日いっぱい、両端を含む。形態は問わない (現地+配信のセット券にも付く)。
pub fn ticket_archive(ticket: &ShowTicket, now_epoch_seconds: i64) -> Option<TicketArchive> {
    let start = ticket.archive_starts_at.as_deref().and_then(parse_sale_moment);
    let end = ticket.archive_ends_at.as_deref().and_then(parse_sale_moment);
    if start.is_none() && end.is_none() {
        return None;
    }
    let now = now_naive(now_epoch_seconds);
    let state = if start.is_some_and(|s| now < lower_bound(s)) {
        ArchiveState::Upcoming
    } else if end.is_some_and(|e| now > upper_bound(e)) {
        ArchiveState::Ended
    } else {
        ArchiveState::Open
    };
    let fmt = |at: NaiveDateTime, has_time: bool| {
        if has_time {
            format!("{}/{} {}:{:02}", at.month(), at.day(), at.hour(), at.minute())
        } else {
            format!("{}/{}", at.month(), at.day())
        }
    };
    let period_label = format!(
        "アーカイブ {}〜{}",
        start.map(|s| fmt(lower_bound(s), s.1.is_some())).unwrap_or_default(),
        end.map(|e| fmt(upper_bound(e), e.1.is_some())).unwrap_or_default(),
    );
    let state_label = match state {
        ArchiveState::Upcoming => "公開前",
        ArchiveState::Open => "公開中",
        ArchiveState::Ended => "終了",
    }
    .to_string();
    let note = format!("{period_label}・{state_label}");
    Some(TicketArchive { state, period_label, state_label, note })
}

/// 券種の入力検査。通れば `None`。
pub fn validate_ticket(name: &str, price: i64) -> Option<TicketInputError> {
    if name.trim().is_empty() {
        return Some(TicketInputError::EmptyName);
    }
    if price <= 0 {
        return Some(TicketInputError::NotPositive);
    }
    // 1 枚 100 万円を超える券は無い。桁の打ち間違いとして弾く。
    if price > 1_000_000 {
        return Some(TicketInputError::TooLarge);
    }
    None
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum TicketInputError {
    EmptyName,
    NotPositive,
    TooLarge,
}

/// 参加形態の保存値 (`user_marks.attended` の text_value) から券の形態へ。
///
/// 旧データ (種別なし) は現地扱い。これは回収率の判定と同じ約束で、
/// ここだけ別の扱いにすると「参加しているのに券種が出ない」が起きる。
pub fn ticket_kind_from_attendance(text_value: &str) -> TicketKind {
    match text_value {
        "stream" => TicketKind::Stream,
        "live_viewing" => TicketKind::LiveViewing,
        _ => TicketKind::Live,
    }
}

/// 券の形態の保存値 (`show_tickets.kind` / `expenses.ticket_kind`)。参加形態の語と同じ。
pub fn ticket_kind_raw(kind: TicketKind) -> String {
    let [live, stream, live_viewing] = &crate::domain::vocabulary::ATTENDANCE_TYPES;
    match kind {
        TicketKind::Live => live,
        TicketKind::Stream => stream,
        TicketKind::LiveViewing => live_viewing,
    }
    .value
    .to_string()
}

/// 保存値 → 券の形態。知らない値は `None` ([`ticket_kind_from_attendance`] と違い現地に倒さない)。
fn ticket_kind_from_raw(raw: &str) -> Option<TicketKind> {
    [TicketKind::Live, TicketKind::Stream, TicketKind::LiveViewing]
        .into_iter()
        .find(|k| ticket_kind_raw(*k) == raw)
}

/// 形態の表示名。語は参加形態と同じ ([`crate::domain::vocabulary::ATTENDANCE_TYPES`] の短い形)。
pub fn ticket_kind_label(kind: TicketKind) -> String {
    let [live, stream, live_viewing] = &crate::domain::vocabulary::ATTENDANCE_TYPES;
    match kind {
        TicketKind::Live => live,
        TicketKind::Stream => stream,
        TicketKind::LiveViewing => live_viewing,
    }
    .short_label
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ticket(id: &str, kind: TicketKind, name: &str, price: i64, sort: i64) -> ShowTicket {
        ShowTicket {
            id: id.into(),
            show_id: "show_1".into(),
            kind,
            name: name.into(),
            price,
            is_estimate: false,
            note: None,
            sort_order: sort,
            archive_starts_at: None,
            archive_ends_at: None,
        }
    }

    /// JST の `YYYY-MM-DD HH:MM` → epoch 秒。
    fn jst_epoch(s: &str) -> i64 {
        let naive = chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M").unwrap();
        naive.and_utc().timestamp() - 9 * 3600
    }

    fn archived(starts: Option<&str>, ends: Option<&str>) -> ShowTicket {
        let mut t = ticket("s", TicketKind::Stream, "配信", 7_000, 0);
        t.archive_starts_at = starts.map(Into::into);
        t.archive_ends_at = ends.map(Into::into);
        t
    }

    #[test]
    fn archive_period_and_state() {
        let t = archived(Some("2026-09-28 18:00"), Some("2026-10-05 23:59"));
        let before = ticket_archive(&t, jst_epoch("2026-09-28 17:59")).unwrap();
        assert_eq!(before.state, ArchiveState::Upcoming);
        assert_eq!(before.period_label, "アーカイブ 9/28 18:00〜10/5 23:59");
        assert_eq!(before.note, "アーカイブ 9/28 18:00〜10/5 23:59・公開前");
        // 両端を含む。
        assert_eq!(ticket_archive(&t, jst_epoch("2026-09-28 18:00")).unwrap().state, ArchiveState::Open);
        assert_eq!(ticket_archive(&t, jst_epoch("2026-10-05 23:59")).unwrap().state, ArchiveState::Open);
        let after = ticket_archive(&t, jst_epoch("2026-10-06 00:00")).unwrap();
        assert_eq!(after.state, ArchiveState::Ended);
        assert_eq!(after.state_label, "終了");
    }

    #[test]
    fn archive_with_one_side_or_date_only() {
        // 終わりだけ・日付だけ → その日いっぱい公開中。
        let t = archived(None, Some("2026-10-05"));
        let a = ticket_archive(&t, jst_epoch("2026-10-05 23:00")).unwrap();
        assert_eq!(a.period_label, "アーカイブ 〜10/5");
        assert_eq!(a.state, ArchiveState::Open);
        // 始まりだけ → 終わりの無い公開中。
        let t = archived(Some("2026-09-28 18:00"), None);
        assert_eq!(ticket_archive(&t, jst_epoch("2027-01-01 00:00")).unwrap().period_label, "アーカイブ 9/28 18:00〜");
        // 無い・読めない → 出さない。
        assert!(ticket_archive(&archived(None, None), 0).is_none());
        assert!(ticket_archive(&archived(Some("10月5日"), Some("")), 0).is_none());
    }

    /// 両 OS の TicketExpensePrompt から移した「聞くかどうか」。
    #[test]
    fn prompt_only_when_tickets_exist_and_nothing_is_recorded_yet() {
        let tickets = sample();
        let prompt = ticket_expense_prompt(&tickets, "live", &[]).expect("現地の券がある");
        assert_eq!(prompt.kind, TicketKind::Live);
        assert_eq!(prompt.tickets, tickets_for_kind(&tickets, TicketKind::Live));
        // 形態なし (旧データ) は現地扱い。
        assert_eq!(ticket_expense_prompt(&tickets, "", &[]).map(|p| p.kind), Some(TicketKind::Live));
        // その形態のチケット代を記録済みなら聞かない。ほかの費目は関係ない。
        assert!(ticket_expense_prompt(&tickets, "live", &[recorded("ticket", Some("live"), None)]).is_none());
        assert!(ticket_expense_prompt(&tickets, "live", &[recorded("transport", None, None)]).is_some());
        // 現地のチケット代があっても、あとから足した配信は聞く (現地 + アーカイブ購入)。
        let live_recorded = [recorded("ticket", Some("live"), Some("S席"))];
        assert_eq!(
            ticket_expense_prompt(&tickets, "stream", &live_recorded).map(|p| p.kind),
            Some(TicketKind::Stream)
        );
        // その形態の券が無ければ聞かない。
        let live_only: Vec<ShowTicket> =
            tickets.iter().filter(|t| t.kind == TicketKind::Live).cloned().collect();
        assert!(ticket_expense_prompt(&live_only, "live_viewing", &[]).is_none());
    }

    fn recorded(category: &str, kind: Option<&str>, note: Option<&str>) -> RecordedShowExpense {
        RecordedShowExpense {
            category: category.into(),
            ticket_kind: kind.map(Into::into),
            note: note.map(Into::into),
        }
    }

    /// 形態を持たない古いチケット代は、メモの券種名から形態を読む。読めなければ全部記録済み。
    #[test]
    fn legacy_ticket_rows_are_read_by_note_or_block_everything() {
        let tickets = sample();
        let legacy = |note: Option<&str>| [recorded("ticket", None, note)];
        // 確認シートで記録した行 (メモ = 券種名)。
        assert!(ticket_kind_recorded(TicketKind::Live, &tickets, &legacy(Some("S席"))));
        assert!(!ticket_kind_recorded(TicketKind::Stream, &tickets, &legacy(Some("S席"))));
        assert!(ticket_kind_recorded(TicketKind::Stream, &tickets, &legacy(Some("配信 (アーカイブ付き)"))));
        let mut estimate = tickets.clone();
        estimate[0].is_estimate = true;
        assert!(!ticket_kind_recorded(TicketKind::Stream, &estimate, &legacy(Some("S席 (推定)"))));
        assert!(ticket_kind_recorded(TicketKind::Live, &estimate, &legacy(Some("S席 (推定)"))));
        // 手で入れた行 (メモが券種名でない・無い) は形態が分からないので、どれも記録済み。
        for kind in [TicketKind::Live, TicketKind::Stream, TicketKind::LiveViewing] {
            assert!(ticket_kind_recorded(kind, &tickets, &legacy(Some("一般"))));
            assert!(ticket_kind_recorded(kind, &tickets, &legacy(None)));
        }
        // 知らない形態の保存値も同じ (古いメモの読み方に倒す)。
        assert!(ticket_kind_recorded(TicketKind::Stream, &tickets, &[recorded("ticket", Some("x"), None)]));
    }

    #[test]
    fn ticket_kind_raw_round_trips() {
        for kind in [TicketKind::Live, TicketKind::Stream, TicketKind::LiveViewing] {
            assert_eq!(ticket_kind_from_raw(&ticket_kind_raw(kind)), Some(kind));
            assert_eq!(ticket_kind_from_attendance(&ticket_kind_raw(kind)), kind);
        }
    }

    #[test]
    fn backfill_lists_unrecorded_shows_and_preselects_only_a_single_candidate() {
        let input = |show: &str, attendance: &str, tickets: Vec<ShowTicket>, existing: Vec<RecordedShowExpense>| {
            TicketBackfillInput {
                show_id: show.into(),
                attendance_type: attendance.into(),
                tickets,
                existing_expenses: existing,
            }
        };
        let items = ticket_expense_backfill(&[
            // 現地の券が 2 種 → 候補に出すが選ばせる。
            input("multi", "live", sample(), vec![]),
            // LV は 1 種 → 最初から選んでおく。ほかの費目があっても関係ない。
            input("single", "live_viewing", sample(), vec![recorded("transport", None, None)]),
            // 記録済み → 出さない。
            input("done", "live", sample(), vec![recorded("ticket", Some("live"), None)]),
            // 券種が無い → 出さない。
            input("none", "live", vec![], vec![]),
            // 現地 + 配信で参加し、現地だけ記録済み → 配信だけ出す。
            input("both", "live,stream", sample(), vec![recorded("ticket", Some("live"), None)]),
        ]);
        let ids: Vec<&str> = items.iter().map(|i| i.show_id.as_str()).collect();
        assert_eq!(ids, ["multi", "single", "both"]);
        assert_eq!(items[2].kind, TicketKind::Stream);
        // どちらも未記録なら形態ごとに 2 つ出る。
        let both = ticket_expense_backfill(&[input("both", "stream,live", sample(), vec![])]);
        assert_eq!(both.iter().map(|i| i.kind).collect::<Vec<_>>(), [TicketKind::Live, TicketKind::Stream]);
        assert_eq!(items[0].preselected, None);
        assert_eq!(items[0].tickets.len(), 2);
        assert_eq!(items[1].kind, TicketKind::LiveViewing);
        assert_eq!(items[1].preselected.as_ref().map(|t| t.price), Some(4_500));
    }

    #[test]
    fn expense_note_marks_estimates() {
        let mut t = ticket("t", TicketKind::Live, "S席", 13200, 0);
        assert_eq!(ticket_expense_note(&t), "S席");
        t.is_estimate = true;
        assert_eq!(ticket_expense_note(&t), "S席 (推定)");
    }

    fn sample() -> Vec<ShowTicket> {
        vec![
            ticket("t1", TicketKind::Live, "S席", 13_200, 1),
            ticket("t2", TicketKind::Live, "A席", 9_900, 2),
            ticket("t3", TicketKind::Stream, "配信", 5_500, 1),
            ticket("t4", TicketKind::Stream, "配信 (アーカイブ付き)", 6_600, 2),
            ticket("t5", TicketKind::LiveViewing, "ライブビューイング", 4_500, 1),
        ]
    }

    /// 並び順が全部 0 でも端末間でぶれない (価格の高い順 → 名前)。
    #[test]
    fn falls_back_to_price_then_name() {
        let tickets = vec![
            ticket("a", TicketKind::Live, "立見", 8_800, 0),
            ticket("b", TicketKind::Live, "アリーナ", 13_200, 0),
            ticket("c", TicketKind::Live, "見切れ", 8_800, 0),
        ];
        let live = tickets_for_kind(&tickets, TicketKind::Live);
        assert_eq!(
            live.iter().map(|t| t.name.as_str()).collect::<Vec<_>>(),
            ["アリーナ", "立見", "見切れ"]
        );
    }

    /// 候補が 1 つのときだけ既定が決まる (勝手に高い方を選ばない)。
    #[test]
    fn default_is_only_decided_when_unambiguous() {
        assert!(default_ticket(&sample(), TicketKind::Live).is_none());
        assert_eq!(
            default_ticket(&sample(), TicketKind::LiveViewing).map(|t| t.name),
            Some("ライブビューイング".to_string())
        );
        assert!(default_ticket(&[], TicketKind::Live).is_none());
    }

    #[test]
    fn price_range_reads_min_and_max() {
        let live = price_range(&sample(), TicketKind::Live).expect("現地の券がある");
        assert_eq!(live.min, 9_900);
        assert_eq!(live.max, 13_200);
        assert_eq!(live.count, 2);
        assert_eq!(live.label, "¥9,900〜¥13,200");
        assert!(!live.has_estimate);

        let lv = price_range(&sample(), TicketKind::LiveViewing).expect("LV の券がある");
        // 1 種だけなら範囲ではなく 1 つの額。
        assert_eq!(lv.label, "¥4,500");
    }

    /// 推定が 1 件でも混じれば札が立つ (推定を実額の顔で出さない)。
    #[test]
    fn estimate_flag_bubbles_up() {
        let mut tickets = sample();
        tickets[1].is_estimate = true;
        assert!(price_range(&tickets, TicketKind::Live).unwrap().has_estimate);
        assert!(!price_range(&tickets, TicketKind::Stream).unwrap().has_estimate);
    }

    /// 並びは 現地 → LV → 配信。券が無い形態は出さない。
    #[test]
    fn ranges_are_ordered_live_first() {
        let ranges = price_ranges(&sample());
        assert_eq!(
            ranges.iter().map(|r| r.kind).collect::<Vec<_>>(),
            [TicketKind::Live, TicketKind::LiveViewing, TicketKind::Stream]
        );

        let stream_only = vec![ticket("a", TicketKind::Stream, "配信", 5_500, 1)];
        assert_eq!(price_ranges(&stream_only).len(), 1);
        assert!(price_ranges(&[]).is_empty());
    }

    #[test]
    fn attendance_maps_to_kind_with_live_fallback() {
        assert_eq!(ticket_kind_from_attendance("live"), TicketKind::Live);
        assert_eq!(ticket_kind_from_attendance("stream"), TicketKind::Stream);
        assert_eq!(ticket_kind_from_attendance("live_viewing"), TicketKind::LiveViewing);
        // 旧データ (種別なし) は現地扱い。回収率の判定と同じ約束。
        assert_eq!(ticket_kind_from_attendance(""), TicketKind::Live);
        assert_eq!(ticket_kind_from_attendance("unknown"), TicketKind::Live);
    }

    #[test]
    fn input_is_validated() {
        assert_eq!(validate_ticket("S席", 13_200), None);
        assert_eq!(validate_ticket("", 13_200), Some(TicketInputError::EmptyName));
        assert_eq!(validate_ticket("  ", 13_200), Some(TicketInputError::EmptyName));
        assert_eq!(validate_ticket("S席", 0), Some(TicketInputError::NotPositive));
        assert_eq!(validate_ticket("S席", 1_000_001), Some(TicketInputError::TooLarge));
    }

    #[test]
    fn kind_labels() {
        assert_eq!(ticket_kind_label(TicketKind::Live), "現地");
        assert_eq!(ticket_kind_label(TicketKind::Stream), "配信");
        assert_eq!(ticket_kind_label(TicketKind::LiveViewing), "LV");
    }
}
