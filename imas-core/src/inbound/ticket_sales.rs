//! チケット受付の FFI 面。ロジックは domain::ticket_sales。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::ticket_sales::{self as sales, TicketSale, TicketSaleDeadline, TicketSaleDraft, TicketSaleIssue, TicketSaleKind, OpenTicketSale, TicketApplication, TicketSaleStage};

#[uniffi::export]
impl SnapshotStore {
    /// イベント配下の受付一覧 (並び済み)。`now_epoch_seconds` で段階を判定する。
    pub fn ticket_sales_for_event(
        &self,
        event_id: String,
        now_epoch_seconds: i64,
    ) -> Result<Vec<TicketSale>, SnapshotError> {
        let snap = self.current()?;
        Ok(sales::sales_for_event(&snap, &event_id, now_epoch_seconds))
    }

    /// 「一番近い・一番大事な受付」1 件 (一覧の先頭・カードに出す用)。
    pub fn ticket_sale_spotlight(
        &self,
        event_id: String,
        now_epoch_seconds: i64,
    ) -> Result<Option<TicketSale>, SnapshotError> {
        let snap = self.current()?;
        Ok(sales::spotlight(&snap, &event_id, now_epoch_seconds))
    }

    /// 全イベント横断の「いま受付中」の受付 (ライブ一覧の頭)。締切の近い順。
    pub fn open_ticket_sales(&self, now_epoch_seconds: i64) -> Result<Vec<OpenTicketSale>, SnapshotError> {
        let snap = self.current()?;
        Ok(sales::open_sales(&snap, now_epoch_seconds))
    }

    /// 全ライブ横断の「いま見られるアーカイブ」(ライブ一覧の頭)。終わりの近い順。
    pub fn open_archives(
        &self,
        now_epoch_seconds: i64,
    ) -> Result<Vec<crate::domain::stream_archives::OpenArchive>, SnapshotError> {
        let snap = self.current()?;
        Ok(crate::domain::stream_archives::open_archives(&snap, now_epoch_seconds))
    }

    /// 全イベント横断の締切一覧 (ウィジェット・通知の材料)。近い順、上限 `limit` 件。
    pub fn ticket_sale_deadlines(
        &self,
        now_epoch_seconds: i64,
        limit: u32,
    ) -> Result<Vec<TicketSaleDeadline>, SnapshotError> {
        let snap = self.current()?;
        Ok(sales::deadlines(&snap, now_epoch_seconds, limit))
    }
}

/// 編集フォームの入力検査。通れば空の `Vec`。
#[uniffi::export]
pub fn validate_ticket_sale_draft(draft: TicketSaleDraft, event_show_ids: Vec<String>) -> Vec<TicketSaleIssue> {
    sales::validate_draft(&draft, &event_show_ids)
}

/// 検査結果 1 件の文言。
#[uniffi::export]
pub fn ticket_sale_issue_message(issue: TicketSaleIssue) -> String {
    sales::issue_message(issue)
}

/// 自由記述の日時を正規化する (`"2026/4/12 23:59"` → `"2026-04-12 23:59"`)。
#[uniffi::export]
pub fn normalize_ticket_sale_moment(input: String) -> Option<String> {
    sales::normalize_moment(&input)
}

/// 申込の記録の保存値 (`user_marks.text_value`)。
#[uniffi::export]
pub fn ticket_application_raw(application: TicketApplication) -> String {
    sales::ticket_application_raw(application)
}

/// 保存値 → 申込の記録。知らない値・空は `None`。
#[uniffi::export]
pub fn ticket_application_from_raw(raw: Option<String>) -> Option<TicketApplication> {
    sales::ticket_application_from_raw(raw.as_deref())
}

/// 申込の記録の表示文字列 (先着・当日券の申込済みは「購入済み」)。
#[uniffi::export]
pub fn ticket_application_label(kind: TicketSaleKind, application: TicketApplication) -> String {
    sales::ticket_application_label(kind, application)
}

/// いま選べる申込の記録 (当選・落選は抽選のある受付で当落発表の日から)。
#[uniffi::export]
pub fn ticket_application_choices(
    kind: TicketSaleKind,
    stage: TicketSaleStage,
    result_at: Option<String>,
    now_epoch_seconds: i64,
) -> Vec<TicketApplication> {
    sales::ticket_application_choices(kind, stage, result_at.as_deref(), now_epoch_seconds)
}

/// 受付種別の保存値。
#[uniffi::export]
pub fn ticket_sale_kind_raw(kind: TicketSaleKind) -> String {
    sales::ticket_sale_kind_raw(kind)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ticket_sales::TicketSaleField;

    /// FFI 関数が domain へ委譲していること (疎通確認だけ)。
    #[test]
    fn delegates_to_domain() {
        let draft = TicketSaleDraft {
            event_id: "e1".into(),
            show_ids: vec![],
            kind: TicketSaleKind::Lottery,
            name: "".into(),
            starts_at: None,
            ends_at: None,
            result_at: None,
            url: None,
            note: None,
            source_url: "".into(),
            sort_order: 0,
        };
        let issues = validate_ticket_sale_draft(draft, vec![]);
        assert!(issues.contains(&TicketSaleIssue::Missing { field: TicketSaleField::Name }));
        assert!(!ticket_sale_issue_message(issues[0].clone()).is_empty());
        assert_eq!(normalize_ticket_sale_moment("2026/4/1".into()), Some("2026-04-01".to_string()));
        assert_eq!(ticket_sale_kind_raw(TicketSaleKind::Resale), "resale");
    }

    #[test]
    fn ffi_surface_smoke() {
        let store = crate::test_support::bundle_store();
        // 実データの受付は日々増減するので、件数ではなく「締切に出た受付がそのイベントの
        // 一覧にも出る」ことだけを確かめる (Bundle に受付が無ければ全部空で通る)。
        let deadlines = store.ticket_sale_deadlines(0, 5).unwrap();
        assert!(deadlines.len() <= 5);
        let Some(first) = deadlines.first() else { return };
        let sales = store.ticket_sales_for_event(first.event_id.clone(), 0).unwrap();
        assert!(sales.iter().any(|s| s.id == first.sale_id));
        assert!(store.ticket_sale_spotlight(first.event_id.clone(), 0).unwrap().is_some());
    }
}
