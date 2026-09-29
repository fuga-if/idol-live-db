//! 歌詞検索サーバ (`GET /lyrics/search`) を叩く。**HTTP を話すのはここだけ。**
//!
//! # なぜ手元で探さないか
//!
//! 歌詞本文は D1 にしか無い。JASRAC の許諾は「一括ダウンロードさせない配信形式」に
//! 対して下りている (`JASRAC.md`) ので、本文をこちら側に持ってこない。
//! `lyrics_local/` に取り込み途中の写しはあるが、あれは投入用の作業場で、
//! **新曲が入っていないことがある**ぶん本番より古い。出面 (iOS / Web) が見ているのと
//! 同じサーバを見るのが、答えが 1 つになる唯一のやり方。
//!
//! サーバは song_id と断片しか返さない (曲名も歌手も返さない) ので、曲の情報は
//! こちらの `master.sqlite` から添える。これは出面と同じ役回り。
//!
//! # なぜ curl か
//!
//! HTTP クライアントの crate を足すと、既定 off の feature のために Cargo.lock が
//! 膨らむ。`proposal_io` が `tools/apply_data.py` を子プロセスで起こしているのと
//! 同じ流儀にそろえた。`--data-urlencode` があるので語の組み立ても自分で書かずに済む。

use crate::agent::tools::{args, ToolError};
use crate::agent::lyrics_search::{self, ApiHit, LyricsFilter, Scope, MAX_SONGS};
use crate::domain::snapshot::Snapshot;
use serde_json::Value;
use std::process::{Command, Stdio};

/// 既定の API ベース。iOS (`APIEndpoints.baseURL`) と同じところを見る。
pub const DEFAULT_BASE_URL: &str = "https://imas-live-api.tokata3011.workers.dev";
/// 環境変数でベースを差し替える (ローカルの wrangler dev に向けたいとき)。
pub const BASE_URL_ENV: &str = "IMAS_LYRICS_API";
/// 応答を待つ上限 (秒)。MCP クライアントを長く待たせない。
const TIMEOUT_SECS: u32 = 20;

fn base_url() -> String {
    std::env::var(BASE_URL_ENV).unwrap_or_else(|_| DEFAULT_BASE_URL.to_string())
}

/// `search_lyrics` を実行する。
pub fn run(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    let query = args::str_opt(arguments, "query")
        .ok_or_else(|| ToolError::BadArgs("query が要る".into()))?;
    let limit = args::limit(arguments, 20, MAX_SONGS as u32)? as usize;
    let filter = build_filter(snap, arguments)?;

    let body = fetch(&base_url(), &query)?;
    let parsed: Value = serde_json::from_str(&body)
        .map_err(|e| ToolError::Failed(format!("歌詞検索サーバの応答が JSON でない: {e}")))?;

    // サーバ側の 4xx は message を持って返る。黙って 0 件にしない
    // (「その語は歌詞に無い」と読まれてしまう)。
    if let Some(msg) = parsed.get("error").and_then(|v| v.as_str()) {
        return Err(ToolError::BadArgs(format!("歌詞検索サーバ: {msg}")));
    }

    let hits: Vec<ApiHit> = parsed
        .get("hits")
        .and_then(|v| v.as_array())
        .map(|rows| rows.iter().filter_map(api_hit).collect())
        .unwrap_or_default();

    Ok(lyrics_search::response(snap, &query, &hits, &filter, hits.len(), limit))
}

/// 引数 → 絞り込み条件。id はここで添字に解決する (domain に id 解決を持たせない)。
///
/// 母集団の軸は 3 つのうち 1 つだけ。同時に渡されたら突き返す — 黙って片方を採ると
/// 「絞ったつもりの数」を答えることになる (`scope.rs` の軸の扱いと同じ)。
fn build_filter(snap: &Snapshot, arguments: &Value) -> Result<LyricsFilter, ToolError> {
    let show = args::str_opt(arguments, "show_id");
    let event = args::str_opt(arguments, "event_id");
    let idol = args::str_opt(arguments, "idol_id");
    if [show.is_some(), event.is_some(), idol.is_some()].iter().filter(|x| **x).count() > 1 {
        return Err(ToolError::BadArgs(
            "show_id / event_id / idol_id は同時に使えない (母集団はどれか 1 つ)".into(),
        ));
    }

    let scope = if let Some(id) = show {
        Some(Scope::Show(
            snap.show_index_by_id
                .get(&id)
                .copied()
                .ok_or_else(|| ToolError::NotFound(format!("公演 {id} が無い")))?,
        ))
    } else if let Some(id) = event {
        Some(Scope::Event(
            snap.event_index_by_id
                .get(&id)
                .copied()
                .ok_or_else(|| ToolError::NotFound(format!("ライブ {id} が無い")))?,
        ))
    } else if let Some(id) = idol {
        Some(Scope::Idol(
            snap.idol_index_by_id
                .get(&id)
                .copied()
                .ok_or_else(|| ToolError::NotFound(format!("アイドル {id} が無い")))?,
        ))
    } else {
        None
    };

    Ok(LyricsFilter {
        brand: args::str_opt(arguments, "brand"),
        song_type: args::str_opt(arguments, "song_type"),
        scope,
        min_performances: args::u32_opt(arguments, "min_performances")?,
        max_performances: args::u32_opt(arguments, "max_performances")?,
    })
}

/// サーバの 1 行を [`ApiHit`] にほどく。鍵の綴りはサーバ側 (camelCase) に合わせる。
fn api_hit(row: &Value) -> Option<ApiHit> {
    let song_id = row.get("songId")?.as_str()?.to_string();
    let snippets = row
        .get("snippets")
        .and_then(|v| v.as_array())
        .map(|xs| {
            xs.iter()
                .filter_map(|x| x.get("snippet").and_then(|s| s.as_str()).map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    Some(ApiHit { song_id, snippets })
}

/// curl で 1 回叩いて本文を返す。
fn fetch(base: &str, query: &str) -> Result<String, ToolError> {
    let out = Command::new("curl")
        .arg("-sS")
        .arg("--max-time")
        .arg(TIMEOUT_SECS.to_string())
        .arg("-G")
        .arg(format!("{}/lyrics/search", base.trim_end_matches('/')))
        .arg("--data-urlencode")
        .arg(format!("q={query}"))
        // stdout を継承させない。継承すると curl の書き出しが JSON-RPC の流れに混ざる
        // (proposal_io で実際にやらかした)。
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| ToolError::Failed(format!("curl を起動できない: {e}")))?;

    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(ToolError::Failed(format!(
            "歌詞検索サーバに届かない ({}): {}",
            out.status,
            err.trim()
        )));
    }
    String::from_utf8(out.stdout)
        .map_err(|e| ToolError::Failed(format!("応答が UTF-8 でない: {e}")))
}
