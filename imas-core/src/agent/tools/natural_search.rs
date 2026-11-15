//! 自然文検索 (アプリ内・利用者の ChatGPT プランの Responses API) のツール面。
//!
//! 「10th で歌われたソロ曲」のような文を、モデルが読み取りツール (MCP と同じ
//! [`super::tool_catalog`]) で引き、**当たったレコードの id の列**を返す。アプリはその id を
//! いつもの一覧の行で出す。文章の答えは出さない (会話の形にしない)。
//!
//! ## ここで決めること
//!
//! - モデルへの指示文・渡すツール・答えの型 ([`request`])
//! - 答えの検証 ([`resolve_answer`]): **DB に実在する id だけを通す**。モデルが名前から
//!   組み立てた id や、覚え違いの id は画面に出る前にここで落ちる。出るものは全部 DB の
//!   事実なので、モデルの間違いは「当たらない」で済み、「嘘が載る」にならない。
//! - 何往復まで許すか・何件で切るか・どの語なら受けるか・どのモデルを使うか
//!
//! アプリ (Swift / Kotlin) は HTTP を運び、JSON を受け渡すだけにする。

use super::{call_tool, tool_catalog};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};
use std::collections::HashSet;

/// Responses API の namespace 名 (関数呼び出しの項目にもこの名前が載る)。
pub const NAMESPACE: &str = "idol_live_db";

/// 1 回の検索で関数呼び出しを何往復まで許すか (無限ループ止め)。
pub const MAX_ROUNDS: u32 = 8;

/// 種別ごとに何件まで出すか。
pub const MAX_HITS_PER_KIND: usize = 50;

/// 受ける語の長さ (文字数)。短すぎる語はふつうの検索で足り、長すぎる文は入力ミス。
pub const MIN_QUERY_CHARS: usize = 2;
pub const MAX_QUERY_CHARS: usize = 200;

/// 「どう読み取ったか」の 1 行の上限 (文字数)。
const MAX_INTERPRETATION_CHARS: usize = 80;

/// 1 回の検索でモデルに渡すもの一式。
#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    /// Responses API の `instructions`。
    pub instructions: String,
    /// 最初の input (利用者の発言 1 件)。各項目は JSON の文字列。
    pub input: Vec<String>,
    /// Responses API の `tools`。
    pub tools: Value,
    /// Responses API の `text.format` (答えの型)。
    pub text_format: Value,
}

/// 検証を通った答え。id 列の並びはモデルが返した順。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Answer {
    /// モデルが語をどう読み取ったかの 1 行 (「ミリオン 10th ツアーで歌われたソロ曲」)。
    pub interpretation: String,
    pub song_ids: Vec<String>,
    pub idol_ids: Vec<String>,
    pub event_ids: Vec<String>,
    /// DB に無い id・知らない種別で落とした件数。
    pub dropped: u32,
    /// 答えが型どおりに読めなかった (アプリは「うまく探せませんでした」を出す)。
    pub unreadable: bool,
}

/// この語を自然文検索に出してよいか。前後の空白は数えない。
pub fn accepts(query: &str) -> bool {
    let n = query.trim().chars().count();
    (MIN_QUERY_CHARS..=MAX_QUERY_CHARS).contains(&n)
}

/// 入力欄が空のときに出す例。どれもツールで引けるもの。
pub fn example_queries() -> Vec<&'static str> {
    vec![
        "ミリオンの周年ライブで一番歌われている曲",
        "去年の合同ライブに出たシャニマスのアイドル",
        "「READY!!」が披露されたライブ",
        "今後のライブで東京の会場のもの",
    ]
}

/// 使うモデルを選ぶ。`available` は API が返した並びのまま (一覧に出してよいものだけ)。
///
/// 前に使えたもの (`saved`) がまだ一覧にあればそれ、無ければ一覧の先頭。
/// 一覧が空なら None (つないだアカウントで使えるモデルが無い)。
pub fn pick_model(available: &[String], saved: Option<&str>) -> Option<String> {
    if let Some(s) = saved {
        if available.iter().any(|m| m == s) {
            return Some(s.to_string());
        }
    }
    available.first().cloned()
}

/// 1 回の検索のリクエスト。語が受けられない長さなら None。
pub fn request(query: &str, today_key: &str) -> Option<Request> {
    if !accepts(query) {
        return None;
    }
    Some(Request {
        instructions: instructions(today_key),
        input: vec![json!({ "role": "user", "content": query.trim() }).to_string()],
        tools: responses_tools(),
        text_format: text_format(),
    })
}

fn instructions(today_key: &str) -> String {
    format!(
        "\
あなたはアイドルマスターのライブ / 楽曲データベースアプリ「アイドルライブDB」の検索機能です。
利用者が打った文に当てはまる曲・アイドル・ライブを、ツールで DB を引いて探します。今日は {today_key} (日本時間) です。

- 事実は必ずツールで引く。記憶で答えない。
- id は resolve か search などツールの結果に出てきたものだけを使う。名前から id を組み立てない。
- 略称・愛称・言い換え (「ミリシタ」「デレ」「10th」など) はあなたが読み解いて、ツールの引数に直す。
- 0 件だったら、語を分けたり軸を 1 つ外したりして引き直す。ツールが返す手がかりに従う。
- 答えは文章ではなく、当てはまったレコードの一覧で返す。
  - kind は song (曲) / idol (アイドル) / event (ライブ) / show (公演 = ライブの 1 日ぶん) のどれか。
  - 利用者が訊いているものの種別だけを返す。「〜で歌われた曲」なら曲だけ、「〜に出たアイドル」ならアイドルだけ。
  - 当てはまりの強い順、または訊かれた順 (「一番多い」なら多い順) に並べる。多くても 50 件まで。
  - 当てはまるものが無ければ hits は空にする。無理に埋めない。
- interpretation には、文をどう読み取ったかを 1 行 (40 字以内) で書く。挨拶や説明は書かない。
- 歌詞の本文は扱わない。データベースに関係のない頼みごとには hits を空にして返す。"
    )
}

/// Responses API の `tools` に渡す配列 (namespace 1 つにまとめる)。
///
/// ChatGPT プランの経路では、関数ツールを namespace にまとめないと受け付けない。
fn responses_tools() -> Value {
    let functions: Vec<Value> = tool_catalog()
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
        "description": "アイドルマスターのライブ / 楽曲 DB を読む。",
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

/// 答えの型 (Responses API の `text.format`)。
fn text_format() -> Value {
    json!({
        "type": "json_schema",
        "name": "search_hits",
        "strict": true,
        "schema": {
            "type": "object",
            "properties": {
                "interpretation": { "type": "string" },
                "hits": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "kind": { "type": "string", "enum": ["song", "idol", "event", "show"] },
                            "id": { "type": "string" }
                        },
                        "required": ["kind", "id"],
                        "additionalProperties": false
                    }
                }
            },
            "required": ["interpretation", "hits"],
            "additionalProperties": false
        }
    })
}

/// ツール実行中に画面へ出す一言。知らない名前は汎用の文言。
pub fn progress_label(name: &str) -> &'static str {
    match name {
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

/// 1 往復ぶんの結末。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    /// 答えが出た。
    Finished(Answer),
    /// 関数呼び出しがあった。これを次のリクエストの input にしてもう 1 往復する。
    Continue(Vec<String>),
}

/// 1 往復の応答を受けて、次にどうするかを決める。
///
/// - `input`: この往復で送った input。
/// - `output_items`: 応答で確定した出力項目 (JSON の文字列)。
/// - `text`: 応答の本文 (断片をつないだもの)。
///
/// 関数呼び出しが無ければ `text` を答えとして検証する。あれば全部実行し、モデルの
/// 出力項目と関数の結果を input の末尾に積んで返す (この経路は `store: false` で、
/// サーバが前の往復を覚えていないため)。
pub fn step(snap: &Snapshot, input: &[String], output_items: &[String], text: &str, today_key: &str) -> Step {
    let items: Vec<Value> = output_items.iter().filter_map(|s| serde_json::from_str(s).ok()).collect();
    let calls: Vec<&Value> = items.iter().filter(|i| i["type"] == "function_call").collect();
    if calls.is_empty() {
        return Step::Finished(resolve_answer(snap, text));
    }

    let mut next: Vec<String> = input.to_vec();
    next.extend(items.iter().filter_map(replayable).map(|v| v.to_string()));
    for item in calls {
        let Some(call_id) = item["call_id"].as_str() else { continue };
        let output = call(snap, item["name"].as_str().unwrap_or(""), item["arguments"].as_str().unwrap_or(""), today_key);
        next.push(json!({ "type": "function_call_output", "call_id": call_id, "output": output }).to_string());
    }
    Step::Continue(next)
}

/// 出力項目を次の input に積み直せる形にする。
///
/// `store: false` では項目が保存されないので、`id` を残すと「その id の項目は無い」で弾かれる。
/// 暗号化された中身の無い推論項目は積み直しても使えないので落とす。
fn replayable(item: &Value) -> Option<Value> {
    let mut item = item.clone();
    let object = item.as_object_mut()?;
    object.remove("id");
    if object.get("type").and_then(Value::as_str) == Some("reasoning") && !object.contains_key("encrypted_content") {
        return None;
    }
    Some(item)
}

/// モデルの答え (JSON 文字列) を検証して、画面に出してよい id 列にする。
///
/// - DB に無い id、知らない種別は落として `dropped` に数える。
/// - 公演 (show) は親のライブ (event) に畳む。アプリの行き先はライブ単位で、同じライブの
///   公演が 2 日ぶん当たっても 1 行にする。
/// - 同じレコードは最初の 1 回だけ。種別ごとに [`MAX_HITS_PER_KIND`] 件で切る。
pub fn resolve_answer(snap: &Snapshot, answer: &str) -> Answer {
    let Some(root) = parse_object(answer) else {
        return Answer { unreadable: true, ..Answer::default() };
    };
    let Some(hits) = root.get("hits").and_then(Value::as_array) else {
        return Answer { unreadable: true, ..Answer::default() };
    };

    let mut out = Answer {
        interpretation: clip(root.get("interpretation").and_then(Value::as_str).unwrap_or("")),
        ..Answer::default()
    };
    let mut seen: HashSet<(u8, String)> = HashSet::new();

    for hit in hits {
        let kind = hit.get("kind").and_then(Value::as_str).unwrap_or("");
        let id = hit.get("id").and_then(Value::as_str).unwrap_or("").trim();
        // (並びの番号, DB にある正しい id)。番号は重複判定の鍵にも使う。
        let found: Option<(u8, String)> = match kind {
            "song" => snap.song(id).map(|s| (0, s.id.clone())),
            "idol" => snap.idol(id).map(|i| (1, i.id.clone())),
            "event" => snap.event(id).map(|e| (2, e.id.clone())),
            "show" => snap.show(id).map(|s| (2, snap.events[s.event as usize].id.clone())),
            _ => None,
        };
        let Some(key) = found else {
            out.dropped += 1;
            continue;
        };
        if !seen.insert(key.clone()) {
            continue;
        }
        let list = match key.0 {
            0 => &mut out.song_ids,
            1 => &mut out.idol_ids,
            _ => &mut out.event_ids,
        };
        if list.len() < MAX_HITS_PER_KIND {
            list.push(key.1);
        }
    }
    out
}

/// 答えの文字列から JSON のオブジェクトを取り出す。
///
/// 型を指定しているので素の JSON が返るはずだが、前後に地の文やコードの囲みが付いても
/// 最初の `{` から最後の `}` までを読む。
fn parse_object(text: &str) -> Option<Value> {
    let start = text.find('{')?;
    let end = text.rfind('}')?;
    if end < start {
        return None;
    }
    serde_json::from_str::<Value>(&text[start..=end]).ok().filter(Value::is_object)
}

/// 1 行に収める: 改行を空白にし、上限の文字数で切る。
fn clip(text: &str) -> String {
    let one_line: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if one_line.chars().count() <= MAX_INTERPRETATION_CHARS {
        return one_line;
    }
    let mut cut: String = one_line.chars().take(MAX_INTERPRETATION_CHARS - 1).collect();
    cut.push('…');
    cut
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    const TODAY: &str = "2026-11-16";

    #[test]
    fn 受ける語は2字から200字で前後の空白は数えない() {
        assert!(!accepts(""));
        assert!(!accepts("  あ  "));
        assert!(accepts("あい"));
        assert!(accepts(&"あ".repeat(200)));
        assert!(!accepts(&"あ".repeat(201)));
        assert!(request("あ", TODAY).is_none());
    }

    #[test]
    fn リクエストは語を整えて今日の日付を指示文に入れる() {
        let req = request("  10thのソロ曲 ", TODAY).unwrap();
        let first: Value = serde_json::from_str(&req.input[0]).unwrap();
        assert_eq!(req.input.len(), 1);
        assert_eq!(first, json!({ "role": "user", "content": "10thのソロ曲" }));
        assert!(req.instructions.contains(TODAY));
    }

    #[test]
    fn ツールはnamespace1つにまとまり最上位にschemaとanyOfが無い() {
        let tools = responses_tools();
        assert_eq!(tools.as_array().unwrap().len(), 1);
        assert_eq!(tools[0]["type"], "namespace");
        let functions = tools[0]["tools"].as_array().unwrap();
        assert_eq!(functions.len(), tool_catalog().len());
        for f in functions {
            assert_eq!(f["type"], "function");
            assert_eq!(f["strict"], false, "{}", f["name"]);
            assert_eq!(f["parameters"]["type"], "object", "{}", f["name"]);
            assert!(f["parameters"].get("$schema").is_none(), "{}", f["name"]);
            assert!(f["parameters"].get("anyOf").is_none(), "{}", f["name"]);
        }
    }

    #[test]
    fn 答えの型はstrictで全キー必須かつ余分な鍵を許さない() {
        let f = text_format();
        assert_eq!(f["type"], "json_schema");
        assert_eq!(f["strict"], true);
        let schema = &f["schema"];
        assert_eq!(schema["additionalProperties"], false);
        assert_eq!(schema["required"], json!(["interpretation", "hits"]));
        let item = &schema["properties"]["hits"]["items"];
        assert_eq!(item["additionalProperties"], false);
        assert_eq!(item["required"], json!(["kind", "id"]));
    }

    #[test]
    fn すべてのツールに専用の進行表示がある() {
        for spec in tool_catalog() {
            assert_ne!(progress_label(&spec.name), "データを調べています…", "{} の表示が無い", spec.name);
        }
    }

    #[test]
    fn ツールの失敗は文字列のerrorで返る() {
        let snap = bundle_snapshot();
        let found: Value = serde_json::from_str(&call(snap, "search", r#"{"query":"READY"}"#, TODAY)).unwrap();
        assert!(found.get("error").is_none(), "{found}");
        let bad: Value = serde_json::from_str(&call(snap, "search", "{", TODAY)).unwrap();
        assert!(bad["error"].is_string());
        let unknown: Value = serde_json::from_str(&call(snap, "nope", "{}", TODAY)).unwrap();
        assert!(unknown["error"].is_string());
    }

    #[test]
    fn 関数呼び出しがあれば実行して出力項目と結果を積み無ければ答えにする() {
        let snap = bundle_snapshot();
        let input = vec![json!({ "role": "user", "content": "q" }).to_string()];
        let output = vec![
            // 中身の無い推論は積み直さない。
            json!({ "type": "reasoning", "id": "rs_1" }).to_string(),
            json!({ "type": "reasoning", "id": "rs_2", "encrypted_content": "xxx" }).to_string(),
            json!({ "type": "function_call", "id": "fc_1", "call_id": "call_1", "name": "search", "arguments": "{\"query\":\"READY\"}" }).to_string(),
            json!({ "type": "function_call", "id": "fc_2", "call_id": "call_2", "name": "nope", "arguments": "" }).to_string(),
            "{broken".to_string(),
        ];
        let Step::Continue(next) = step(snap, &input, &output, "", TODAY) else { panic!("続くはず") };
        let next: Vec<Value> = next.iter().map(|s| serde_json::from_str(s).unwrap()).collect();
        // input 1 + 推論 1 + 呼び出し 2 + 結果 2。
        assert_eq!(next.len(), 6);
        assert_eq!(next[0]["role"], "user");
        assert_eq!(next[1]["type"], "reasoning");
        assert!(next.iter().all(|v| v.get("id").is_none()), "id は落とす");
        assert_eq!(next[4]["type"], "function_call_output");
        assert_eq!(next[4]["call_id"], "call_1");
        let found: Value = serde_json::from_str(next[4]["output"].as_str().unwrap()).unwrap();
        assert!(found.get("error").is_none(), "{found}");
        // 知らないツールも結果 (エラーの文字列) を返す。返さないと次の往復が弾かれる。
        assert_eq!(next[5]["call_id"], "call_2");
        assert!(next[5]["output"].as_str().unwrap().contains("error"));

        let answer = json!({ "interpretation": "x", "hits": [{ "kind": "song", "id": snap.songs[0].id }] }).to_string();
        let message = vec![json!({ "type": "message", "id": "msg_1" }).to_string()];
        let Step::Finished(got) = step(snap, &input, &message, &answer, TODAY) else { panic!("終わるはず") };
        assert_eq!(got.song_ids.len(), 1);
    }

    #[test]
    fn 前に使えたモデルが一覧にあればそれで無ければ先頭() {
        let list = vec!["a".to_string(), "b".to_string()];
        assert_eq!(pick_model(&list, Some("b")), Some("b".into()));
        assert_eq!(pick_model(&list, Some("gone")), Some("a".into()));
        assert_eq!(pick_model(&list, None), Some("a".into()));
        assert_eq!(pick_model(&[], Some("a")), None);
    }

    #[test]
    fn dbに無いidと知らない種別は落として数える() {
        let snap = bundle_snapshot();
        let song = &snap.songs[0].id;
        let idol = &snap.idols[0].id;
        let answer = json!({
            "interpretation": "テスト",
            "hits": [
                { "kind": "song", "id": song },
                { "kind": "song", "id": "song_that_does_not_exist" },
                { "kind": "idol", "id": idol },
                { "kind": "unit", "id": "x" },
                // 種別を取り違えた id (曲の id をアイドルとして) も通さない。
                { "kind": "idol", "id": song },
            ]
        })
        .to_string();
        let got = resolve_answer(snap, &answer);
        assert!(!got.unreadable);
        assert_eq!(got.interpretation, "テスト");
        assert_eq!(got.song_ids, vec![song.clone()]);
        assert_eq!(got.idol_ids, vec![idol.clone()]);
        assert!(got.event_ids.is_empty());
        assert_eq!(got.dropped, 3);
    }

    #[test]
    fn 公演は親のライブに畳み同じライブは1行にする() {
        let snap = bundle_snapshot();
        // 公演を 2 つ以上持つライブを実データから採る。
        let (event_idx, shows) = snap
            .shows_by_event
            .iter()
            .enumerate()
            .find(|(_, s)| s.len() >= 2)
            .expect("複数公演のライブが 1 つはある");
        let event_id = snap.events[event_idx].id.clone();
        let hits: Vec<Value> = shows
            .iter()
            .map(|&i| json!({ "kind": "show", "id": snap.shows[i as usize].id }))
            .chain(std::iter::once(json!({ "kind": "event", "id": event_id })))
            .collect();
        let got = resolve_answer(snap, &json!({ "interpretation": "", "hits": hits }).to_string());
        assert_eq!(got.event_ids, vec![event_id]);
        assert_eq!(got.dropped, 0);
    }

    #[test]
    fn 並びは返された順で種別ごとに50件で切る() {
        let snap = bundle_snapshot();
        let ids: Vec<String> = snap.songs.iter().take(60).map(|s| s.id.clone()).collect();
        let mut hits: Vec<Value> = ids.iter().rev().map(|id| json!({ "kind": "song", "id": id })).collect();
        // 重複は数えない。
        hits.push(json!({ "kind": "song", "id": ids[59] }));
        let got = resolve_answer(snap, &json!({ "interpretation": "", "hits": hits }).to_string());
        assert_eq!(got.song_ids.len(), MAX_HITS_PER_KIND);
        assert_eq!(got.song_ids[0], ids[59]);
        assert_eq!(got.song_ids[1], ids[58]);
        assert_eq!(got.dropped, 0);
    }

    #[test]
    fn 読めない答えはunreadableで囲みつきのjsonは読める() {
        let snap = bundle_snapshot();
        assert!(resolve_answer(snap, "すみません、分かりませんでした").unreadable);
        assert!(resolve_answer(snap, "").unreadable);
        assert!(resolve_answer(snap, r#"{"interpretation":"x"}"#).unreadable);
        assert!(resolve_answer(snap, "[1,2]").unreadable);

        let fenced = format!(
            "```json\n{}\n```",
            json!({ "interpretation": "x", "hits": [{ "kind": "song", "id": snap.songs[0].id }] })
        );
        let got = resolve_answer(snap, &fenced);
        assert!(!got.unreadable);
        assert_eq!(got.song_ids.len(), 1);
    }

    #[test]
    fn 読み取りの1行は改行をつぶして80字で切る() {
        let snap = bundle_snapshot();
        let long = format!("あ\nい {}", "う".repeat(100));
        let got = resolve_answer(snap, &json!({ "interpretation": long, "hits": [] }).to_string());
        assert!(got.interpretation.starts_with("あ い "));
        assert_eq!(got.interpretation.chars().count(), 80);
        assert!(got.interpretation.ends_with('…'));
    }

    #[test]
    fn 歌詞の本文やurlを返すツールは渡していない() {
        // 渡すツールは MCP と同じ読み取りカタログ。歌詞を返さないことは
        // `agent::tools` のテストが全ツールを 1 巡して止めている。ここでは、歌詞検索
        // (HTTP を叩く・feature = "agent" の中) が紛れていないことだけ見る。
        let names: Vec<String> = tool_catalog().into_iter().map(|s| s.name).collect();
        assert!(!names.iter().any(|n| n.contains("lyric")), "{names:?}");
    }
}
