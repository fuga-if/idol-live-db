//! 利用者の ChatGPT プラン (Responses API) で回す仕事の、往復の共通部分。
//!
//! 「文で探す」([`super::natural_search`]) も「予習 DJ」([`super::prep_dj`]) も、モデルが
//! 読み取りツール ([`super::tool_catalog`]) で DB を引き、最後に型つきの答えを返す。
//! ツールの渡し方・関数の実行・往復の積み直しはここ 1 か所。仕事ごとに違うのは
//! 指示文と答えの型と検証だけ。

use super::{call_tool, tool_catalog};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// Responses API の namespace 名 (関数呼び出しの項目にもこの名前が載る)。
pub const NAMESPACE: &str = "idol_live_db";

/// 1 回の仕事で関数呼び出しを何往復まで許すか (無限ループ止め)。
pub const MAX_ROUNDS: u32 = 8;

/// 往復の上限に達したときに出す文言。
pub const TOO_MANY_ROUNDS_MESSAGE: &str = "調べものが長くなりすぎたので止めました。もう一度試してください";

/// 1 回の仕事でモデルに渡すもの一式。
#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    /// Responses API の `instructions`。
    pub instructions: String,
    /// 最初の input (利用者の側の 1 件)。各項目は JSON の文字列。
    pub input: Vec<String>,
    /// Responses API の `tools`。
    pub tools: Value,
    /// Responses API の `text.format` (答えの型)。
    pub text_format: Value,
}

/// Responses API の `tools` に渡す配列 (namespace 1 つにまとめる)。
///
/// ChatGPT プランの経路では、関数ツールを namespace にまとめないと受け付けない。
pub(super) fn responses_tools() -> Value {
    responses_tools_of(tool_catalog(), "アイドルマスターのライブ / 楽曲 DB を読む。")
}

/// 渡すツールを選んで組む (読み取りに操作ツールを足す仕事用)。
pub(super) fn responses_tools_of(specs: Vec<super::ToolSpec>, description: &str) -> Value {
    let functions: Vec<Value> = specs
        .into_iter()
        .map(|spec| {
            json!({
                "type": "function",
                "name": spec.name,
                "description": spec.description,
                "parameters": responses_parameters(spec.input_schema),
                // Responses API の関数ツールは既定で strict (全キー required) として検証される。
                // MCP のスキーマは省略できる引数が前提なので、明示的に外す。
                "strict": false,
            })
        })
        .collect();
    json!([{
        "type": "namespace",
        "name": NAMESPACE,
        "description": description,
        "tools": functions,
    }])
}

/// Web 検索 (Responses API の組み込みツール)。実行は ChatGPT の側で、端末もコアも通信しない。
pub(super) fn web_search_tool() -> Value {
    json!({ "type": "web_search" })
}

/// `tools` から Web 検索を外したもの。この経路が Web 検索を受けなかったときのやり直しに使う。
pub fn without_web_search(tools: &Value) -> Value {
    Value::Array(tools.as_array().into_iter().flatten().filter(|t| t["type"] != "web_search").cloned().collect())
}

/// MCP 用のスキーマから、Responses API の関数パラメータが受けない鍵を外す。
///
/// - `$schema`: 関数パラメータは JSON Schema の部分集合で、方言の宣言は要らない。
/// - 最上位の `anyOf` (id か name のどちらか必須): 最上位は `type: object` だけにする。
///   どちらが要るかは説明文に書いてあり、欠けていればツールが引数エラーを返す。
fn responses_parameters(mut schema: Value) -> Value {
    if let Some(o) = schema.as_object_mut() {
        o.remove("$schema");
        o.remove("anyOf");
    }
    schema
}

/// ツール実行中に画面へ出す一言。知らない名前は汎用の文言。
pub fn progress_label(name: &str) -> &'static str {
    match name {
        "resolve" | "search" => "データベースを検索しています…",
        "list_posts" | "get_post" => "X のポストを読んでいます…",
        n if crate::domain::ai_actions::is_action(n) => "やることをまとめています…",
        "get_idol" | "get_idol_facts" | "list_idols" => "アイドルを調べています…",
        "get_song" | "list_songs" => "曲を調べています…",
        "idol_songs" | "songs_for_cast" => "持ち歌を調べています…",
        "get_event" | "list_events" | "list_shows" => "ライブを調べています…",
        "get_show" | "setlist_diff" | "setlist_shape" => "セトリを調べています…",
        "song_performances" | "song_position_profile" | "co_performed_songs" => "披露履歴を調べています…",
        "stats" => "集計しています…",
        "vocabulary" => "収録範囲を確認しています…",
        _ => "データを調べています…",
    }
}

/// 関数呼び出しを 1 件実行し、`function_call_output` に載せる文字列を返す。
///
/// 失敗も文字列 (`{"error": ...}`) で返す — モデルが読んで引き直せるように。
pub fn call(snap: &Snapshot, name: &str, arguments: &str, today_key: &str) -> String {
    let args: Value = if arguments.trim().is_empty() {
        json!({})
    } else {
        match serde_json::from_str(arguments) {
            Ok(v) => v,
            Err(e) => return json!({ "error": format!("引数が JSON として読めません: {e}") }).to_string(),
        }
    };
    match call_tool(snap, name, &args, today_key) {
        Ok(v) => v.to_string(),
        Err(e) => json!({ "error": e.to_string() }).to_string(),
    }
}

/// 1 往復の応答に関数呼び出しがあれば全部実行し、次のリクエストの input を返す。
/// 無ければ None (本文が答え)。
///
/// モデルの出力項目と関数の結果を input の末尾に積む (この経路は `store: false` で、
/// サーバが前の往復を覚えていないため)。
pub fn advance(snap: &Snapshot, input: &[String], output_items: &[String], today_key: &str) -> Option<Vec<String>> {
    let items: Vec<Value> = output_items.iter().filter_map(|s| serde_json::from_str(s).ok()).collect();
    let calls: Vec<&Value> = items.iter().filter(|i| i["type"] == "function_call").collect();
    if calls.is_empty() {
        return None;
    }
    let mut next: Vec<String> = input.to_vec();
    next.extend(items.iter().filter_map(replayable).map(|v| v.to_string()));
    for item in calls {
        let Some(call_id) = item["call_id"].as_str() else { continue };
        let output = call(snap, item["name"].as_str().unwrap_or(""), item["arguments"].as_str().unwrap_or(""), today_key);
        next.push(json!({ "type": "function_call_output", "call_id": call_id, "output": output }).to_string());
    }
    Some(next)
}

/// 出力項目を次の input に積み直せる形にする。
///
/// `store: false` では項目が保存されないので、`id` を残すと「その id の項目は無い」で弾かれる。
/// 暗号化された中身の無い推論項目は積み直しても使えないので落とす。
pub(super) fn replayable(item: &Value) -> Option<Value> {
    let mut item = item.clone();
    let object = item.as_object_mut()?;
    object.remove("id");
    if object.get("type").and_then(Value::as_str) == Some("reasoning") && !object.contains_key("encrypted_content") {
        return None;
    }
    Some(item)
}

/// 答えの文字列から JSON のオブジェクトを取り出す。
///
/// 型を指定しているので素の JSON が返るはずだが、前後に地の文やコードの囲みが付いても
/// 最初の `{` から最後の `}` までを読む。
pub(super) fn parse_object(text: &str) -> Option<Value> {
    let start = text.find('{')?;
    let end = text.rfind('}')?;
    if end < start {
        return None;
    }
    serde_json::from_str::<Value>(&text[start..=end]).ok().filter(Value::is_object)
}

/// 1 行に収める: 改行を空白にし、上限の文字数で切る。
pub(super) fn clip_chars(text: &str, max: usize) -> String {
    let one_line: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if one_line.chars().count() <= max {
        return one_line;
    }
    let mut cut: String = one_line.chars().take(max.saturating_sub(1)).collect();
    cut.push('…');
    cut
}
