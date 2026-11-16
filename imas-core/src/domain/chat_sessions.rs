//! チャットの会話の保存 (端末の中だけ)。
//!
//! 会話は端末のファイルに 1 本ずつ置く (サーバには送らない・アカウントにも結ばない)。
//! ここは**保存の形**と、題の付け方・何本まで残すか・一覧の並びを持つ。iOS と Android で
//! 形が食い違うと、バックアップや機種変更で読めなくなるので、読み書きの口は両方ここを通す。
//! ファイルを置く・消すのは各 OS。
//!
//! # 残すもの・残さないもの
//!
//! - 残す: 発言・返事・一覧に出した操作の題と「実行したか」・次の番に渡す会話 (`history`)。
//! - 残さない: 添えた画像 (枚数だけ)、ツールが返した DB の中身、実行できる形の操作。
//!   読み直した会話の操作は見るだけで、もう一度やるなら頼み直す (DB もプレイリストも
//!   その後に変わっているかもしれないので、古い検査結果で実行させない)。

use serde::{Deserialize, Serialize};

/// 残す会話の上限。越えたぶんは古い順に消す。
pub const MAX_SESSIONS: usize = 50;
/// 題の上限 (文字数)。
const MAX_TITLE_CHARS: usize = 28;
/// 保存の形の版。読めない版のファイルは捨てずに無視する (新しいアプリが書いたものかもしれない)。
const FORMAT_VERSION: u32 = 1;

/// 一覧に出した操作 1 件の記録。
#[derive(uniffi::Record, Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ChatSavedAction {
    pub title: String,
    pub target: String,
    /// 実行して成功したか。
    pub done: bool,
}

/// 1 番ぶん (発言と返事)。
#[derive(uniffi::Record, Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ChatSavedTurn {
    pub order: String,
    /// 添えた画像の枚数 (画像そのものは残さない)。
    pub image_count: u32,
    pub reply: String,
    pub actions: Vec<ChatSavedAction>,
}

/// 会話 1 本。
#[derive(uniffi::Record, Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ChatSession {
    pub id: String,
    pub title: String,
    /// 最後に動いた時刻 (エポック秒)。
    pub updated_at: i64,
    /// 次の番に渡す会話 (`AssistantPlan::history`)。
    pub history: Vec<String>,
    pub turns: Vec<ChatSavedTurn>,
}

/// 一覧の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ChatSessionSummary {
    pub id: String,
    pub title: String,
    pub updated_at: i64,
    pub turn_count: u32,
}

#[derive(Serialize, Deserialize)]
struct Stored {
    version: u32,
    session: ChatSession,
}

/// 会話の題。最初の発言の頭を使う。字が無ければ (画像だけ) そう分かる題にする。
pub fn title_for(first_order: &str) -> String {
    let one_line: String = first_order.split_whitespace().collect::<Vec<_>>().join(" ");
    if one_line.is_empty() {
        return "画像の相談".to_string();
    }
    if one_line.chars().count() <= MAX_TITLE_CHARS {
        return one_line;
    }
    let mut cut: String = one_line.chars().take(MAX_TITLE_CHARS - 1).collect();
    cut.push('…');
    cut
}

/// ファイルに書く文字列。
pub fn encode(session: &ChatSession) -> String {
    serde_json::to_string(&Stored { version: FORMAT_VERSION, session: session.clone() }).unwrap_or_default()
}

/// ファイルの中身を読む。壊れている・知らない版・1 番も無い、なら None。
pub fn decode(text: &str) -> Option<ChatSession> {
    let stored: Stored = serde_json::from_str(text).ok()?;
    (stored.version == FORMAT_VERSION && !stored.session.id.is_empty() && !stored.session.turns.is_empty())
        .then_some(stored.session)
}

/// 一覧に出す並び (新しい順) と、消してよい会話の id (上限を越えた古いもの)。
pub fn arrange(sessions: &[ChatSession]) -> (Vec<ChatSessionSummary>, Vec<String>) {
    let mut all: Vec<ChatSessionSummary> = sessions
        .iter()
        .map(|s| ChatSessionSummary { id: s.id.clone(), title: s.title.clone(), updated_at: s.updated_at, turn_count: s.turns.len() as u32 })
        .collect();
    all.sort_by(|a, b| b.updated_at.cmp(&a.updated_at).then_with(|| a.id.cmp(&b.id)));
    let overflow = all.split_off(all.len().min(MAX_SESSIONS)).into_iter().map(|s| s.id).collect();
    (all, overflow)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session(id: &str, updated_at: i64) -> ChatSession {
        ChatSession {
            id: id.into(),
            title: title_for("次のライブはいつ？"),
            updated_at,
            history: vec![r#"{"role":"user","content":"次のライブはいつ？"}"#.into()],
            turns: vec![ChatSavedTurn {
                order: "次のライブはいつ？".into(),
                image_count: 0,
                reply: "来月です".into(),
                actions: vec![ChatSavedAction { title: "カレンダーに足す".into(), target: "DAY1".into(), done: true }],
            }],
        }
    }

    #[test]
    fn 書いたものがそのまま読める() {
        let s = session("a", 100);
        assert_eq!(decode(&encode(&s)), Some(s));
        assert!(decode("{}").is_none() && decode("こわれた").is_none());
        // 知らない版は読まない (捨てもしない: 消すのは各 OS が利用者に言われたときだけ)。
        assert!(decode(&encode(&session("a", 1)).replace("\"version\":1", "\"version\":99")).is_none());
        let mut empty = session("a", 1);
        empty.turns.clear();
        assert!(decode(&encode(&empty)).is_none());
    }

    #[test]
    fn 題は最初の発言の頭() {
        assert_eq!(title_for("  次のライブは\nいつ？ "), "次のライブは いつ？");
        assert_eq!(title_for(""), "画像の相談");
        let long = title_for(&"あ".repeat(80));
        assert_eq!(long.chars().count(), MAX_TITLE_CHARS);
        assert!(long.ends_with('…'));
    }

    #[test]
    fn 一覧は新しい順で_上限を越えた古いものは消す側へ() {
        let sessions: Vec<ChatSession> = (0..MAX_SESSIONS as i64 + 2).map(|i| session(&format!("s{i}"), i)).collect();
        let (list, overflow) = arrange(&sessions);
        assert_eq!(list.len(), MAX_SESSIONS);
        assert_eq!(list[0].id, format!("s{}", MAX_SESSIONS + 1));
        assert_eq!(list[0].turn_count, 1);
        assert_eq!(overflow, vec!["s1".to_string(), "s0".to_string()]);
    }
}
