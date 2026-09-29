//! MCP (Model Context Protocol) の JSON-RPC 2.0 面。
//!
//! 扱うのは `initialize` / `tools/list` / `tools/call` / `ping` と、通知
//! (`notifications/initialized`) だけ。トランスポート (stdio / HTTP) は呼び手が持つ。
//!
//! ## 応答の形について
//!
//! - JSON-RPC の「形が壊れている」(`jsonrpc` が `"2.0"` でない・`method` が無い・
//!   `id` が明示的に `null`) は `-32600` (Invalid Request)。MCP は `id: null` を
//!   禁じている (「id 無し」= 通知とは別物) ので、区別して弾く。呼び手が通知のつもり
//!   だったかは形が壊れていると判別できないので、仕様どおり `id: null` で必ず応答する。
//! - 通知 (id 無し) は **`ping` 以外、実行そのものをしない**。`tools/call` を id 無しで
//!   投げられたときにドラフト作成のような副作用まで実行してしまうと、結果を捨てるだけで
//!   呼び手には何も返らない事故になる。`ping` は副作用が無いので実行してよい。
//! - `tools/call` が `ToolError` を返したときは **JSON-RPC のエラーにしない**。
//!   LLM が見るのは `content` の文言で、そこに日本語の失敗理由を積んで
//!   `isError: true` を立てる (LLM が自分で引数を直して再試行できるようにするため)。
//!   例外は `UnknownTool` — ツール名を LLM が捏造した場合で、これは MCP の作法どおり
//!   `-32602` (Invalid params) にする。
//! - `protocolVersion` はクライアントが要求した版がこちらの対応集合にあればそのまま
//!   返す (MCP 仕様の MUST)。無ければこちらの最新版を返す。

use super::Ctx;
use crate::agent::tools::{server_instructions, ToolError};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// このサーバが話せる `protocolVersion`。新しい版に対応したら先頭 (最新) に足す。
const SUPPORTED_PROTOCOL_VERSIONS: &[&str] = &["2025-06-18", "2025-03-26", "2024-11-05"];

/// リクエスト 1 件を処理して応答を返す。通知 (id 無し) には `None`。
pub fn handle(ctx: &Ctx, snap: &Snapshot, request: &Value) -> Option<Value> {
    let has_id = request.get("id").is_some();
    let id = request.get("id").cloned().unwrap_or(Value::Null);

    let jsonrpc_ok = request.get("jsonrpc").and_then(Value::as_str) == Some("2.0");
    let method = request.get("method").and_then(Value::as_str);

    let Some(method) = jsonrpc_ok.then_some(()).and(method) else {
        // 形が壊れているリクエストは通知として扱えない (id の有無すら疑わしい) ので、
        // 仕様どおり id: null で必ず応答する。
        return Some(error_response(Value::Null, -32600, "Invalid Request".to_string()));
    };

    // MCP は id: null を禁じる (「id 無し」= 通知とは別物)。id フィールド自体が無いのと
    // 明示的な null を取り違えないよう、has_id と id.is_null() を両方見る。
    if has_id && id.is_null() {
        return Some(error_response(
            Value::Null,
            -32600,
            "Invalid Request: id は null にできません".to_string(),
        ));
    }

    // `notifications/initialized` はメソッドとして常に通知なので、クライアントが
    // 誤って id を付けてきても無視する (何もせず無応答)。
    if method == "notifications/initialized" {
        return None;
    }

    // 通知 (id 無し) は ping 以外実行しない。tools/call のような副作用を持ちうる
    // メソッドを「実行だけして結果を捨てる」のは事故のもと (ドラフトが書かれるのに
    // 呼び手には何も返らない)。
    if !has_id && method != "ping" {
        return None;
    }

    let params = request.get("params").cloned().unwrap_or_else(|| json!({}));

    let result: Result<Value, (i64, String)> = match method {
        "initialize" => Ok(initialize_result(&params)),
        "tools/list" => Ok(tools_list_result(ctx)),
        "tools/call" => tools_call_result(ctx, snap, &params),
        "ping" => Ok(json!({})),
        _ => Err((-32601, "Method not found".to_string())),
    };

    if !has_id {
        // ping はここまで来るが通知なので応答しない。
        return None;
    }

    Some(match result {
        Ok(value) => success_response(id, value),
        Err((code, message)) => error_response(id, code, message),
    })
}

/// `initialize` の `protocolVersion` はクライアントの要求に合わせる (MCP 仕様の MUST)。
/// 対応していない版を要求されたら、こちらの最新版を返して交渉に委ねる。
fn initialize_result(params: &Value) -> Value {
    let requested = params.get("protocolVersion").and_then(Value::as_str);
    let protocol_version = requested
        .filter(|v| SUPPORTED_PROTOCOL_VERSIONS.contains(v))
        .unwrap_or(SUPPORTED_PROTOCOL_VERSIONS[0]);
    json!({
        "protocolVersion": protocol_version,
        "capabilities": { "tools": {} },
        "serverInfo": {
            "name": "imas-live-db",
            "version": env!("CARGO_PKG_VERSION"),
        },
        "instructions": server_instructions(),
    })
}

/// `ToolSpec` を MCP の `tools/list` の形に写す。
///
/// `input_schema` は `ToolSpec` (`tools::tool_schema` 経由) の時点で
/// すでに `serde_json::Value`。以前はここが JSON 文字列を持っていて、パースに失敗した
/// ツールを一覧から落として stderr に書く縮退が要った (`lookup` が文字列テンプレートで
/// スキーマを組んでいて、説明文に `"` が 1 つ入るだけで不正な JSON を作れたため)。
/// domain 側が最初から妥当な `Value` しか作れない形になった今、この縮退は起こりようが
/// ないので、ここでは鍵の名前を `inputSchema` に変えて写すだけにする。
fn tools_list_result(ctx: &Ctx) -> Value {
    let tools: Vec<Value> = super::catalog(ctx)
        .into_iter()
        .map(|spec| {
            json!({
                "name": spec.name,
                "description": spec.description,
                "inputSchema": spec.input_schema,
            })
        })
        .collect();
    json!({ "tools": tools })
}

fn tools_call_result(ctx: &Ctx, snap: &Snapshot, params: &Value) -> Result<Value, (i64, String)> {
    let Some(name) = params.get("name").and_then(Value::as_str) else {
        return Err((-32602, "Invalid params: name が必要です".to_string()));
    };
    let arguments = params.get("arguments").cloned().unwrap_or_else(|| json!({}));

    match super::dispatch(ctx, snap, name, &arguments) {
        Ok(value) => {
            // 整形しない。読むのは LLM で、インデントと改行は素の JSON より
            // 3〜4 割トークンを増やすだけ。人が目で見る CLI 側 (cli.rs) は整形する。
            let text = serde_json::to_string(&value)
                .unwrap_or_else(|e| format!("(結果の整形に失敗: {e})"));
            Ok(json!({
                "content": [{ "type": "text", "text": text }],
                "isError": false,
            }))
        }
        Err(ToolError::UnknownTool(n)) => Err((-32602, format!("知らないツール: {n}"))),
        Err(e) => Ok(json!({
            "content": [{ "type": "text", "text": e.to_string() }],
            "isError": true,
        })),
    }
}

fn success_response(id: Value, result: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

fn error_response(id: Value, code: i64, message: String) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 実在しそうな名前と衝突しないよう、わざと有り得ない綴りにする。
    const NO_SUCH_TOOL: &str = "__no_such_tool__";

    fn ctx() -> Ctx {
        Ctx {
            db_path: "master.sqlite".into(),
            repo_root: ".".into(),
            today_override: Some("2026-09-19".to_string()),
            allow_write: true,
        }
    }

    #[test]
    fn initialize_はクライアントが対応版なら同じ版で応答する() {
        let req = json!({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": { "protocolVersion": "2024-11-05" },
        });
        let resp = handle(&ctx(), &Snapshot::default(), &req).unwrap();
        assert_eq!(resp["result"]["protocolVersion"], "2024-11-05");
        assert_eq!(resp["result"]["serverInfo"]["name"], "imas-live-db");
        assert!(resp["result"]["instructions"].as_str().is_some_and(|s| !s.is_empty()));
        assert_eq!(resp["id"], 1);
    }

    #[test]
    fn notifications_initialized_は無応答() {
        let req = json!({ "jsonrpc": "2.0", "method": "notifications/initialized" });
        assert!(handle(&ctx(), &Snapshot::default(), &req).is_none());
    }

    #[test]
    fn id無しは通知として無応答_未知メソッドでも() {
        let req = json!({ "jsonrpc": "2.0", "method": "そんざいしない" });
        assert!(handle(&ctx(), &Snapshot::default(), &req).is_none());
    }

    #[test]
    fn id無しのtools_call_は実行すらせず無応答() {
        // 副作用 (ドラフト書き出し) を持ちうるメソッドを通知として投げても、
        // 実行されず (結果を捨てるのでもなく) 無視されることを確認する。
        let req = json!({
            "jsonrpc": "2.0", "method": "tools/call",
            "params": { "name": NO_SUCH_TOOL, "arguments": {} },
        });
        assert!(handle(&ctx(), &Snapshot::default(), &req).is_none());
    }

    #[test]
    fn id無しのpingは実行して良いが応答はしない() {
        let req = json!({ "jsonrpc": "2.0", "method": "ping" });
        assert!(handle(&ctx(), &Snapshot::default(), &req).is_none());
    }

    #[test]
    fn idがnullは無応答ではなくinvalid_request() {
        // JSON-RPC/MCP は id: null を禁じる。id 無し (通知) と混同しない。
        let req = json!({ "jsonrpc": "2.0", "id": null, "method": "ping" });
        let resp = handle(&ctx(), &Snapshot::default(), &req).unwrap();
        assert_eq!(resp["error"]["code"], -32600);
    }

    /// カタログの中身 (何件あるか・どんなツールか) は `agent::tools` 側の責務。
    /// ここで確かめるのは「`ToolSpec` → MCP の `tools/list` への写し方」だけなので、
    /// 件数を決め打ちしない (他の担当がツールを増減させても壊れないように)。
    #[test]
    fn tools_list_はカタログの各ツールをinput_schemaオブジェクト付きで写す() {
        let ctx = ctx();
        let expected = super::super::catalog(&ctx).len();
        let req = json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" });
        let resp = handle(&ctx, &Snapshot::default(), &req).unwrap();
        let tools = resp["result"]["tools"].as_array().unwrap();
        // カタログの input_schema は全部 JSON として妥当なはずなので、写す過程で
        // 1 件も落ちない (パース失敗による握り潰しが起きない) ことも兼ねて確認する。
        assert_eq!(tools.len(), expected);
        for tool in tools {
            assert!(tool["name"].is_string());
            assert!(tool["description"].is_string());
            assert!(
                tool["inputSchema"].is_object(),
                "inputSchema は文字列のままでなくオブジェクトに写っているべき: {tool}"
            );
        }
    }

    #[test]
    fn tools_call_の未知ツールはjsonrpcエラー_32602() {
        let req = json!({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": { "name": NO_SUCH_TOOL, "arguments": { "query": "眠り姫" } },
        });
        let resp = handle(&ctx(), &Snapshot::default(), &req).unwrap();
        assert_eq!(resp["error"]["code"], -32602);
        assert!(resp.get("result").is_none());
    }

    #[test]
    fn tools_call_name無しもinvalid_params() {
        let req = json!({
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": {},
        });
        let resp = handle(&ctx(), &Snapshot::default(), &req).unwrap();
        assert_eq!(resp["error"]["code"], -32602);
    }

    #[test]
    fn 未知メソッドは_32601() {
        let req = json!({ "jsonrpc": "2.0", "id": 6, "method": "resources/list" });
        let resp = handle(&ctx(), &Snapshot::default(), &req).unwrap();
        assert_eq!(resp["error"]["code"], -32601);
    }

    #[test]
    fn jsonrpcが違う版だとinvalid_request_id_nullで応答() {
        let req = json!({ "jsonrpc": "1.0", "id": 7, "method": "ping" });
        let resp = handle(&ctx(), &Snapshot::default(), &req).unwrap();
        assert_eq!(resp["error"]["code"], -32600);
        assert_eq!(resp["id"], Value::Null);
    }
}
