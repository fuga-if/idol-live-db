//! 通販の購入明細の取り込みの FFI 面。ロジックは domain::store_order。
//!
//! 貼り付けたテキスト全体を 1 回で渡して、読めた注文をまとめて受け取る。

use crate::domain::store_order::{StoreExpenseDraft, StoreOrder, StoreOrderItem, StoreShowCandidate};

#[uniffi::export]
pub fn parse_store_orders(
    text: String,
    today: String,
    candidates: Vec<StoreShowCandidate>,
    existing_notes: Vec<String>,
) -> Vec<StoreOrder> {
    crate::domain::store_order::parse_store_orders(&text, &today, &candidates, &existing_notes)
}

#[uniffi::export]
pub fn store_order_expenses(
    order: StoreOrder,
    show_id: Option<String>,
    event_id: Option<String>,
) -> Vec<StoreExpenseDraft> {
    crate::domain::store_order::store_order_expenses(&order, show_id, event_id)
}

/// 品目のうち帳簿に入れる額 (外したら 0、点数を減らしたら単価 × 点数)。画面の品目の額に出す。
#[uniffi::export]
pub fn store_order_item_amount(item: StoreOrderItem) -> i64 {
    item.counted_amount()
}

/// アソビストアのマイページの購入履歴一覧 (取り込み画面の案内で開く)。
#[uniffi::export]
pub fn asobi_order_history_url() -> String {
    crate::domain::store_order::ASOBI_ORDER_HISTORY_URL.to_string()
}
