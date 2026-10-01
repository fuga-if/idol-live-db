//! LLM (MCP クライアント / 人の手) 向けの面。`web_export` と同じ立ち位置の driving adapter。
//!
//! ## 構成
//!
//! - **ツール面** ([`tools`] / [`proposal`] / [`lyrics_search`]): ツールのカタログ (名前・説明・
//!   入力の JSON Schema) と、応答の JSON の組み立て。何を返すか・何件で切るか・どう並べるかは
//!   ここで決まる (Web 出面の `web_export::emit` にあたる)。照合・曖昧解決・セトリの型のように
//!   他の面と共有する規則は domain の関数を呼び、ここに書き直さない。
//! - **入出力** ([`mcp`] / [`stdio`] / [`cli`] / [`proposal_io`] / [`lyrics_api`]): 入力
//!   (JSON-RPC の封 / argv) をほどいてツール面を呼び、返った値を書き出す (stdout / ファイル /
//!   HTTP) だけ。「どのレコードを返すか」「何件で切るか」をここで決めてはいけない。
//!
//! ## アプリに入るのはツール面だけ
//!
//! [`tools`] (読み取りツールとアプリ内アシスタント向けの面) は常にコンパイルし、
//! `inbound::assistant_tools` から FFI でアプリに出す。アプリ内の AI も MCP と同じ
//! 答えを返すようにするため (ツールを Swift / Kotlin に写経しない)。
//! 入出力のアダプタ・書き込み (ドラフト)・歌詞検索 (HTTP) は既定 off の feature = "agent"
//! でしかコンパイルされず、iOS/Android のバインディングには現れない。

#[cfg(feature = "agent")]
pub mod cli;
#[cfg(feature = "agent")]
pub mod lyrics_api;
#[cfg(feature = "agent")]
pub mod lyrics_search;
#[cfg(feature = "agent")]
pub mod mcp;
#[cfg(feature = "agent")]
pub mod proposal;
#[cfg(feature = "agent")]
pub mod proposal_io;
#[cfg(feature = "agent")]
pub mod stdio;
pub mod tools;

#[cfg(feature = "agent")]
use crate::domain::snapshot::Snapshot;
#[cfg(feature = "agent")]
use tools::{ToolError, ToolSpec};
#[cfg(feature = "agent")]
use serde_json::Value;
#[cfg(feature = "agent")]
use std::path::PathBuf;

/// 1 プロセスぶんの実行文脈。
#[cfg(feature = "agent")]
pub struct Ctx {
    /// 読む master.sqlite。
    pub db_path: PathBuf,
    /// リポジトリルート。ドラフトの書き出し先と `tools/apply_data.py` の基準。
    pub repo_root: PathBuf,
    /// JST の「今日」(`YYYY-MM-DD`) を固定したいときだけ `Some`。
    ///
    /// MCP サーバは 1 プロセスを何日も起動したままにされる (クライアントが繋ぎっぱなしに
    /// する)。ここに固定の文字列を持たせて起動時に決め打ちすると、JST 深夜を跨いだ後も
    /// 「今後のライブ」判定が古い日付のまま返り続ける。既定 (`None`) では
    /// [`Ctx::today_key`] が呼ぶたびに現在時刻から計算する。`--today` 指定時や
    /// テストで日付を固定したいときだけ `Some` にする。
    pub today_override: Option<String>,
    /// 書き込み (ドラフト作成) ツールを出すか。リモート公開時は false。
    pub allow_write: bool,
}

#[cfg(feature = "agent")]
impl Ctx {
    /// JST の「今日」。`today_override` があればそれを、無ければ現在時刻から求める。
    pub fn today_key(&self) -> String {
        self.today_override.clone().unwrap_or_else(|| {
            let now_epoch_seconds = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            crate::domain::jst_day::jst_today(now_epoch_seconds)
        })
    }
}

/// 出せるツールの一覧 (読み取り + 書き込み)。
#[cfg(feature = "agent")]
pub fn catalog(ctx: &Ctx) -> Vec<ToolSpec> {
    let mut all = tools::tool_catalog();
    // 歌詞検索はサーバを叩くので domain の call_tool には通らない (proposal と同じ扱い)。
    all.extend(lyrics_search::lyrics_catalog());
    if ctx.allow_write {
        all.extend(proposal::proposal_catalog());
    }
    all
}

/// ツール名で読み取り / 書き込みを振り分けて実行する。
#[cfg(feature = "agent")]
pub fn dispatch(ctx: &Ctx, snap: &Snapshot, name: &str, args: &Value) -> Result<Value, ToolError> {
    let is_write = proposal::is_proposal_tool(name);
    if is_write {
        if !ctx.allow_write {
            return Err(ToolError::UnknownTool(name.to_string()));
        }
        return proposal_io::run(ctx, name, args);
    }
    if lyrics_search::is_lyrics_tool(name) {
        return lyrics_api::run(snap, args);
    }
    tools::call_tool(snap, name, args, &ctx.today_key())
}
