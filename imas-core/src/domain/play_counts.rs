//! 曲の再生回数をみんなの集計 (`POST /plays/batch`) に送るための端末側の規則。
//!
//! 試聴 (30 秒の音源) とフル再生 (Apple Music / Spotify) を別々に数える。
//!
//! 規則:
//! - 1 回と数えるのは、試聴は [`PREVIEW_COUNT_AFTER_SECONDS`] 秒、フル再生は
//!   [`FULL_COUNT_AFTER_SECONDS`] 秒続けて流れたとき。押してすぐ止めた分は数えない。
//!   端末は再生を始めたらこの秒数のあとに「まだ同じ曲が流れているか」を見て [`record`] を呼ぶ。
//! - 数えた分は端末に貯めておき、まとめて送る。送るのは前回の送信から
//!   [`SEND_INTERVAL_SECONDS`] 以上たったときだけ (送信回数を抑えて、Worker と D1 の
//!   有料プランの枠に収めるため。サーバ側でも端末ごとに 1 日の送信回数を制限している)。
//! - 送れたら送った分だけ引く (送っている間に数えた分は残る)。失敗したら貯めたまま次に回す。
//!
//! OS 側に残すのは、保存 (UserDefaults / SharedPreferences に [`encode`] の文字列を置く)、
//! 秒数を待つタイマ、実際の送信だけ。

use serde_json::Value;

/// 試聴をこの秒数続けて流したら 1 回。
pub const PREVIEW_COUNT_AFTER_SECONDS: f64 = 5.0;
/// フル再生をこの秒数続けて流したら 1 回。
pub const FULL_COUNT_AFTER_SECONDS: f64 = 30.0;
/// 送信の間隔の下限 (秒)。
pub const SEND_INTERVAL_SECONDS: f64 = 3600.0;
/// 1 回に送る曲数の上限 (サーバの受け付ける上限と同じ)。残りは次の送信に回る。
pub const MAX_BATCH_SONGS: usize = 500;

/// 再生の種類。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PlayKind {
    /// 試聴 (30 秒の音源)。
    Preview,
    /// フル再生 (Apple Music / Spotify)。
    Full,
}

/// 1 曲ぶんの回数。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PlayTally {
    pub song_id: String,
    pub preview: u32,
    pub full: u32,
}

/// 端末に貯めている、まだ送っていない回数。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct PlayLog {
    /// 曲ごとの回数 (数えた順)。
    pub pending: Vec<PlayTally>,
    /// 最後に送ろうとした時刻 (epoch 秒。まだなら 0)。
    pub last_attempt_at: f64,
}

/// 何秒流れたら 1 回と数えるか。
pub fn count_after_seconds(kind: PlayKind) -> f64 {
    match kind {
        PlayKind::Preview => PREVIEW_COUNT_AFTER_SECONDS,
        PlayKind::Full => FULL_COUNT_AFTER_SECONDS,
    }
}

/// 1 回数える。
pub fn record(log: &PlayLog, song_id: &str, kind: PlayKind) -> PlayLog {
    let mut next = log.clone();
    if song_id.is_empty() {
        return next;
    }
    let tally = match next.pending.iter_mut().find(|t| t.song_id == song_id) {
        Some(t) => t,
        None => {
            next.pending.push(PlayTally { song_id: song_id.to_string(), preview: 0, full: 0 });
            next.pending.last_mut().expect("直前に足した")
        }
    };
    match kind {
        PlayKind::Preview => tally.preview = tally.preview.saturating_add(1),
        PlayKind::Full => tally.full = tally.full.saturating_add(1),
    }
    next
}

/// いま送るもの。送る時期でない・送るものが無いときは空。
pub fn due(log: &PlayLog, now: f64) -> Vec<PlayTally> {
    // まだ一度も送っていない (0) ときと、時計が巻き戻った (前回が未来) ときは待たない。
    let waited = now - log.last_attempt_at;
    if log.last_attempt_at > 0.0 && (0.0..SEND_INTERVAL_SECONDS).contains(&waited) {
        return Vec::new();
    }
    log.pending
        .iter()
        .filter(|t| t.preview > 0 || t.full > 0)
        .take(MAX_BATCH_SONGS)
        .cloned()
        .collect()
}

/// 送ろうとした時刻を残す (成否にかかわらず、次の送信はここから数える)。
pub fn mark_attempt(log: &PlayLog, now: f64) -> PlayLog {
    PlayLog { pending: log.pending.clone(), last_attempt_at: now }
}

/// 送れた分を引く。送っている間に数えた分は残る。0 になった曲は消す。
pub fn after_sent(log: &PlayLog, sent: &[PlayTally]) -> PlayLog {
    let pending = log
        .pending
        .iter()
        .filter_map(|t| {
            let mut t = t.clone();
            if let Some(s) = sent.iter().find(|s| s.song_id == t.song_id) {
                t.preview = t.preview.saturating_sub(s.preview);
                t.full = t.full.saturating_sub(s.full);
            }
            (t.preview > 0 || t.full > 0).then_some(t)
        })
        .collect();
    PlayLog { pending, last_attempt_at: log.last_attempt_at }
}

/// `POST /plays/batch` の本文。
pub fn batch_body(batch: &[PlayTally]) -> String {
    let plays: Vec<Value> = batch
        .iter()
        .map(|t| serde_json::json!({ "song_id": t.song_id, "preview": t.preview, "full": t.full }))
        .collect();
    serde_json::json!({ "plays": plays }).to_string()
}

/// 保存用の文字列。
pub fn encode(log: &PlayLog) -> String {
    let pending: Vec<Value> = log
        .pending
        .iter()
        .map(|t| serde_json::json!({ "songId": t.song_id, "preview": t.preview, "full": t.full }))
        .collect();
    serde_json::json!({ "pending": pending, "lastAttemptAt": log.last_attempt_at }).to_string()
}

/// 保存された文字列を読む。読めなければ空。読めない要素は飛ばし、同じ曲は足し合わせる。
pub fn decode(text: &str) -> PlayLog {
    let mut log = PlayLog { pending: Vec::new(), last_attempt_at: 0.0 };
    let Ok(Value::Object(obj)) = serde_json::from_str::<Value>(text) else {
        return log;
    };
    log.last_attempt_at = obj.get("lastAttemptAt").and_then(Value::as_f64).unwrap_or(0.0);
    let count = |v: Option<&Value>| v.and_then(Value::as_u64).unwrap_or(0).min(u32::MAX as u64) as u32;
    for item in obj.get("pending").and_then(Value::as_array).into_iter().flatten() {
        let Some(song_id) = item.get("songId").and_then(Value::as_str).filter(|s| !s.is_empty()) else {
            continue;
        };
        let (preview, full) = (count(item.get("preview")), count(item.get("full")));
        match log.pending.iter_mut().find(|t| t.song_id == song_id) {
            Some(t) => {
                t.preview = t.preview.saturating_add(preview);
                t.full = t.full.saturating_add(full);
            }
            None => log.pending.push(PlayTally { song_id: song_id.to_string(), preview, full }),
        }
    }
    log.pending.retain(|t| t.preview > 0 || t.full > 0);
    log
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty() -> PlayLog {
        PlayLog { pending: Vec::new(), last_attempt_at: 0.0 }
    }

    fn tally(id: &str, preview: u32, full: u32) -> PlayTally {
        PlayTally { song_id: id.into(), preview, full }
    }

    #[test]
    fn 試聴とフルを曲ごとに別々に数える() {
        let log = record(&empty(), "s1", PlayKind::Preview);
        let log = record(&log, "s2", PlayKind::Full);
        let log = record(&log, "s1", PlayKind::Preview);
        let log = record(&log, "s1", PlayKind::Full);
        assert_eq!(log.pending, vec![tally("s1", 2, 1), tally("s2", 0, 1)]);
        assert_eq!(record(&empty(), "", PlayKind::Full).pending, vec![]);
    }

    #[test]
    fn 数える秒数は試聴5秒フル30秒() {
        assert_eq!(count_after_seconds(PlayKind::Preview), 5.0);
        assert_eq!(count_after_seconds(PlayKind::Full), 30.0);
    }

    #[test]
    fn 前回から1時間たつまで送らない() {
        let log = record(&empty(), "s1", PlayKind::Preview);
        assert_eq!(due(&log, 100.0), vec![tally("s1", 1, 0)]);
        let sent = mark_attempt(&log, 100.0);
        assert!(due(&sent, 100.0 + SEND_INTERVAL_SECONDS - 1.0).is_empty());
        assert_eq!(due(&sent, 100.0 + SEND_INTERVAL_SECONDS), vec![tally("s1", 1, 0)]);
        // 時計が巻き戻ったら送ってよい
        assert_eq!(due(&sent, 50.0), vec![tally("s1", 1, 0)]);
        assert!(due(&empty(), 1e9).is_empty());
    }

    #[test]
    fn 一度に送るのは上限まで() {
        let mut log = empty();
        for i in 0..(MAX_BATCH_SONGS + 3) {
            log = record(&log, &format!("s{i}"), PlayKind::Full);
        }
        assert_eq!(due(&log, 1e9).len(), MAX_BATCH_SONGS);
    }

    #[test]
    fn 送れた分だけ引き_送る間に数えた分は残る() {
        let log = record(&record(&empty(), "s1", PlayKind::Preview), "s2", PlayKind::Full);
        let batch = due(&log, 1e9);
        let log = mark_attempt(&log, 1e9);
        let log = record(&log, "s1", PlayKind::Preview);
        let log = after_sent(&log, &batch);
        assert_eq!(log.pending, vec![tally("s1", 1, 0)]);
        assert_eq!(log.last_attempt_at, 1e9);
    }

    #[test]
    fn 本文はsnake_case() {
        assert_eq!(
            batch_body(&[tally("s1", 2, 1)]),
            r#"{"plays":[{"full":1,"preview":2,"song_id":"s1"}]}"#
        );
    }

    #[test]
    fn 書いたものを読み戻せる() {
        let log = PlayLog { pending: vec![tally("s\"1", 3, 0), tally("s2", 0, 4)], last_attempt_at: 7.5 };
        assert_eq!(decode(&encode(&log)), log);
    }

    #[test]
    fn 壊れた要素は飛ばし同じ曲は足す() {
        let text = r#"{"pending":[{"songId":"s1","preview":1},{"songId":""},7,{"songId":"s1","full":2},{"songId":"s3"}],"lastAttemptAt":"x"}"#;
        assert_eq!(decode(text), PlayLog { pending: vec![tally("s1", 1, 2)], last_attempt_at: 0.0 });
        assert_eq!(decode(""), empty());
        assert_eq!(decode("[]"), empty());
    }
}
