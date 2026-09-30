//! 通販の購入明細の取り込みの FFI 面。ロジックは domain::store_order。
//!
//! 貼り付けたテキスト全体を 1 回で渡して、読めた注文をまとめて受け取る。

use crate::domain::store_order::{AiPromptLink, StoreExpenseDraft, StoreOrder, StoreShowCandidate};

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

/// AI に購入明細をまとめさせる指示文 (コピー用)。
#[uniffi::export]
pub fn store_order_ai_prompt() -> String {
    crate::domain::store_order::store_order_ai_prompt()
}

/// 指示文を入れて AI を開くリンク。
#[uniffi::export]
pub fn store_order_ai_links() -> Vec<AiPromptLink> {
    crate::domain::store_order::store_order_ai_links()
}
