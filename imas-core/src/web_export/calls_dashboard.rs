//! Worker の `GET /calls/dashboard` の写し (`db/calls_dashboard.json`) を読む。
//!
//! 写しを作るのは `tools/export_calls_dashboard.py` (公開エンドポイントを 1 回 GET して
//! 保存するだけ)。出面のビルドは D1 にも Worker にも触らない。
//! 形は Worker の応答そのもの (`imas-live-api/src/routes/calls.ts`)。知らない鍵は無視する。

use serde::Deserialize;
use std::path::Path;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Dashboard {
    /// 秒 epoch (UTC)。
    pub generated_at: i64,
    pub songs_with_calls: Vec<SongStat>,
    pub recent_edits: Vec<Edit>,
    pub tagged_without_calls: Vec<String>,
    pub call_tag: Option<CallTag>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SongStat {
    pub song_id: String,
    pub call_lines: u32,
    pub call_count: u32,
    pub updated_at: Option<i64>,
    pub updated_by: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Edit {
    pub song_id: String,
    pub at: Option<i64>,
    pub by: String,
    pub call_lines_before: u32,
    pub call_lines_after: u32,
    pub call_count_before: u32,
    pub call_count_after: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CallTag {
    pub tag_name: String,
    pub tagged: u32,
    pub with_calls: u32,
    pub without_lyrics: u32,
}

/// 写しが無ければ `None` (ページごと出さない。お題と同じ扱い)。
pub fn load(path: &str) -> Result<Option<Dashboard>, String> {
    if !Path::new(path).exists() {
        return Ok(None);
    }
    let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    serde_json::from_str(&text)
        .map(Some)
        .map_err(|e| format!("{path}: コールガイドの写しが読めない: {e}"))
}
