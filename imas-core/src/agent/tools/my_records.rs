//! 利用者がこの端末に付けている記録を読むツール。
//!
//! 「私が行ったライブは？」「今年いくら使った？」に答えるのと、操作を積む前に「もう付いているか」を
//! モデルが確かめるのに使う。記録は端末が射影して渡したもの ([`AiUserRecords`]) で、コアは保存しない。
//! モデルが呼んだときだけ、その分が ChatGPT に渡る。

use super::{tool_schema, ToolSpec};
use crate::domain::ai_actions::AiUserRecords;
use crate::domain::ledger;
use crate::domain::show_naming::show_title;
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 1 回に返す件数の上限 (新しいものから)。
const MAX_ROWS: usize = 60;

pub const NAME: &str = "my_records";

pub fn spec() -> ToolSpec {
    ToolSpec {
        name: NAME.into(),
        description: "利用者がこのアプリに付けている記録を読む。参加した公演・お気に入りの曲・担当のアイドル・持っている円盤・収支。「私の」「自分の」と訊かれたときと、記録を付ける前にもう付いていないか確かめるときに。".into(),
        input_schema: tool_schema(
            json!({ "kind": { "type": "string", "enum": ["attendance", "favorites", "my_picks", "owned_releases", "expenses"],
                               "description": "attendance = 参加した公演、favorites = お気に入りの曲、my_picks = 担当、owned_releases = 持っている円盤、expenses = 収支。" } }),
            &["kind"],
        ),
    }
}

pub fn call(snap: &Snapshot, records: &AiUserRecords, args: &Value) -> String {
    let kind = args.get("kind").and_then(Value::as_str).unwrap_or("");
    let (total, rows): (usize, Vec<Value>) = match kind {
        "attendance" => {
            // 新しい公演から。DB に無くなった公演は名前を出せないので飛ばす。
            let mut rows: Vec<(String, Value)> = records
                .attendance
                .iter()
                .filter_map(|a| {
                    let show = snap.show(&a.show_id)?;
                    Some((show.date.clone(), json!({ "show_id": show.id, "date": show.date, "name": show_title(snap, &show.id), "types": a.types })))
                })
                .collect();
            rows.sort_by(|a, b| b.0.cmp(&a.0));
            (rows.len(), rows.into_iter().map(|r| r.1).collect())
        }
        "favorites" => {
            let rows: Vec<Value> = records.favorite_song_ids.iter().filter_map(|id| snap.song(id)).map(|s| json!({ "song_id": s.id, "title": s.title })).collect();
            (rows.len(), rows)
        }
        "my_picks" => {
            let rows: Vec<Value> = records.my_pick_idol_ids.iter().filter_map(|id| snap.idol(id)).map(|i| json!({ "idol_id": i.id, "name": i.name })).collect();
            (rows.len(), rows)
        }
        "owned_releases" => {
            let rows: Vec<Value> = records
                .owned_release_ids
                .iter()
                .filter_map(|id| snap.event_releases.iter().find(|r| &r.id == id))
                .map(|r| json!({ "release_id": r.id, "title": r.title }))
                .collect();
            (rows.len(), rows)
        }
        "expenses" => {
            let mut all: Vec<&crate::domain::ai_actions::AiExpenseRef> = records.expenses.iter().collect();
            all.sort_by(|a, b| b.date.cmp(&a.date));
            let sum: i64 = all.iter().map(|e| e.amount).sum();
            let rows: Vec<Value> = all
                .iter()
                .map(|e| {
                    json!({
                        "date": e.date,
                        "category": ledger::expense_category_label(e.category),
                        "amount": e.amount,
                        "show_id": e.show_id,
                        "show": e.show_id.as_deref().and_then(|id| show_title(snap, id)),
                        "note": e.note,
                    })
                })
                .collect();
            let shown: Vec<Value> = rows.into_iter().take(MAX_ROWS).collect();
            return json!({ "total_count": all.len(), "total_amount": sum, "rows": shown,
                           "note": "total_amount は全件の合計 (円)。rows は新しい順で、多ければ途中まで。" })
            .to_string();
        }
        other => return json!({ "error": format!("kind が語彙にありません: {other}") }).to_string(),
    };
    let shown: Vec<Value> = rows.into_iter().take(MAX_ROWS).collect();
    json!({ "total_count": total, "rows": shown }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ai_actions::{AiAttendanceRef, AiExpenseRef};
    use crate::domain::ledger::ExpenseCategory;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn 記録を名前つきで返す() {
        let snap = bundle_snapshot();
        let show = snap.shows[0].id.clone();
        let records = AiUserRecords {
            attendance: vec![
                AiAttendanceRef { show_id: show.clone(), types: vec!["live".into()] },
                AiAttendanceRef { show_id: "消えた公演".into(), types: vec!["live".into()] },
            ],
            favorite_song_ids: vec![snap.songs[0].id.clone()],
            expenses: vec![
                AiExpenseRef { date: "2026-01-01".into(), category: ExpenseCategory::Goods, amount: 3000, show_id: None, note: None },
                AiExpenseRef { date: "2026-11-15".into(), category: ExpenseCategory::Ticket, amount: 9800, show_id: Some(show.clone()), note: None },
            ],
            ..AiUserRecords::default()
        };
        let attendance: Value = serde_json::from_str(&call(snap, &records, &json!({ "kind": "attendance" }))).unwrap();
        assert_eq!(attendance["total_count"], 1);
        assert_eq!(attendance["rows"][0]["show_id"], show);
        let favorites: Value = serde_json::from_str(&call(snap, &records, &json!({ "kind": "favorites" }))).unwrap();
        assert_eq!(favorites["rows"][0]["title"], snap.songs[0].title);
        let expenses: Value = serde_json::from_str(&call(snap, &records, &json!({ "kind": "expenses" }))).unwrap();
        assert_eq!(expenses["total_amount"], 12800);
        assert_eq!(expenses["rows"][0]["date"], "2026-11-15");
        assert!(expenses["rows"][0]["show"].is_string());
        assert!(call(snap, &records, &json!({ "kind": "all" })).contains("error"));
    }
}
