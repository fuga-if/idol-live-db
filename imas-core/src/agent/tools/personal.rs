//! 利用者本人の記録を読むツール。アプリ内のアシスタントだけが出す (MCP には出さない)。
//!
//! 記録 (参加マーク) は端末のユーザー DB にあり、スナップショット (マスタ) には無い。
//! 呼び手 (アプリ) が射影して渡し、ここでマスタの名前を引いて LLM が読める形にする。

use super::browse::show_header;
use super::json::Obj;
use super::{args, ToolError, ToolSpec};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 公演 1 件の参加マーク。`attendance` は語彙の参加種別 ("live" 現地 / "stream" 配信 /
/// "live_viewing" ライブビューイング)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttendedShow {
    pub show_id: String,
    pub attendance: String,
}

pub const MY_ATTENDED_SHOWS: &str = "my_attended_shows";

pub fn catalog() -> Vec<ToolSpec> {
    vec![ToolSpec {
        name: MY_ATTENDED_SHOWS.to_string(),
        description: "このアプリの利用者本人が「参加した」と記録した公演の一覧 (現地 / 配信 / ライブビューイング)。\
             日付の新しい順。利用者の参戦歴・参加回数・初参加などを訊かれたらこれを引く。\
             セトリが要るときは返った show_id で get_show を呼ぶ。"
            .to_string(),
        input_schema: super::tool_schema(
            json!({
                "attendance": {
                    "type": "string",
                    "enum": ["live", "stream", "live_viewing"],
                    "description": "live=現地 / stream=配信 / live_viewing=ライブビューイング で絞る。省略するとすべて",
                },
                "brand": { "type": "string", "description": "ブランド id で絞る (vocabulary の brands)" },
                "limit": { "type": "integer", "description": "既定 50・上限 300" },
            }),
            &[],
        ),
    }]
}

pub fn call(snap: &Snapshot, attended: &[AttendedShow], arguments: &Value) -> Result<Value, ToolError> {
    let limit = args::limit(arguments, 50, 300)?;
    let attendance = args::str_opt(arguments, "attendance");
    let brand = args::str_opt(arguments, "brand");

    // マスタから消えた公演 (記録だけ残っている) は数に入れない。
    let mut rows: Vec<(u32, &AttendedShow)> = attended
        .iter()
        .filter_map(|mark| snap.show_index_by_id.get(&mark.show_id).map(|&i| (i, mark)))
        .filter(|(i, mark)| {
            let event = &snap.events[snap.shows[*i as usize].event as usize];
            attendance.as_deref().is_none_or(|a| a == mark.attendance)
                && brand.as_deref().is_none_or(|b| event.brand_id.as_deref() == Some(b))
        })
        .collect();
    rows.sort_by(|a, b| {
        let (sa, sb) = (&snap.shows[a.0 as usize], &snap.shows[b.0 as usize]);
        sb.date.cmp(&sa.date).then_with(|| sa.id.cmp(&sb.id))
    });

    let mut by_attendance = std::collections::BTreeMap::<&str, usize>::new();
    for (_, mark) in &rows {
        *by_attendance.entry(mark.attendance.as_str()).or_default() += 1;
    }
    let mut o = Obj::new();
    o.put("total", rows.len());
    o.put("by_attendance", json!(by_attendance));
    o.put(
        "shows",
        Value::Array(
            rows.iter()
                .take(limit as usize)
                .map(|(i, mark)| {
                    let mut row = show_header(snap, *i);
                    let event = &snap.events[snap.shows[*i as usize].event as usize];
                    row["brand"] = json!(event.brand_id);
                    row["attendance"] = json!(mark.attendance);
                    row
                })
                .collect(),
        ),
    );
    if rows.is_empty() {
        o.put("note", "参加の記録がありません (アプリで公演に「参加」を付けると出ます)");
    }
    Ok(o.value())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    #[test]
    fn 参加した公演を新しい順に返し種別ごとに数える() {
        let snap = bundle_snapshot();
        let mut shows: Vec<&crate::domain::snapshot::Show> = snap.shows.iter().collect();
        shows.sort_by(|a, b| a.date.cmp(&b.date));
        let (old, new) = (shows[0], shows[shows.len() - 1]);
        let marks = vec![
            AttendedShow { show_id: old.id.clone(), attendance: "live".into() },
            AttendedShow { show_id: new.id.clone(), attendance: "stream".into() },
            AttendedShow { show_id: "no-such-show".into(), attendance: "live".into() },
        ];

        let all = call(&snap, &marks, &json!({})).unwrap();
        assert_eq!(all["total"], 2);
        assert_eq!(all["by_attendance"]["live"], 1);
        assert_eq!(all["by_attendance"]["stream"], 1);
        assert_eq!(all["shows"][0]["show_id"], json!(new.id));
        assert_eq!(all["shows"][0]["attendance"], "stream");

        let live = call(&snap, &marks, &json!({ "attendance": "live" })).unwrap();
        assert_eq!(live["total"], 1);
        assert_eq!(live["shows"][0]["show_id"], json!(old.id));
    }

    #[test]
    fn 記録が無ければ0件と案内を返す() {
        let snap = bundle_snapshot();
        let empty = call(&snap, &[], &json!({})).unwrap();
        assert_eq!(empty["total"], 0);
        assert!(empty["note"].is_string());
    }
}
