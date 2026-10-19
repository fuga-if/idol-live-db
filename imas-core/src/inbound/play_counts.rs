//! 再生回数の積み残しの FFI 面。規則は [`crate::domain::play_counts`]。

use crate::domain::play_counts::{self as domain, PlayKind, PlayLog, PlayTally};

/// 保存された文字列を読む。
#[uniffi::export]
pub fn play_log_decode(text: String) -> PlayLog {
    domain::decode(&text)
}

/// 保存用の文字列。
#[uniffi::export]
pub fn play_log_encode(log: PlayLog) -> String {
    domain::encode(&log)
}

/// 何秒流れたら 1 回と数えるか。
#[uniffi::export]
pub fn play_count_after_seconds(kind: PlayKind) -> f64 {
    domain::count_after_seconds(kind)
}

/// 1 回数える。
#[uniffi::export]
pub fn play_log_record(log: PlayLog, song_id: String, kind: PlayKind) -> PlayLog {
    domain::record(&log, &song_id, kind)
}

/// いま送るもの (空なら送らない)。
#[uniffi::export]
pub fn play_log_due(log: PlayLog, now: f64) -> Vec<PlayTally> {
    domain::due(&log, now)
}

/// 送ろうとした時刻を残す。
#[uniffi::export]
pub fn play_log_mark_attempt(log: PlayLog, now: f64) -> PlayLog {
    domain::mark_attempt(&log, now)
}

/// 送れた分を引く。
#[uniffi::export]
pub fn play_log_after_sent(log: PlayLog, sent: Vec<PlayTally>) -> PlayLog {
    domain::after_sent(&log, &sent)
}

/// `POST /plays/batch` の本文。
#[uniffi::export]
pub fn play_batch_body(batch: Vec<PlayTally>) -> String {
    domain::batch_body(&batch)
}
