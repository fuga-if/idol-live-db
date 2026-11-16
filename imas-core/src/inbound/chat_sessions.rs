//! チャットの会話の保存の FFI 口。形と規則は `domain::chat_sessions`。ファイルを置く・消すのは各 OS。

use crate::domain::chat_sessions::{self as d, ChatSession, ChatSessionSummary};

/// 一覧に出す並びと、消してよい会話。
#[derive(Debug, Clone, uniffi::Record)]
pub struct ChatSessionShelf {
    /// 新しい順。
    pub sessions: Vec<ChatSessionSummary>,
    /// 上限を越えた古い会話の id (各 OS がファイルを消す)。
    pub overflow_ids: Vec<String>,
}

/// 会話の題 (最初の発言から)。
#[uniffi::export]
pub fn chat_session_title(first_order: String) -> String {
    d::title_for(&first_order)
}

/// ファイルに書く文字列。
#[uniffi::export]
pub fn chat_session_encode(session: ChatSession) -> String {
    d::encode(&session)
}

/// ファイルの中身を読む。読めなければ None。
#[uniffi::export]
pub fn chat_session_decode(text: String) -> Option<ChatSession> {
    d::decode(&text)
}

/// 読めた会話を一覧に並べる (1 画面 = 1 呼び出し)。
#[uniffi::export]
pub fn chat_session_shelf(sessions: Vec<ChatSession>) -> ChatSessionShelf {
    let (sessions, overflow_ids) = d::arrange(&sessions);
    ChatSessionShelf { sessions, overflow_ids }
}
