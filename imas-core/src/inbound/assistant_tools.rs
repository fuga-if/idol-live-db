//! アプリ内アシスタント (ChatGPT プランの Responses API) のツール面の FFI。
//! 中身は agent::tools::assistant。アプリは JSON を受け渡すだけ。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::agent::tools::{assistant, personal};

/// 公演 1 件の参加マーク (アプリのユーザー DB から射影して渡す)。
#[derive(Debug, Clone, uniffi::Record)]
pub struct AssistantAttendedShow {
    pub show_id: String,
    /// "live" (現地) / "stream" (配信)。
    pub attendance: String,
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
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let today = crate::domain::jst_day::jst_today(now);
        Ok(assistant::call(&snap, &marks, &name, &arguments_json, &today))
    }
}
