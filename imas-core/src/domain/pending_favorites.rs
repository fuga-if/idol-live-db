//! お気に入りをみんなの集計 (`POST /favorites/toggle`) に送れなかったときの積み残しの規則。
//!
//! 付け外しのたびに背景で送り、失敗したら端末に積んでおいて、アプリが前面に出たときに
//! 送り直す。両 OS が同じ規則を別々に書いていて、送り直しの前に待つか (iOS は待ち、
//! Android は待たずに連打していた) が割れていたので、ここに寄せた。
//!
//! 規則:
//! - 積むのは曲ごとに 1 件。同じ曲をまた積むと前のものを置き換える (送るのは最後の意思だけ)。
//! - 送れたら、その曲の積み残しは捨てる。古い値を後から送ると集計が巻き戻る。
//! - 送り直しは 1 件ずつ。2 回目からは `2^失敗回数` 秒待ってから送る。
//! - [`MAX_RETRIES`] 回失敗したら諦めて捨てる。
//! - 送り直しの途中で同じ曲が積み直されたり捨てられたりしたら、その結果は反映しない。
//!   1 件は曲と積んだ時刻で見分ける。
//!
//! OS 側に残すのは、保存 (UserDefaults / SharedPreferences に [`encode`] の文字列を置く) と
//! 実際の送信だけ。

use serde_json::Value;

/// これだけ失敗したら諦める。
pub const MAX_RETRIES: u32 = 3;

/// 積んである 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct PendingFavorite {
    pub song_id: String,
    /// 送りたい値 (付けた = true)。
    pub value: bool,
    /// 積んだ時刻。1 件を見分けるためだけに使う (単位は OS 側の都合で決めてよい)。
    pub enqueued_at: f64,
    /// これまでに送り直して失敗した回数。
    pub retry_count: u32,
}

/// 送った結果。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SendOutcome {
    Sent,
    Failed,
}

fn same(a: &PendingFavorite, b: &PendingFavorite) -> bool {
    a.song_id == b.song_id && a.enqueued_at == b.enqueued_at
}

/// 送れなかった値を積む。同じ曲の積み残しは置き換える。
pub fn enqueue(queue: &[PendingFavorite], song_id: &str, value: bool, now: f64) -> Vec<PendingFavorite> {
    let mut next = discard(queue, song_id);
    next.push(PendingFavorite { song_id: song_id.to_string(), value, enqueued_at: now, retry_count: 0 });
    next
}

/// その曲の積み残しを捨てる (送れたとき)。
pub fn discard(queue: &[PendingFavorite], song_id: &str) -> Vec<PendingFavorite> {
    queue.iter().filter(|p| p.song_id != song_id).cloned().collect()
}

/// 送り直しを始めた時点の 1 件が、まだ最新の意思として残っているか。
pub fn is_still_queued(queue: &[PendingFavorite], item: &PendingFavorite) -> bool {
    queue.iter().any(|p| same(p, item))
}

/// 送り直す前に待つ秒数。初回は待たず、以降は `2^失敗回数`。
pub fn retry_delay_seconds(retry_count: u32) -> f64 {
    if retry_count == 0 { 0.0 } else { 2f64.powi(retry_count.min(16) as i32) }
}

/// 1 件を送り直した結果を列に反映する。送れたら捨て、失敗したら回数を数え、
/// 上限に達したら捨てる。待っている間に置き換わっていた・捨てられていたら何もしない。
pub fn after_attempt(queue: &[PendingFavorite], item: &PendingFavorite, outcome: SendOutcome) -> Vec<PendingFavorite> {
    queue
        .iter()
        .filter_map(|p| {
            if !same(p, item) {
                return Some(p.clone());
            }
            match outcome {
                SendOutcome::Sent => None,
                SendOutcome::Failed => {
                    let retry_count = p.retry_count + 1;
                    (retry_count < MAX_RETRIES).then(|| PendingFavorite { retry_count, ..p.clone() })
                }
            }
        })
        .collect()
}

/// 保存用の文字列。
pub fn encode(queue: &[PendingFavorite]) -> String {
    let items: Vec<Value> = queue
        .iter()
        .map(|p| {
            serde_json::json!({
                "songId": p.song_id,
                "value": p.value,
                "enqueuedAt": p.enqueued_at,
                "retryCount": p.retry_count,
            })
        })
        .collect();
    Value::Array(items).to_string()
}

/// 保存された文字列を読む。これまでの両 OS の形式 (iOS は `enqueuedAt` あり、Android は無し)
/// をどちらも読む。読めない要素は飛ばし、同じ曲が複数あれば後のものを残す。
pub fn decode(text: &str) -> Vec<PendingFavorite> {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(text) else {
        return Vec::new();
    };
    let mut queue: Vec<PendingFavorite> = Vec::new();
    for item in &items {
        let Some(obj) = item.as_object() else { continue };
        let (Some(song_id), Some(value)) = (
            obj.get("songId").and_then(Value::as_str).filter(|s| !s.is_empty()),
            obj.get("value").and_then(Value::as_bool),
        ) else {
            continue;
        };
        let enqueued_at = obj.get("enqueuedAt").and_then(Value::as_f64).unwrap_or(0.0);
        let retry_count = obj.get("retryCount").and_then(Value::as_u64).unwrap_or(0).min(u32::MAX as u64) as u32;
        queue.retain(|p| p.song_id != song_id);
        queue.push(PendingFavorite { song_id: song_id.to_string(), value, enqueued_at, retry_count });
    }
    queue
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(song_id: &str, value: bool, at: f64, retry_count: u32) -> PendingFavorite {
        PendingFavorite { song_id: song_id.into(), value, enqueued_at: at, retry_count }
    }

    #[test]
    fn 同じ曲を積み直すと最後の値だけが残る() {
        let q = enqueue(&[], "s1", true, 1.0);
        let q = enqueue(&q, "s2", true, 2.0);
        let q = enqueue(&q, "s1", false, 3.0);
        assert_eq!(q, vec![item("s2", true, 2.0, 0), item("s1", false, 3.0, 0)]);
    }

    #[test]
    fn 待ち時間は初回0でそのあと倍々() {
        assert_eq!(retry_delay_seconds(0), 0.0);
        assert_eq!(retry_delay_seconds(1), 2.0);
        assert_eq!(retry_delay_seconds(2), 4.0);
        assert!(retry_delay_seconds(u32::MAX).is_finite());
    }

    #[test]
    fn 送り直しで送れたら捨てる() {
        let a = item("s1", true, 1.0, 1);
        let q = vec![a.clone(), item("s2", false, 2.0, 0)];
        assert_eq!(after_attempt(&q, &a, SendOutcome::Sent), vec![item("s2", false, 2.0, 0)]);
    }

    #[test]
    fn 失敗は数えて_3回目で諦める() {
        let a = item("s1", true, 1.0, 0);
        let q = after_attempt(&[a.clone()], &a, SendOutcome::Failed);
        assert_eq!(q, vec![item("s1", true, 1.0, 1)]);
        let q = after_attempt(&q, &q[0].clone(), SendOutcome::Failed);
        assert_eq!(q, vec![item("s1", true, 1.0, 2)]);
        assert!(after_attempt(&q, &q[0].clone(), SendOutcome::Failed).is_empty());
    }

    #[test]
    fn 待つ間に積み直された曲は結果を反映しない() {
        let old = item("s1", true, 1.0, 1);
        let q = enqueue(&[old.clone()], "s1", false, 5.0);
        assert!(!is_still_queued(&q, &old));
        assert_eq!(after_attempt(&q, &old, SendOutcome::Sent), q);
        assert_eq!(after_attempt(&q, &old, SendOutcome::Failed), q);
    }

    #[test]
    fn 書いたものを読み戻せる() {
        let q = vec![item("s1", true, 780_000_000.5, 2), item("s\"2", false, 0.0, 0)];
        assert_eq!(decode(&encode(&q)), q);
    }

    #[test]
    fn これまでの両OSの保存形式を読む() {
        let ios = r#"[{"songId":"s1","value":true,"enqueuedAt":780000000.25,"retryCount":1}]"#;
        assert_eq!(decode(ios), vec![item("s1", true, 780_000_000.25, 1)]);
        let android = r#"[{"songId":"s2","value":false,"retryCount":2},{"songId":"s3","value":true}]"#;
        assert_eq!(decode(android), vec![item("s2", false, 0.0, 2), item("s3", true, 0.0, 0)]);
    }

    #[test]
    fn 壊れた要素は飛ばし_同じ曲は後を残す() {
        let text = r#"[{"songId":"s1","value":true},{"songId":""},{"value":true},7,{"songId":"s1","value":false,"enqueuedAt":2}]"#;
        assert_eq!(decode(text), vec![item("s1", false, 2.0, 0)]);
        assert!(decode("").is_empty());
        assert!(decode("{}").is_empty());
    }
}
