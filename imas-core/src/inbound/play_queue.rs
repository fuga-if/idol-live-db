//! 曲送りとプレイリストの並びの FFI 口。規則は domain::play_queue。

use crate::domain::play_queue as d;

/// 「前の曲」で鳴らす曲の添字。今の曲の頭出しなら `index` のまま。
#[uniffi::export]
pub fn play_queue_previous_index(index: u32, position_ms: i64) -> u32 {
    d::previous_index(index, position_ms)
}

/// 「次の曲」の添字。最後の曲なら `None`。
#[uniffi::export]
pub fn play_queue_next_index(index: u32, len: u32) -> Option<u32> {
    d::next_index(index, len)
}

/// プレイリストに曲を足した後の並び (既にある曲は足さない)。
#[uniffi::export]
pub fn playlist_append_songs(existing: Vec<String>, adding: Vec<String>) -> Vec<String> {
    d::append_songs(&existing, &adding)
}

/// 曲を 1 つ動かした後の並び。
#[uniffi::export]
pub fn playlist_move_song(ids: Vec<String>, from: u32, to: u32) -> Vec<String> {
    d::move_song(&ids, from, to)
}
