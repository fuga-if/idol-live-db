//! アプリ内アシスタント (ChatGPT プランの Responses API) に渡すツール面。
//!
//! MCP サーバと同じ読み取りツールに、利用者本人の記録を読むツール ([`super::personal`]) を
//! 足したもの。ツールの中身も文言もここ (コア) で決め、アプリは JSON を受け渡すだけにする
//! (iOS / Android で同じ答えになるように)。

use super::personal::{self, AttendedShow};
use super::{call_tool, tool_catalog, ToolSpec};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// Responses API の namespace 名 (関数呼び出しの項目にもこの名前が載る)。
pub const NAMESPACE: &str = "idol_live_db";

/// 指示文 (Responses API の `instructions`)。
pub fn instructions() -> &'static str {
    "\
あなたはアイドルマスターのライブ / 楽曲データベースアプリ「アイドルライブDB」の中のアシスタントです。

- 曲・アイドル・ライブ・公演・セトリの事実は、必ずツールで DB を引いてから答える。記憶で答えない。
- id は resolve か search で得てから使う。名前から id を推測して組み立てない。
- 利用者本人の参戦歴は my_attended_shows で引ける。セトリは get_show。
- 歌詞本文は扱わない。
- セトリ予想を訊かれたら、DB にあるのは過去の実績だけなので、それを材料に予想を組み立て、
  根拠にした公演数・回数を添える。
- 答えは日本語で、短く。曲名・ライブ名は DB の表記のまま書く。"
}

/// ツール実行中に画面へ出す一言 (「セトリを調べています…」)。知らない名前は汎用の文言。
pub fn progress_label(name: &str) -> &'static str {
    match name {
        "my_attended_shows" => "参戦履歴を見ています…",
        "resolve" | "search" => "データベースを検索しています…",
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

/// 会話が空のときに出す質問の例。どれもツールで答えられるもの。
pub fn example_prompts() -> Vec<&'static str> {
    vec![
        "私が参戦した公演を新しい順に教えて",
        "「READY!!」が最後に披露されたライブは？",
        "シャニマスの直近のライブのセトリを見せて",
        "ミリオンで一番披露回数が多い曲は？",
    ]
}

/// アシスタントに出すツールの一覧。
pub fn catalog() -> Vec<ToolSpec> {
    let mut all = personal::catalog();
    all.extend(tool_catalog());
    all
}

/// Responses API の `tools` に渡す配列 (namespace 1 つにまとめる)。
///
/// ChatGPT プランの経路では、関数ツールを namespace にまとめないと受け付けない。
pub fn responses_tools() -> Value {
    let functions: Vec<Value> = catalog()
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
        "description": "アイドルマスターのライブ / 楽曲 DB と、利用者本人の参戦記録を読む。",
        "tools": functions,
    }])
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

/// 関数呼び出しを 1 件実行し、`function_call_output` に載せる文字列を返す。
///
/// 失敗も文字列 (`{"error": ...}`) で返す — モデルが読んで引き直せるように。
pub fn call(snap: &Snapshot, attended: &[AttendedShow], name: &str, arguments: &str, today_key: &str) -> String {
    let args: Value = if arguments.trim().is_empty() {
        json!({})
    } else {
        match serde_json::from_str(arguments) {
            Ok(v) => v,
            Err(e) => return json!({ "error": format!("引数が JSON として読めません: {e}") }).to_string(),
        }
    };
    let result = if name == personal::MY_ATTENDED_SHOWS {
        personal::call(snap, attended, &args)
    } else {
        call_tool(snap, name, &args, today_key)
    };
    match result {
        Ok(v) => v.to_string(),
        Err(e) => json!({ "error": e.to_string() }).to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn ツールはnamespace1つにまとまり最上位にschemaとanyOfが無い() {
        let tools = responses_tools();
        assert_eq!(tools.as_array().unwrap().len(), 1);
        assert_eq!(tools[0]["type"], "namespace");
        let functions = tools[0]["tools"].as_array().unwrap();
        assert_eq!(functions.len(), catalog().len());
        for f in functions {
            assert_eq!(f["type"], "function");
            assert_eq!(f["strict"], false, "{}", f["name"]);
            assert_eq!(f["parameters"]["type"], "object", "{}", f["name"]);
            assert!(f["parameters"].get("$schema").is_none(), "{}", f["name"]);
            assert!(f["parameters"].get("anyOf").is_none(), "{}", f["name"]);
        }
        let names: Vec<&str> = functions.iter().filter_map(|f| f["name"].as_str()).collect();
        for expected in ["my_attended_shows", "search", "get_show", "get_song"] {
            assert!(names.contains(&expected), "{expected} が無い");
        }
    }

    #[test]
    fn すべてのツールに専用の進行表示がある() {
        for spec in catalog() {
            assert_ne!(progress_label(&spec.name), "データを調べています…", "{} の表示が無い", spec.name);
        }
    }

    #[test]
    fn 検索と参戦歴とエラーを文字列で返す() {
        let snap = bundle_snapshot();
        let show = &snap.shows[0];
        let marks = vec![AttendedShow { show_id: show.id.clone(), attendance: "live".into() }];

        let found: Value = serde_json::from_str(&call(&snap, &marks, "search", r#"{"query":"READY"}"#, "2026-10-01")).unwrap();
        assert!(found.get("error").is_none(), "{found}");

        let mine: Value = serde_json::from_str(&call(&snap, &marks, "my_attended_shows", "", "2026-10-01")).unwrap();
        assert_eq!(mine["total"], 1);

        let bad: Value = serde_json::from_str(&call(&snap, &marks, "search", "{", "2026-10-01")).unwrap();
        assert!(bad["error"].is_string());
        let unknown: Value = serde_json::from_str(&call(&snap, &marks, "nope", "{}", "2026-10-01")).unwrap();
        assert!(unknown["error"].is_string());
    }
}
