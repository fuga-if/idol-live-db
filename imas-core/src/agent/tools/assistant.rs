//! アプリ内の会話 (利用者の ChatGPT プランの Responses API) のツール面。
//!
//! 利用者が打ったことに、モデルが読み取りツール ([`super::tool_catalog`]) で DB を引いて答え、
//! 頼まれた操作は**操作ツール** ([`crate::domain::ai_actions`]) の呼び出しに直す。
//!
//! ## 操作ツールは実行しない
//!
//! 操作ツールを呼ばれても、ここは検査して「予定に積んだ」と返すだけ。その番の往復が終わったら、
//! **その番に**積まれた操作の呼び出しをもう一度検査し直して一覧にする ([`resolve`])。
//! 実行は、利用者が返事の下の一覧を見て押してから各 OS がやる。
//!
//! ## 会話の続き
//!
//! この経路は `store: false` で、サーバは前の番を覚えていない。会話の続きは、前の番までの
//! input に返事と次の発言を積んだもの ([`follow_up`])。端末は input を持ち回るだけで、
//! 往復の途中の状態はどこにも持たない (1 往復 = 1 呼び出しのまま)。

use super::plan_loop::{self, parse_object, replayable, Request};
#[cfg(test)]
use super::plan_loop::NAMESPACE;
use super::{tool_catalog, tool_schema, ToolSpec};
use crate::domain::ai_actions::{self as actions, AiPlannedAction, PlanContext, MAX_ACTIONS};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 受ける頼みの長さ (文字数)。
pub const MIN_ORDER_CHARS: usize = 2;
pub const MAX_ORDER_CHARS: usize = 300;

/// 返事の上限 (文字数)。
const MAX_MESSAGE_CHARS: usize = 600;

/// 会話を続けられる長さ (input の項目数と、合わせた字数)。越えたら新しい会話にしてもらう。
/// 会話に残すのは発言と返事だけ (ツールの結果は番ごとに捨てる) なので、数十番は続く。
const MAX_HISTORY_ITEMS: usize = 80;
const MAX_HISTORY_CHARS: usize = 40_000;

/// 検証を通った一覧。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Plan {
    /// モデルの返事。
    pub message: String,
    /// この番で積まれた、これからやること。並びはモデルが呼んだ順。
    pub actions: Vec<AiPlannedAction>,
    /// 検査で落とした操作の件数 (DB に無い id など)。
    pub rejected: u32,
    /// ここまでの会話 (次の番の [`follow_up`] に渡す)。
    pub history: Vec<String>,
}

/// この頼みを受けてよいか。前後の空白は数えない。
pub fn accepts(order: &str) -> bool {
    let n = order.trim().chars().count();
    (MIN_ORDER_CHARS..=MAX_ORDER_CHARS).contains(&n)
}

/// 入力欄が空のときに出す例。
pub fn example_orders() -> Vec<&'static str> {
    vec![
        "次のミリオンのライブはいつ？",
        "「READY!!」がいちばん歌われたのはどのライブ？",
        "シャニマスのソロ曲で予習用のプレイリストを作って",
        "きのうの新幹線代 14,000 円を収支に入れて",
    ]
}

fn action_specs() -> Vec<ToolSpec> {
    actions::catalog()
        .into_iter()
        .map(|spec| ToolSpec {
            name: spec.name.to_string(),
            description: spec.description.to_string(),
            input_schema: tool_schema(spec.properties, spec.required),
        })
        .collect()
}

fn user_item(order: &str) -> String {
    json!({ "role": "user", "content": order.trim() }).to_string()
}

/// 会話の続きの input。`history` は前の番の [`Plan::history`]。
///
/// 発言が受けられない長さ・会話が長くなりすぎた、なら None (端末は新しい会話を促す)。
pub fn follow_up(history: &[String], order: &str) -> Option<Vec<String>> {
    let chars: usize = history.iter().map(|s| s.chars().count()).sum();
    if !accepts(order) || history.len() >= MAX_HISTORY_ITEMS || chars >= MAX_HISTORY_CHARS {
        return None;
    }
    let mut input = history.to_vec();
    input.push(user_item(order));
    Some(input)
}

/// 1 番ぶんのリクエスト。`history` は前の番までの会話 (最初は空)。
/// 発言が受けられない長さ・会話が長くなりすぎた、なら None。
pub fn request(history: &[String], order: &str, today_key: &str) -> Option<Request> {
    let input = follow_up(history, order)?;
    let mut specs = tool_catalog();
    specs.extend(action_specs());
    Some(Request {
        instructions: instructions(today_key),
        input,
        tools: plan_loop::responses_tools_of(specs, "アイドルマスターのライブ / 楽曲 DB を読み、利用者の記録への操作を予定に積む。"),
        text_format: text_format(),
    })
}

fn instructions(today_key: &str) -> String {
    format!(
        "\
あなたはアイドルマスターのライブ / 楽曲データベースアプリ「アイドルライブDB」の中の話し相手です。利用者の質問にデータベースを引いて答え、頼まれた操作を予定に積みます。今日は {today_key} (日本時間) です。

# 答え方
- 事実 (曲・アイドル・ライブ・セトリ・日付・回数) は、必ず読み取りツール (resolve / search / get_event など) で引いてから答える。記憶で答えない。引いても分からなければ、分からないと言う。
- message は話し言葉の短い日本語で。箇条書きや見出しの記号 (# * - など) は使わない。長くても 300 字。
- セトリの「予想」を訊かれたら、過去の実績 (setlist_shape など) を材料に自分で組み立て、根拠にした公演数や回数を添える。
- 歌詞の本文は扱わない。書かない・直さない・探さない。訊かれたら、曲の画面で見られると伝える。
- このアプリとアイドルマスターに関係のない話には、短く断る。

# 操作
- 利用者に何かを頼まれたら、操作ツール (set_attendance / create_playlist / add_expense / open など) を、やる順に呼ぶ。
- 操作ツールは**その場では実行されない**。予定に積まれ、利用者が返事の下の一覧を見て押してから実行される。「やりました」と言わず、「下の一覧で確かめて実行してください」のように伝える。
- id はツールの結果に出てきたものだけを使う。名前から id を組み立てない。
- 頼まれたことだけを積む。気を利かせて操作を足さない (参加を付けてと言われて、支出まで入れない)。
- どの公演・どの曲か決めきれないときは、当て推量で積まず、候補を挙げて訊き返す。
- 金額・座席・メモの文面は、利用者が言ったものだけを使う。DB の値や推測で埋めない。
- 用意されていない操作 (消す・公開する・歌詞やコールを書く・設定を変える) は積めない。人が中身を書くものは open でその画面を開くところまでにして、そう伝える。
- 前の番で積んだ操作を、頼まれていないのにもう一度積まない。"
    )
}

/// 答えの型 (Responses API の `text.format`)。
fn text_format() -> Value {
    json!({
        "type": "json_schema",
        "name": "assistant_result",
        "strict": true,
        "schema": {
            "type": "object",
            "properties": { "message": { "type": "string" } },
            "required": ["message"],
            "additionalProperties": false
        }
    })
}

/// 1 往復ぶんの結末。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    Finished(Plan),
    Continue(Vec<String>),
}

fn parse_args(arguments: &str) -> Result<Value, String> {
    if arguments.trim().is_empty() {
        return Ok(json!({}));
    }
    serde_json::from_str(arguments).map_err(|e| format!("引数が JSON として読めません: {e}"))
}

/// 操作ツールの呼び出し 1 件を検査して、モデルに返す文字列にする。
fn queue(snap: &Snapshot, name: &str, arguments: &str, ctx: PlanContext<'_>) -> String {
    match parse_args(arguments).and_then(|args| actions::plan(snap, name, &args, ctx)) {
        Ok(p) => json!({ "queued": true, "will": p.title, "target": p.target,
                         "note": "まだ実行していない。利用者が確かめてから実行される。" })
        .to_string(),
        Err(e) => json!({ "queued": false, "error": e }).to_string(),
    }
}

/// 返事を上限の字数で切る。改行は残す (段落のある返事を 1 行に潰さない)。
fn clip_reply(text: &str) -> String {
    let trimmed = text.trim();
    if trimmed.chars().count() <= MAX_MESSAGE_CHARS {
        return trimmed.to_string();
    }
    let mut cut: String = trimmed.chars().take(MAX_MESSAGE_CHARS - 1).collect();
    cut.push('…');
    cut
}

/// 1 往復の応答を受けて、次にどうするかを決める。
///
/// 関数呼び出しがあれば、読み取りは実行し、操作は検査だけして、結果を input の末尾に積む。
/// 無ければ、これまでの input から操作の一覧を組む。
pub fn step(snap: &Snapshot, input: &[String], output_items: &[String], text: &str, ctx: PlanContext<'_>) -> Step {
    let today_key = ctx.today_key;
    let items: Vec<Value> = output_items.iter().filter_map(|s| serde_json::from_str(s).ok()).collect();
    let calls: Vec<&Value> = items.iter().filter(|i| i["type"] == "function_call").collect();
    if calls.is_empty() {
        return Step::Finished(resolve(snap, input, text, ctx));
    }
    let mut next: Vec<String> = input.to_vec();
    next.extend(items.iter().filter_map(replayable).map(|v| v.to_string()));
    for item in calls {
        let Some(call_id) = item["call_id"].as_str() else { continue };
        let name = item["name"].as_str().unwrap_or("");
        let arguments = item["arguments"].as_str().unwrap_or("");
        let output = if actions::is_action(name) {
            queue(snap, name, arguments, ctx)
        } else {
            plan_loop::call(snap, name, arguments, today_key)
        };
        next.push(json!({ "type": "function_call_output", "call_id": call_id, "output": output }).to_string());
    }
    Step::Continue(next)
}

/// 番の往復が終わったあと、**この番で** (最後の利用者の発言より後に) 積まれた操作の呼び出しを
/// 検査し直して一覧にする。前の番の操作は、もう一度は出さない。
///
/// - 返事が型どおりに読めなければ、本文をそのまま返事にする。
/// - 検査に落ちたものは `rejected` に数える (モデルには往復の中で理由を返してある)。
/// - まったく同じ操作は最初の 1 回だけ。[`MAX_ACTIONS`] 件で切る。
pub fn resolve(snap: &Snapshot, input: &[String], text: &str, ctx: PlanContext<'_>) -> Plan {
    let message = parse_object(text)
        .and_then(|root| root.get("message").and_then(Value::as_str).map(str::to_string))
        .unwrap_or_else(|| text.to_string());
    let message = clip_reply(&message);
    let items: Vec<Value> = input.iter().filter_map(|s| serde_json::from_str::<Value>(s).ok()).collect();
    let turn_start = items.iter().rposition(|i| i["role"] == "user").map(|i| i + 1).unwrap_or(0);
    // 次の番に持ち越すのは発言と返事だけ。ツールの呼び出しと結果 (DB の JSON) は番ごとに捨てる
    // (毎番ぜんぶ送り直すと、数番でモデルの文脈を使い切る)。
    let mut history: Vec<String> = items
        .iter()
        .filter(|i| i["role"] == "user" || (i["role"] == "assistant" && i["content"].is_string()))
        .map(Value::to_string)
        .collect();
    history.push(json!({ "role": "assistant", "content": message }).to_string());
    let mut plan = Plan { message, history, ..Plan::default() };
    for item in &items[turn_start..] {
        let name = item["name"].as_str().unwrap_or("");
        if item["type"] != "function_call" || !actions::is_action(name) {
            continue;
        }
        let planned = parse_args(item["arguments"].as_str().unwrap_or("")).and_then(|args| actions::plan(snap, name, &args, ctx));
        match planned {
            Ok(p) if plan.actions.iter().any(|a| a.action == p.action) => {}
            Ok(p) if plan.actions.len() < MAX_ACTIONS => plan.actions.push(p),
            // 上限を越えたぶんは黙って切る (検査に落ちたわけではない)。
            Ok(_) => {}
            Err(_) => plan.rejected += 1,
        }
    }
    plan
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ai_actions::{AiAction, AiActionReach};
    use crate::test_support::bundle_snapshot;

    const TODAY: &str = "2026-11-16";
    const CTX: PlanContext<'static> = PlanContext { today_key: TODAY, playlists: &[] };

    fn call(id: &str, name: &str, args: Value) -> String {
        json!({ "type": "function_call", "id": "fc_x", "call_id": id, "name": name, "arguments": args.to_string() }).to_string()
    }

    #[test]
    fn 読み取りと操作のツールを両方渡す() {
        assert!(request(&[], " ", TODAY).is_none());
        let req = request(&[], "READY!! をお気に入りに入れて", TODAY).unwrap();
        let tools = &req.tools[0];
        assert_eq!(tools["name"], NAMESPACE);
        let names: Vec<&str> = tools["tools"].as_array().unwrap().iter().filter_map(|t| t["name"].as_str()).collect();
        assert!(names.contains(&"search") && names.contains(&"set_favorite_song") && names.contains(&"add_expense"));
        // 最上位は type: object だけ (この経路は $schema を受けない)。
        assert!(tools["tools"].as_array().unwrap().iter().all(|t| t["parameters"].get("$schema").is_none()));
        assert!(req.instructions.contains("その場では実行されない"));
    }

    #[test]
    fn 操作は実行せず積んで_返事と一緒に一覧にする() {
        let snap = bundle_snapshot();
        let song = snap.songs[0].id.clone();
        let req = request(&[], "この曲をお気に入りに入れて", TODAY).unwrap();

        let items = vec![
            call("c1", "set_favorite_song", json!({ "song_id": song })),
            call("c2", "set_favorite_song", json!({ "song_id": "no-such-song" })),
            call("c3", "search", json!({ "query": "READY" })),
        ];
        let Step::Continue(next) = step(snap, &req.input, &items, "", CTX) else { panic!("続くはず") };
        assert_eq!(next.len(), req.input.len() + 6);
        let outputs: Vec<Value> = next.iter().filter_map(|s| serde_json::from_str::<Value>(s).ok())
            .filter(|v| v["type"] == "function_call_output").collect();
        assert!(outputs[0]["output"].as_str().unwrap().contains("\"queued\":true"));
        assert!(outputs[1]["output"].as_str().unwrap().contains("\"queued\":false"));
        // 積み直した項目に id は残さない (store: false)。
        assert!(next.iter().all(|s| !s.contains("fc_x")));

        let Step::Finished(plan) = step(snap, &next, &[], r#"{"message":"下の一覧で確かめてください"}"#, CTX) else { panic!("終わるはず") };
        assert_eq!(plan.actions.len(), 1);
        assert_eq!(plan.rejected, 1);
        assert_eq!(plan.actions[0].action, AiAction::SetFavoriteSong { song_id: song, on: true });
        assert_eq!(plan.actions[0].reach, AiActionReach::Device);
        // 会話に残るのは発言と返事だけ (ツールの呼び出しと結果は持ち越さない)。
        assert_eq!(plan.history.len(), 2);
        assert!(plan.history[0].contains("user") && plan.history[1].contains("assistant"));
        assert!(plan.history.iter().all(|s| !s.contains("function_call")));
    }

    #[test]
    fn 次の番は前の番の操作をもう一度出さない() {
        let snap = bundle_snapshot();
        let idol = snap.idols[0].id.clone();
        let first = request(&[], "担当にして", TODAY).unwrap();
        let Step::Continue(next) = step(snap, &first.input, &[call("c1", "set_my_pick", json!({ "idol_id": idol }))], "", CTX) else {
            panic!("続くはず")
        };
        let Step::Finished(one) = step(snap, &next, &[], r#"{"message":"どうぞ"}"#, CTX) else { panic!("終わるはず") };
        assert_eq!(one.actions.len(), 1);

        let second = request(&one.history, "ありがとう", TODAY).unwrap();
        assert_eq!(second.input.len(), one.history.len() + 1);
        let Step::Finished(two) = step(snap, &second.input, &[], r#"{"message":"どういたしまして"}"#, CTX) else { panic!("終わるはず") };
        assert!(two.actions.is_empty());
        assert_eq!(two.message, "どういたしまして");
    }

    #[test]
    fn 同じ操作は一度だけ_型どおりでない返事は本文のまま() {
        let snap = bundle_snapshot();
        let idol = snap.idols[0].id.clone();
        let input = vec![
            user_item("担当にして"),
            call("c1", "set_my_pick", json!({ "idol_id": idol })),
            call("c2", "set_my_pick", json!({ "idol_id": idol })),
        ];
        let plan = resolve(snap, &input, "  積みました\n確かめてください ", CTX);
        assert_eq!(plan.actions.len(), 1);
        assert_eq!((plan.rejected, plan.message.as_str()), (0, "積みました\n確かめてください"));
    }

    #[test]
    fn 長くなりすぎた会話は続けない() {
        let long: Vec<String> = (0..MAX_HISTORY_ITEMS).map(|_| user_item("あ")).collect();
        assert!(follow_up(&long, "続き").is_none());
        assert!(follow_up(&[], "続き").is_some());
    }
}
