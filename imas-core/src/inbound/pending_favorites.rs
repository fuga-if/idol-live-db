//! お気に入り送信の積み残しの FFI 面。規則は [`crate::domain::pending_favorites`]。

use crate::domain::pending_favorites::{self as domain, PendingFavorite, SendOutcome};

/// 保存された文字列を読む (両 OS のこれまでの形式も読む)。
#[uniffi::export]
pub fn pending_favorites_decode(text: String) -> Vec<PendingFavorite> {
    domain::decode(&text)
}

/// 保存用の文字列。
#[uniffi::export]
pub fn pending_favorites_encode(queue: Vec<PendingFavorite>) -> String {
    domain::encode(&queue)
}

/// 送れなかった値を積む (同じ曲の積み残しは置き換える)。
#[uniffi::export]
pub fn pending_favorites_enqueue(queue: Vec<PendingFavorite>, song_id: String, value: bool, now: f64) -> Vec<PendingFavorite> {
    domain::enqueue(&queue, &song_id, value, now)
}

/// その曲の積み残しを捨てる (送れたとき)。
#[uniffi::export]
pub fn pending_favorites_discard(queue: Vec<PendingFavorite>, song_id: String) -> Vec<PendingFavorite> {
    domain::discard(&queue, &song_id)
}

/// 送り直しを始めた時点の 1 件が、まだ列に残っているか。
#[uniffi::export]
pub fn pending_favorite_is_still_queued(queue: Vec<PendingFavorite>, item: PendingFavorite) -> bool {
    domain::is_still_queued(&queue, &item)
}

/// 送り直す前に待つ秒数。
#[uniffi::export]
pub fn pending_favorite_retry_delay_seconds(retry_count: u32) -> f64 {
    domain::retry_delay_seconds(retry_count)
}

/// 1 件を送り直した結果を列に反映する。
#[uniffi::export]
pub fn pending_favorites_after_attempt(queue: Vec<PendingFavorite>, item: PendingFavorite, outcome: SendOutcome) -> Vec<PendingFavorite> {
    domain::after_attempt(&queue, &item, outcome)
}
