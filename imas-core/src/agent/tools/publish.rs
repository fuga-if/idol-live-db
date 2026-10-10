//! 公開 API (`imas-data-api`) が配る「1 件の文書」の組み立て。
//!
//! ## なぜここに置くか
//!
//! API の応答は Web でもアプリでも MCP でも**同じ質問に同じ答え**でなければならない
//! (`docs/ARCHITECTURE-mcp.md` §2 の 2)。そこで文書は新しい規則を書かず、`get_idol` /
//! `idol_songs` / `get_song` と話し方 ([`super::speech`]) をそのまま呼んで束ねるだけにする。
//! Worker (TypeScript) 側は、この文書を D1 から引いて返すだけで、中身に触れない。
//!
//! ## 返さないもの
//!
//! `get_song` などの出力は歌詞本文・`lyrics_url`・`preview_url` を持たない (ツール面の
//! 約束。`mod.rs` のテストが固定している)。ここでも `serde_json::to_value(song)` のような
//! 構造体丸ごとの変換をしない。出力に対するテストは下と `web_export::data_api` にある。
//! タグはコミュニティが付けるリアルタイムのデータ (imas-live-api) なので載せない。

use super::json::{brand_ref, Obj};
use super::{call_tool, speech, ToolError};
use crate::domain::idol_queries as idols;
use crate::domain::snapshot::Snapshot;
use crate::domain::unit_queries;
use serde_json::{json, Value};

/// 文書の形の版。キーの追加は版を上げない。削除・改名・型の変更で上げる。
pub const SCHEMA_VERSION: u32 = 1;
/// 「ライブで歌った曲」を何件まで載せるか (残りは `performed_total` で数だけ)。
pub const PERFORMED_SONGS_LIMIT: u32 = 50;
/// 「出演ライブ」を何件まで載せるか (新しい順。残りは `shows_total` で数だけ)。
pub const SHOWS_LIMIT: usize = 30;
/// ユニットの持ち曲を何件まで載せるか。
pub const UNIT_SONGS_LIMIT: usize = 100;
/// 持ち歌の上限 (`idol_songs` の上限と同じ)。
const ORIGINAL_SONGS_LIMIT: u32 = 300;

/// アイドル 1 人の文書。
pub fn idol_document(snap: &Snapshot, idol_id: &str, today_key: &str) -> Result<Value, ToolError> {
    let mut doc = call_tool(snap, "get_idol", &json!({ "id": idol_id }), today_key)?;
    let Some(map) = doc.as_object_mut() else {
        return Err(ToolError::Failed("get_idol がオブジェクトを返さなかった".into()));
    };
    // 上位 10 曲は下の `performed` (上位 N) に含まれるので重複させない。
    for key in ["top_performed_songs", "top_performed_songs_total", "top_performed_songs_truncated"] {
        map.remove(key);
    }

    // 持ち歌 (原唱 + ユニット名義)。
    let original = call_tool(
        snap,
        "idol_songs",
        &json!({ "idol_id": idol_id, "role": "original", "limit": ORIGINAL_SONGS_LIMIT }),
        today_key,
    )?;
    // ライブで歌った曲 (回数順の上位 N)。
    let performed = call_tool(
        snap,
        "idol_songs",
        &json!({ "idol_id": idol_id, "role": "performed", "limit": PERFORMED_SONGS_LIMIT }),
        today_key,
    )?;
    for part in [original, performed] {
        if let Value::Object(m) = part {
            for (k, v) in m {
                if k != "idol" {
                    map.insert(k, v);
                }
            }
        }
    }

    // 出演ライブ (新しい順)。
    let shows = idols::idol_shows(snap, idol_id);
    let rows: Vec<Value> = shows
        .iter()
        .take(SHOWS_LIMIT)
        .map(|s| {
            let mut v = super::lookup::idol_show_json(s);
            if let Some(o) = v.as_object_mut() {
                o.insert("cast_role".into(), Value::String(s.cast_role.clone()));
            }
            v
        })
        .collect();
    let mut o = Obj::new();
    o.put("shows", Value::Array(rows));
    o.put("shows_total", shows.len());
    if shows.len() > SHOWS_LIMIT {
        o.put("shows_truncated", true);
    }
    if let Value::Object(m) = o.value() {
        map.extend(m);
    }

    if let Some(profile) =
        speech::speech_profile(idol_id, |id| snap.idol(id).map(|i| i.name.clone()))
    {
        map.insert("speech".into(), profile);
    }
    map.insert("schema_version".into(), json!(SCHEMA_VERSION));
    Ok(doc)
}

/// アイドル 1 人の項目の束 (`GET /v1/idols/:id/facts`、MCP の `get_idol_facts`)。
///
/// 組み立ては `domain::idol_facets::build_idol_facts`。ここは話し方 (出典つきの公式データ)
/// を渡すだけ。`tags` はタグの票の写し (imas-live-api から同期。MCP・アプリ内トークは空)。
/// 歌詞・試聴の URL・体重・スリーサイズは束に含まれない (domain のテストが固定)。
pub fn idol_facts_document(
    snap: &Snapshot,
    idol_id: &str,
    tags: &[crate::domain::idol_facets::TagFacetInput],
) -> Result<Value, ToolError> {
    let persona = speech::persona_input(idol_id);
    crate::domain::idol_facets::build_idol_facts(snap, idol_id, &persona, tags)
        .ok_or_else(|| ToolError::NotFound(format!("idol の id が無い: {idol_id}")))
}

/// 曲 1 件の文書。
pub fn song_document(snap: &Snapshot, song_id: &str, today_key: &str) -> Result<Value, ToolError> {
    let mut doc = call_tool(snap, "get_song", &json!({ "id": song_id }), today_key)?;
    if let Some(m) = doc.as_object_mut() {
        m.insert("schema_version".into(), json!(SCHEMA_VERSION));
    }
    Ok(doc)
}

/// ユニット 1 件の文書。
pub fn unit_document(snap: &Snapshot, unit_id: &str) -> Option<Value> {
    let unit = unit_queries::unit_by_id(snap, unit_id)?;
    let mut o = Obj::new();
    o.put("id", unit.id.as_str());
    o.put("name", unit.name.as_str());
    o.opt("name_kana", unit.name_kana.as_deref());
    o.opt("name_alt", unit.name_alt.as_deref());
    o.put("is_permanent", unit.is_permanent);
    o.opt("brand", brand_ref(snap, Some(&unit.brand_id)));
    let members: Vec<Value> = unit_queries::unit_member_idol_ids(snap, unit_id)
        .iter()
        .filter_map(|id| snap.idol(id))
        .map(|i| json!({ "id": i.id, "name": i.name }))
        .collect();
    o.put("member_count", members.len());
    o.list("members", members);
    let song_ids = unit_queries::unit_song_ids(snap, unit_id);
    let songs: Vec<Value> = song_ids
        .iter()
        .take(UNIT_SONGS_LIMIT)
        .filter_map(|id| snap.song(id))
        .map(|s| {
            let mut x = Obj::new();
            x.put("id", s.id.as_str());
            x.put("title", s.title.as_str());
            x.opt("release_date", s.release_date.as_deref());
            x.value()
        })
        .collect();
    o.put("song_count", song_ids.len());
    o.list("songs", songs);
    o.put("schema_version", SCHEMA_VERSION);
    Some(o.value())
}

/// ブランド一覧の文書。
pub fn brands_document(snap: &Snapshot) -> Value {
    let mut brands: Vec<&crate::domain::snapshot::Brand> = snap.brands.iter().collect();
    brands.sort_by(|a, b| a.sort_order.cmp(&b.sort_order).then_with(|| a.id.cmp(&b.id)));
    let rows: Vec<Value> = brands
        .iter()
        .map(|b| {
            let mut o = Obj::new();
            o.put("id", b.id.as_str());
            o.put("name", b.name.as_str());
            o.put("short_name", b.short_name.as_str());
            o.opt("color", b.color.as_deref());
            o.value()
        })
        .collect();
    json!({ "schema_version": SCHEMA_VERSION, "brands": rows })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    const TODAY: &str = "2026-10-01";

    fn mao(snap: &Snapshot) -> &str {
        snap.idols.iter().find(|i| i.id == "gakuen_有村麻央").map(|i| i.id.as_str()).unwrap_or(&snap.idols[0].id)
    }

    #[test]
    fn アイドルの文書はツール面と同じ答えを束ねている() {
        let snap = bundle_snapshot();
        let id = mao(snap);
        let doc = idol_document(snap, id, TODAY).unwrap();
        let tool = call_tool(snap, "get_idol", &json!({ "id": id }), TODAY).unwrap();
        for key in ["id", "name", "birthday", "description", "voice_actor", "units", "performed_song_count", "show_count"] {
            assert_eq!(doc.get(key), tool.get(key), "{key} がツール面と違う");
        }
        let songs = call_tool(snap, "idol_songs", &json!({ "idol_id": id, "role": "original", "limit": 300 }), TODAY).unwrap();
        assert_eq!(doc["original"], songs["original"]);
        assert!(doc.get("performed_total").is_some() && doc.get("shows_total").is_some());
        assert!(doc.get("top_performed_songs").is_none());
    }

    #[test]
    fn 話し方のある子は文書に話し方が入る() {
        let snap = bundle_snapshot();
        let doc = idol_document(snap, "765as_天海春香", TODAY).unwrap();
        assert!(doc["speech"]["first_person"].is_string(), "{}", doc["speech"]);
        assert!(doc["speech"]["producer_call"].is_string());
        assert!(doc["speech"].get("sources").is_none(), "出典 URL は載せない");
    }

    #[test]
    fn 全文書が組めて_持ち歌は大きさで切れない() {
        let snap = bundle_snapshot();
        for idol in &snap.idols {
            let doc = idol_document(snap, &idol.id, TODAY).unwrap();
            for key in ["original_truncated", "unit_songs_truncated", "original_truncated_reason", "unit_songs_truncated_reason"] {
                assert!(doc.get(key).is_none(), "{} の {key}", idol.id);
            }
            assert!(doc["performed"].as_array().unwrap().len() <= PERFORMED_SONGS_LIMIT as usize);
            assert!(doc["shows"].as_array().unwrap().len() <= SHOWS_LIMIT);
        }
        for unit in &snap.units {
            assert!(unit_document(snap, &unit.id).is_some());
        }
    }

    #[test]
    fn 文書に歌詞と試聴の_url_もタグも出ない() {
        let snap = bundle_snapshot();
        let 禁止値: Vec<&str> = snap
            .songs
            .iter()
            .flat_map(|s| [s.lyrics_url.as_deref(), s.preview_url.as_deref()])
            .flatten()
            .filter(|v| !v.is_empty())
            .collect();
        assert!(!禁止値.is_empty());
        let mut all: Vec<Value> = Vec::new();
        for i in &snap.idols {
            all.push(idol_document(snap, &i.id, TODAY).unwrap());
        }
        for s in &snap.songs {
            all.push(song_document(snap, &s.id, TODAY).unwrap());
        }
        for u in &snap.units {
            all.push(unit_document(snap, &u.id).unwrap());
        }
        all.push(brands_document(snap));
        for doc in all {
            let text = doc.to_string();
            for key in ["lyrics_url", "preview_url", "\"tags\""] {
                assert!(!text.contains(key), "{key} が文書に出ている");
            }
            for v in &禁止値 {
                assert!(!text.contains(v), "歌詞/試聴の URL が文書に出ている");
            }
        }
    }
}
