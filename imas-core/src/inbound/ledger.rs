//! 収支 (家計簿) の FFI 面。ロジックは domain::ledger。
//!
//! 帳簿ぜんぶを 1 回で渡して、集計済みの箱を受け取る。
//! 1 件ずつ呼ぶと数千件で数千回の境界越えになる。

use crate::domain::ledger::{
    ExpenseCategory, ExpenseCategoryInfo, ExpenseEntry, ExpenseInputError, LedgerFilter,
    LedgerPeriod, LedgerSummary, ShowTotal,
};

#[uniffi::export]
pub fn expense_categories() -> Vec<ExpenseCategoryInfo> {
    crate::domain::ledger::expense_categories()
}

#[uniffi::export]
pub fn expense_category_from_key(key: String) -> ExpenseCategory {
    crate::domain::ledger::expense_category_from_key(&key)
}

#[uniffi::export]
pub fn expense_category_key(category: ExpenseCategory) -> String {
    crate::domain::ledger::expense_category_key(category)
}

#[uniffi::export]
pub fn expense_category_label(category: ExpenseCategory) -> String {
    crate::domain::ledger::expense_category_label(category)
}

#[uniffi::export]
pub fn format_yen(amount: i64) -> String {
    crate::domain::ledger::format_yen(amount)
}

#[uniffi::export]
pub fn validate_expense(date: String, amount: i64) -> Option<ExpenseInputError> {
    crate::domain::ledger::validate_expense(&date, amount)
}

#[uniffi::export]
pub fn build_ledger_summary(
    entries: Vec<ExpenseEntry>,
    period: LedgerPeriod,
    filter: LedgerFilter,
) -> LedgerSummary {
    crate::domain::ledger::build_ledger_summary(&entries, period, &filter)
}

#[uniffi::export]
pub fn ledger_show_totals(entries: Vec<ExpenseEntry>, filter: LedgerFilter) -> Vec<ShowTotal> {
    crate::domain::ledger::show_totals(&entries, &filter)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ledger::LedgerLinkage;

    /// FFI 関数が domain へ委譲していること (値渡し = FFI と同じ所有権移動)。
    #[test]
    fn delegates_to_domain() {
        let entries = vec![ExpenseEntry {
            id: "a".into(),
            date: "2026-09-19".into(),
            category: ExpenseCategory::Ticket,
            amount: 9_000,
            show_id: Some("s1".into()),
            event_id: Some("ev1".into()),
            show_label: Some("公演".into()),
            note: None,
        }];
        let filter = LedgerFilter {
            year: String::new(),
            categories: vec![],
            linkage: LedgerLinkage::All,
            event_id: String::new(),
        };

        let expected =
            crate::domain::ledger::build_ledger_summary(&entries, LedgerPeriod::Month, &filter);
        assert_eq!(
            build_ledger_summary(entries.clone(), LedgerPeriod::Month, filter.clone()),
            expected
        );
        assert_eq!(ledger_show_totals(entries, filter).len(), 1);

        assert_eq!(expense_categories().len(), 9);
        assert_eq!(expense_category_key(ExpenseCategory::Lodging), "lodging");
        assert_eq!(expense_category_from_key("lodging".into()), ExpenseCategory::Lodging);
        assert_eq!(expense_category_label(ExpenseCategory::Party), "打ち上げ代");
        assert_eq!(format_yen(12_345), "¥12,345");
        assert_eq!(validate_expense("2026-09-19".into(), 0), Some(ExpenseInputError::NotPositive));
    }
}
