//! CLI 面。MCP と同じツールを人の手から叩けるようにする (デバッグと単体確認用)。
//!
//! ```text
//! imas-mcp <tool> --json '{"query":"春日未来"}'
//! imas-mcp <tool> --query 春日未来 --limit 5
//! imas-mcp tools            # 一覧 (名前と説明)
//! imas-mcp tools --json     # ToolSpec を JSON で
//! ```
//!
//! `--key value` の組み立ては `super::dispatch` の手前で JSON オブジェクトに変換する
//! だけ。値の型推定・欠損チェックは全部 `tools::args` 側の役目で、ここは
//! 「文字列がどう見えるか」しか判断しない (数値に見えれば数値、`true`/`false` なら
//! 真偽値、それ以外は文字列)。

use super::Ctx;
use crate::agent::tools::ToolError;
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Map, Value};

/// `imas-mcp <tool> [--json '{...}'] [--key value ...]` を 1 回実行して stdout に書く。
pub fn run(ctx: &Ctx, snap: &Snapshot, argv: &[String]) -> Result<(), ToolError> {
    let Some(sub) = argv.first() else {
        return Err(ToolError::BadArgs(
            "サブコマンドが要ります (tools か、ツール名)".to_string(),
        ));
    };
    let rest = &argv[1..];

    if sub == "tools" {
        print_tools(ctx, rest.iter().any(|a| a == "--json"));
        return Ok(());
    }

    let args = parse_tool_args(rest)?;
    let result = super::dispatch(ctx, snap, sub, &args)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&result).map_err(|e| ToolError::Failed(e.to_string()))?
    );
    Ok(())
}

fn print_tools(ctx: &Ctx, as_json: bool) {
    let specs = super::catalog(ctx);
    if as_json {
        let list: Vec<Value> = specs
            .iter()
            .map(|s| {
                json!({
                    "name": s.name,
                    "description": s.description,
                    "input_schema": s.input_schema,
                })
            })
            .collect();
        match serde_json::to_string_pretty(&json!(list)) {
            Ok(text) => println!("{text}"),
            Err(e) => eprintln!("imas-mcp: tools --json の整形に失敗: {e}"),
        }
        return;
    }
    for spec in &specs {
        println!("{}\t{}", spec.name, spec.description);
    }
}

/// `--key value ...` (または `--json '{...}'`) を 1 個の JSON オブジェクトに組む。
///
/// `--json` が来たらそれだけを使う (`--key` との併用は想定しない = 混在時は `--json` 優先)。
/// 同じキーが複数回来たら配列にまとめる (`--brands cg --brands ml` → `{"brands":["cg","ml"]}`)。
fn parse_tool_args(rest: &[String]) -> Result<Value, ToolError> {
    if let Some(pos) = rest.iter().position(|a| a == "--json") {
        let raw = rest
            .get(pos + 1)
            .ok_or_else(|| ToolError::BadArgs("--json に値がありません".to_string()))?;
        return serde_json::from_str(raw)
            .map_err(|e| ToolError::BadArgs(format!("--json の中身が JSON として読めません: {e}")));
    }

    let mut map = Map::new();
    let mut it = rest.iter();
    while let Some(flag) = it.next() {
        let Some(key) = flag.strip_prefix("--") else {
            return Err(ToolError::BadArgs(format!(
                "引数は --key value の形式です: {flag}"
            )));
        };
        let raw = it
            .next()
            .ok_or_else(|| ToolError::BadArgs(format!("--{key} に値がありません")))?;
        let value = infer_value(raw);
        match map.get_mut(key) {
            None => {
                map.insert(key.to_string(), value);
            }
            Some(Value::Array(existing)) => existing.push(value),
            Some(existing) => {
                let prev = existing.clone();
                *existing = Value::Array(vec![prev, value]);
            }
        }
    }
    Ok(Value::Object(map))
}

/// `--key value` の `value` を JSON の型に見立てる。曖昧なものは文字列のまま通す。
fn infer_value(raw: &str) -> Value {
    if let Ok(n) = raw.parse::<i64>() {
        return json!(n);
    }
    if let Ok(f) = raw.parse::<f64>() {
        return json!(f);
    }
    match raw {
        "true" => json!(true),
        "false" => json!(false),
        _ => json!(raw),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx() -> Ctx {
        Ctx {
            db_path: "master.sqlite".into(),
            repo_root: ".".into(),
            today_override: Some("2026-09-19".to_string()),
            allow_write: true,
        }
    }

    #[test]
    fn key_valueは型を推定する() {
        let argv = vec![
            "--query".to_string(),
            "春日未来".to_string(),
            "--limit".to_string(),
            "5".to_string(),
            "--exact".to_string(),
            "true".to_string(),
        ];
        let args = parse_tool_args(&argv).unwrap();
        assert_eq!(args["query"], "春日未来");
        assert_eq!(args["limit"], 5);
        assert_eq!(args["exact"], true);
    }

    #[test]
    fn 同じキーが複数回なら配列にまとめる() {
        let argv = vec![
            "--brands".to_string(),
            "cg".to_string(),
            "--brands".to_string(),
            "ml".to_string(),
        ];
        let args = parse_tool_args(&argv).unwrap();
        assert_eq!(args["brands"], json!(["cg", "ml"]));
    }

    #[test]
    fn jsonが来たらそれだけを使う() {
        let argv = vec!["--json".to_string(), r#"{"query":"眠り姫","limit":3}"#.to_string()];
        let args = parse_tool_args(&argv).unwrap();
        assert_eq!(args["query"], "眠り姫");
        assert_eq!(args["limit"], 3);
    }

    #[test]
    fn 値が無いとbadargs() {
        let argv = vec!["--query".to_string()];
        assert!(parse_tool_args(&argv).is_err());
    }

    #[test]
    fn サブコマンド無しはbadargs() {
        let err = run(&ctx(), &Snapshot::default(), &[]).unwrap_err();
        assert!(matches!(err, ToolError::BadArgs(_)));
    }

    #[test]
    fn tools_サブコマンドは常に成功する() {
        assert!(run(&ctx(), &Snapshot::default(), &["tools".to_string()]).is_ok());
        assert!(run(
            &ctx(),
            &Snapshot::default(),
            &["tools".to_string(), "--json".to_string()]
        )
        .is_ok());
    }

    #[test]
    fn 未知ツール名はエラーが伝播する() {
        // 実在しそうな名前と衝突しないよう、わざと有り得ない綴りにする。
        let err = run(
            &ctx(),
            &Snapshot::default(),
            &["__no_such_tool__".to_string(), "--query".to_string(), "x".to_string()],
        )
        .unwrap_err();
        assert!(matches!(err, ToolError::UnknownTool(_)));
    }
}
