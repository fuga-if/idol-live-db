//! アプリ内アシスタント (ChatGPT プランの Responses API) のツール面の FFI。
//! 中身は agent::tools::assistant。アプリは JSON を受け渡すだけ。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::agent::tools::{assistant, persona, personal, timeline};

/// 公演 1 件の参加マーク (アプリのユーザー DB から射影して渡す)。
#[derive(Debug, Clone, uniffi::Record)]
pub struct AssistantAttendedShow {
    pub show_id: String,
    /// "live" (現地) / "stream" (配信) / "live_viewing" (ライブビューイング)。
    pub attendance: String,
}

/// キャラ同士のタイムラインを 1 回生成するリクエストの材料。
#[derive(Debug, Clone, uniffi::Record)]
pub struct AssistantTimelineRequest {
    pub instructions: String,
    /// input に入れる利用者発言 1 件ぶんの本文。
    pub input: String,
    /// Responses API の `text.format` (JSON)。
    pub text_format_json: String,
    pub cast_ids: Vec<String>,
}

/// タイムラインの投稿にリプライしたときの input 本文。
#[uniffi::export]
pub fn assistant_timeline_reply_input(post_author: String, post_text: String, user_text: String) -> String {
    timeline::reply_input(&post_author, &post_text, &user_text)
}

/// Responses API の `instructions` に渡す指示文。
#[uniffi::export]
pub fn assistant_instructions() -> String {
    assistant::instructions().to_string()
}

/// Responses API の `tools` に渡す配列 (JSON 文字列)。
#[uniffi::export]
pub fn assistant_tools_json() -> String {
    assistant::responses_tools().to_string()
}

/// ツール実行中に出す一言 (「セトリを調べています…」)。
#[uniffi::export]
pub fn assistant_tool_progress_label(name: String) -> String {
    assistant::progress_label(&name).to_string()
}

/// 会話が空のときに出す質問の例。
#[uniffi::export]
pub fn assistant_example_prompts() -> Vec<String> {
    assistant::example_prompts().into_iter().map(String::from).collect()
}

#[uniffi::export]
impl SnapshotStore {
    /// 関数呼び出しを 1 件実行し、`function_call_output` の `output` に載せる文字列を返す。
    /// ツール側の失敗は `{"error": ...}` の文字列で返る (モデルが読んで引き直す)。
    /// 「今日」(今後 / 過去の切り分け) は呼んだ時刻の JST で決める。
    pub fn assistant_call_tool(
        &self,
        name: String,
        arguments_json: String,
        attended: Vec<AssistantAttendedShow>,
    ) -> Result<String, SnapshotError> {
        let snap = self.current()?;
        let marks: Vec<personal::AttendedShow> = attended
            .into_iter()
            .map(|m| personal::AttendedShow { show_id: m.show_id, attendance: m.attendance })
            .collect();
        Ok(assistant::call(&snap, &marks, &name, &arguments_json, &today_jst()))
    }

    /// キャラとのトークの指示文。知らないアイドルなら None。
    /// `recent_replies` はそのキャラの直近の返信 (出てきた口癖を今回は避けさせる)。
    pub fn assistant_talk_instructions(
        &self,
        idol_id: String,
        recent_replies: Vec<String>,
    ) -> Result<Option<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(persona::talk_instructions(&snap, &idol_id, &today_jst(), &recent_replies).ok())
    }

    /// キャラ同士のタイムラインの生成リクエスト。`seed` は呼ぶたびに変える (顔ぶれが変わる)。
    pub fn assistant_timeline_request(
        &self,
        oshi_ids: Vec<String>,
        previous_posts: Vec<String>,
        seed: u64,
    ) -> Result<AssistantTimelineRequest, SnapshotError> {
        let snap = self.current()?;
        let req = timeline::request(&snap, &today_jst(), &oshi_ids, &previous_posts, seed);
        Ok(AssistantTimelineRequest {
            instructions: req.instructions,
            input: req.input,
            text_format_json: req.text_format.to_string(),
            cast_ids: req.cast_ids,
        })
    }

    /// タイムラインの投稿へのリプライに、そのキャラが返すときの指示文。知らないアイドルなら None。
    pub fn assistant_timeline_reply_instructions(
        &self,
        idol_id: String,
        recent_replies: Vec<String>,
    ) -> Result<Option<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(timeline::reply_instructions(&snap, &idol_id, &today_jst(), &recent_replies).ok())
    }
}

/// 呼んだ時刻の JST の日付 (今後 / 過去の切り分けと、指示文の「今日」)。
fn today_jst() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    crate::domain::jst_day::jst_today(now)
}
