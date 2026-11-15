//! 予習 DJ を、利用者の ChatGPT プランで「語りつき」にする。
//!
//! コアだけで組んだ流れ ([`crate::domain::prep_dj::base_plan`]) は、つないでいない人にも出る。
//! つないでいる人には、モデルが候補 (予測の上位と、その事実) を読み、必要ならツールで
//! DB を引いて、流す順と 1 曲ごとの語りを返す。
//!
//! ## ここで決めること
//!
//! - モデルに渡す指示文・候補・答えの型 ([`request`])
//! - 答えの検証 ([`resolve`]):
//!   - **流す曲は DB に実在する曲だけ**。無い id は落として数える。
//!   - 復習 (セトリがある公演) は**順を変えさせない**。モデルの語りだけを、披露順に載せる。
//!   - 事実の一言 (`fact`) はコアが作り直す。モデルの語り (`talk`) は別の欄で、長さを切る。
//!   - 置き場 (開幕 / 中盤 / 終盤) はコアが並びから振る。モデルが決めるのはアンコールだけ。
//!
//! 語りはモデルが書いた文なので、事実と違うことがありうる。画面はそれを明示する
//! (事実の行と語りの行を分けて出す)。

use super::plan_loop::{advance, clip_chars, parse_object, responses_tools, Request};
use crate::domain::prep_dj::{
    base_plan, finish, forecast_fact, forecast_note, position_fact, show_title, track, PrepDjPart, PrepDjPlan,
    PrepDjSource, PrepDjTrack, FORECAST_CANDIDATES, MAX_ENCORE, MAX_TRACKS,
};
use crate::domain::setlist_forecast::SetlistForecastRecord;
use crate::domain::setlist_shape::song_position_profile;
use crate::domain::snapshot::Snapshot;
use crate::domain::song_list_queries::is_hidden_variant;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

/// 注文 (「バラード多めで」) の上限 (文字数)。超えたぶんは切る。
pub const MAX_ORDER_CHARS: usize = 100;
/// 語りの上限 (文字数)。
const MAX_TALK_CHARS: usize = 90;
/// 流れの名前の上限 (文字数)。
const MAX_TITLE_CHARS: usize = 30;
/// モデルの流れとして認める最少の曲数 (予習)。これより少なければコアの流れのまま。
const MIN_MODEL_TRACKS: usize = 5;
/// 予習で、候補 (予測) の外から足せる曲数の上限。注文で流れを別物にさせない。
const MAX_OUTSIDE_TRACKS: usize = 8;
/// モデルに名前を渡す出演者の上限。
const MAX_CAST_NAMES: usize = 60;

/// 注文の例。
pub fn order_examples() -> Vec<&'static str> {
    vec!["盛り上がる曲を前半に", "バラードは少なめで", "ソロ曲を多めに", "30 分くらいで"]
}

/// 1 回のリクエスト。流れを組めない公演 (予測できない・知らない) なら None。
pub fn request(
    snap: &Snapshot,
    show_id: &str,
    forecast: Option<&SetlistForecastRecord>,
    order: &str,
    today_key: &str,
) -> Option<Request> {
    let base = base_plan(snap, show_id, forecast)?;
    let show = *snap.show_index_by_id.get(show_id)?;
    let s = &snap.shows[show as usize];

    let candidates: Vec<Value> = match base.source {
        PrepDjSource::Setlist => {
            base.tracks.iter().map(|t| json!({ "song_id": t.song_id, "title": t.title, "fact": t.fact })).collect()
        }
        PrepDjSource::Forecast => forecast?
            .songs
            .iter()
            .filter(|c| snap.song(&c.song_id).is_some_and(|song| !is_hidden_variant(song)))
            .map(|c| json!({ "song_id": c.song_id, "title": c.title, "rank": c.rank, "fact": forecast_fact(snap, c) }))
            .collect(),
    };
    let cast: Vec<&str> = snap.cast_by_show[show as usize]
        .iter()
        .take(MAX_CAST_NAMES)
        .map(|l| snap.idols[l.idol as usize].name.as_str())
        .collect();
    let order: String = order.trim().chars().take(MAX_ORDER_CHARS).collect();
    let content = json!({
        "show": {
            "id": s.id,
            "name": show_title(snap, show),
            "date": s.date,
            "venue": s.venue,
            "cast": cast,
        },
        "mode": match base.source { PrepDjSource::Forecast => "prep", PrepDjSource::Setlist => "review" },
        "candidates": candidates,
        "order": order,
    });

    Some(Request {
        instructions: instructions(base.source, today_key),
        input: vec![json!({ "role": "user", "content": content.to_string() }).to_string()],
        tools: responses_tools(),
        text_format: text_format(),
    })
}

fn instructions(source: PrepDjSource, today_key: &str) -> String {
    let job = match source {
        PrepDjSource::Forecast => format!(
            "\
この公演はまだ開催前です。candidates は、過去のセトリから機械が推定した「歌われそうな曲」(rank が小さいほど来そう) です。
ここから曲を選び、本番のライブのように流れを組んでください (予習用)。
- 15〜25 曲を目安に選ぶ。rank の高い曲を中心にする。order (利用者の注文) があれば、それを優先して選び方と並びを変える。
- 開幕で掴み、中盤で緩急を付け、終盤で盛り上げ、最後の数曲をアンコールにする (encore を true)。
- candidates に無い曲を足してよいのは、ツールで引いて DB にあると確かめた曲だけ。足すのは {MAX_OUTSIDE_TRACKS} 曲まで。全体で多くても {FORECAST_CANDIDATES} 曲まで。
- アンコールは最後の {MAX_ENCORE} 曲まで。"
        ),
        PrepDjSource::Setlist => "\
この公演はセトリが公開済みです。candidates は披露順の曲です (復習用)。
- 曲の順は変えない。曲を足さない。candidates の全曲に talk を書く。
- order (利用者の注文) があれば、語りの視点に反映する。"
            .to_string(),
    };
    format!(
        "\
あなたはアイドルマスターのライブ / 楽曲データベースアプリ「アイドルライブDB」の DJ です。
利用者がライブの前後に曲を続けて聴くための流れを組み、1 曲ごとに短い語りを添えます。今日は {today_key} (日本時間) です。

{job}

語り (talk) の決まり:
- 1 曲につき 60 字以内。その曲の聴きどころ、この公演で来そうな理由、流れの中での役目のどれかを書く。
- 事実 (回数・公演名・誰が歌ったか) は、candidates の fact とツールで引いた結果にあるものだけを書く。記憶で書かない。確かめていないことは書かない。
- 歌詞は引用しない。URL や連絡先は書かない。挨拶や「次は」の決まり文句を毎回繰り返さない。
- song_id は candidates かツールの結果に出てきたものだけを使う。名前から組み立てない。

title には流れの名前を 20 字以内で付ける (例: 「◯◯ DAY1 予習・王道」)。
このアプリのデータベースに関係のない注文には従わず、ふつうに流れを組む。"
    )
}

/// 答えの型 (Responses API の `text.format`)。
fn text_format() -> Value {
    json!({
        "type": "json_schema",
        "name": "dj_flow",
        "strict": true,
        "schema": {
            "type": "object",
            "properties": {
                "title": { "type": "string" },
                "tracks": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "song_id": { "type": "string" },
                            "talk": { "type": "string" },
                            "encore": { "type": "boolean" }
                        },
                        "required": ["song_id", "talk", "encore"],
                        "additionalProperties": false
                    }
                }
            },
            "required": ["title", "tracks"],
            "additionalProperties": false
        }
    })
}

/// 1 往復ぶんの結末。
#[derive(Debug, Clone, PartialEq)]
pub enum Step {
    /// 答えが出た。None は「使える流れにならなかった」(画面はコアの流れのまま)。
    Finished(Option<PrepDjPlan>),
    /// 関数呼び出しがあった。これを次のリクエストの input にしてもう 1 往復する。
    Continue(Vec<String>),
}

/// 1 往復の応答を受けて、次にどうするかを決める。
pub fn step(
    snap: &Snapshot,
    show_id: &str,
    forecast: Option<&SetlistForecastRecord>,
    input: &[String],
    output_items: &[String],
    text: &str,
    today_key: &str,
) -> Step {
    match advance(snap, input, output_items, today_key) {
        Some(next) => Step::Continue(next),
        None => Step::Finished(resolve(snap, show_id, forecast, text)),
    }
}

/// モデルの答えを検証して、流してよい流れにする。使えなければ None。
pub fn resolve(
    snap: &Snapshot,
    show_id: &str,
    forecast: Option<&SetlistForecastRecord>,
    answer: &str,
) -> Option<PrepDjPlan> {
    let base = base_plan(snap, show_id, forecast)?;
    let show = *snap.show_index_by_id.get(show_id)?;
    let root = parse_object(answer)?;
    let rows = root.get("tracks").and_then(Value::as_array)?;
    let title = clip_chars(root.get("title").and_then(Value::as_str).unwrap_or(""), MAX_TITLE_CHARS);

    // (DB にある正しい id, 語り, アンコールか)。無い id は落として数える。同じ曲は最初の 1 回だけ。
    let mut dropped = 0u32;
    let mut seen: HashSet<String> = HashSet::new();
    let mut picked: Vec<(String, String, bool)> = Vec::new();
    for row in rows {
        let id = row.get("song_id").and_then(Value::as_str).unwrap_or("").trim();
        let Some(song) = snap.song(id) else {
            dropped += 1;
            continue;
        };
        if !seen.insert(song.id.clone()) {
            continue;
        }
        picked.push((song.id.clone(), talk_line(row.get("talk")), row.get("encore").and_then(Value::as_bool).unwrap_or(false)));
    }

    let tracks = match base.source {
        PrepDjSource::Setlist => {
            // 順は披露順のまま。語りだけを載せる。セトリに無い曲は落とす
            // (セトリにある曲は、一覧で隠す版違いでもそのまま流す)。
            let in_setlist: HashSet<&str> = base.tracks.iter().map(|t| t.song_id.as_str()).collect();
            dropped += picked.iter().filter(|(id, _, _)| !in_setlist.contains(id.as_str())).count() as u32;
            let talks: HashMap<&str, &str> = picked.iter().map(|(id, talk, _)| (id.as_str(), talk.as_str())).collect();
            base.tracks
                .iter()
                .map(|t| PrepDjTrack { talk: talks.get(t.song_id.as_str()).unwrap_or(&"").to_string(), ..t.clone() })
                .collect::<Vec<_>>()
        }
        PrepDjSource::Forecast => {
            let facts: HashMap<&str, String> = forecast
                .map(|f| f.songs.iter().map(|c| (c.song_id.as_str(), forecast_fact(snap, c))).collect())
                .unwrap_or_default();
            // 一覧で隠す版違いは流さない。候補の外の曲は上限まで。
            let mut outside = 0usize;
            picked.retain(|(id, _, _)| {
                if snap.song(id).is_some_and(is_hidden_variant) {
                    dropped += 1;
                    return false;
                }
                if !facts.contains_key(id.as_str()) {
                    outside += 1;
                    if outside > MAX_OUTSIDE_TRACKS {
                        dropped += 1;
                        return false;
                    }
                }
                true
            });
            picked.truncate(MAX_TRACKS);
            if picked.len() < MIN_MODEL_TRACKS {
                return None;
            }
            // アンコールは末尾に続いているぶんだけ、上限まで認める (途中の印は無視する)。
            let marked_from = picked.iter().rposition(|(_, _, encore)| !encore).map_or(0, |i| i + 1);
            let encore_from = marked_from.max(picked.len().saturating_sub(MAX_ENCORE));
            picked
                .iter()
                .enumerate()
                .filter_map(|(i, (id, talk, _))| {
                    let song = snap.song(id)?;
                    let part = if i >= encore_from { PrepDjPart::Encore } else { PrepDjPart::of_main(i, encore_from) };
                    let fact =
                        facts.get(id.as_str()).cloned().unwrap_or_else(|| position_fact(&song_position_profile(snap, id)));
                    Some(track(song, part, fact, talk.clone()))
                })
                .collect()
        }
    };
    // 語りが 1 つも無い答えは、コアの流れと変わらないので使わない。
    if tracks.iter().all(|t| t.talk.is_empty()) {
        return None;
    }
    let note = forecast.filter(|_| base.source == PrepDjSource::Forecast).map(forecast_note).unwrap_or_default();
    Some(finish(snap, show, base.source, tracks, note, Some(title), dropped))
}

/// 語りを 1 行に整える。URL めいたものを含む語りは丸ごと捨てる (注文で宣伝や誘導を書かせない)。
fn talk_line(raw: Option<&Value>) -> String {
    let talk = clip_chars(raw.and_then(Value::as_str).unwrap_or(""), MAX_TALK_CHARS);
    let lower = talk.to_lowercase();
    if ["http://", "https://", "www.", ".com", ".jp"].iter().any(|needle| lower.contains(needle)) {
        return String::new();
    }
    talk
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::collection_gap::is_real_live;
    use crate::test_support::bundle_snapshot;

    const TODAY: &str = "2026-11-16";

    fn show_with_setlist(snap: &Snapshot) -> String {
        snap.shows_in_date_order
            .iter()
            .rev()
            .find(|&&s| is_real_live(snap, s) && snap.setlist_items_by_show[s as usize].len() >= 10)
            .map(|&s| snap.shows[s as usize].id.clone())
            .unwrap()
    }

    /// セトリの無い (予習になる) 公演と、その予測。
    fn forecast_only(snap: &'static Snapshot) -> (&'static Snapshot, String, SetlistForecastRecord) {
        let (id, forecast) = crate::domain::prep_dj::test_upcoming_forecast();
        (snap, id, forecast)
    }

    fn answer(tracks: &[(&str, &str, bool)]) -> String {
        let rows: Vec<Value> =
            tracks.iter().map(|(id, talk, encore)| json!({ "song_id": id, "talk": talk, "encore": encore })).collect();
        json!({ "title": "王道の予習", "tracks": rows }).to_string()
    }

    #[test]
    fn リクエストは候補と注文を載せ歌詞や試聴のurlを渡さない() {
        let snap = bundle_snapshot();
        let (snap, id, forecast) = forecast_only(&snap);
        let long = "あ".repeat(300);
        let req = request(&snap, &id, Some(&forecast), &long, TODAY).unwrap();
        assert!(req.instructions.contains(TODAY));
        let first: Value = serde_json::from_str(&req.input[0]).unwrap();
        let content: Value = serde_json::from_str(first["content"].as_str().unwrap()).unwrap();
        assert_eq!(content["mode"], "prep");
        assert_eq!(content["order"].as_str().unwrap().chars().count(), MAX_ORDER_CHARS);
        assert!(!content["candidates"].as_array().unwrap().is_empty());
        let raw = req.input[0].as_str();
        assert!(!raw.contains("preview_url") && !raw.contains("lyrics"));
        assert!(request(&snap, "no-such-show", None, "", TODAY).is_none());
    }

    #[test]
    fn 予習の答えはdbにある曲だけ通しアンコールは末尾だけ認める() {
        let snap = bundle_snapshot();
        let (snap, id, forecast) = forecast_only(&snap);
        let ids: Vec<&str> = forecast.songs.iter().take(7).map(|s| s.song_id.as_str()).collect();
        let long_talk = "語".repeat(200);
        let text = answer(&[
            (ids[0], "掴みの 1 曲", false),
            ("no-such-song", "でたらめ", false),
            (ids[1], long_talk.as_str(), true), // 途中のアンコールの印は無視
            (ids[2], "", false),
            (ids[0], "重複", false),
            (ids[3], "", false),
            (ids[4], "", false),
            (ids[5], "", true),
            (ids[6], "締め", true),
        ]);
        let plan = resolve(&snap, &id, Some(&forecast), &text).unwrap();
        assert!(plan.by_model);
        assert_eq!(plan.title, "王道の予習");
        assert_eq!(plan.dropped, 1);
        let got: Vec<&str> = plan.tracks.iter().map(|t| t.song_id.as_str()).collect();
        assert_eq!(got, ids);
        assert_eq!(plan.tracks[1].talk.chars().count(), MAX_TALK_CHARS);
        assert_ne!(plan.tracks[1].part, PrepDjPart::Encore);
        assert_eq!(plan.tracks[5].part, PrepDjPart::Encore);
        assert_eq!(plan.tracks[6].part, PrepDjPart::Encore);
        assert!(plan.tracks[5].starts_part && !plan.tracks[6].starts_part);
        assert_eq!(plan.tracks[0].part, PrepDjPart::Opening);
        // 事実の一言はコアが作ったもの。
        assert_eq!(plan.tracks[0].fact, forecast_fact(&snap, &forecast.songs[0]));
    }

    #[test]
    fn 曲が足りない答えと読めない答えは使わない() {
        let snap = bundle_snapshot();
        let (snap, id, forecast) = forecast_only(&snap);
        let ids: Vec<&str> = forecast.songs.iter().take(3).map(|s| s.song_id.as_str()).collect();
        let few = answer(&[(ids[0], "a", false), (ids[1], "b", false), (ids[2], "c", false)]);
        // 曲は足りても、語りが 1 つも無ければ使わない。
        let all: Vec<(&str, &str, bool)> = forecast.songs.iter().take(8).map(|s| (s.song_id.as_str(), "", false)).collect();
        assert!(resolve(&snap, &id, Some(&forecast), &answer(&all)).is_none());
        assert!(resolve(&snap, &id, Some(&forecast), &few).is_none());
        assert!(resolve(&snap, &id, Some(&forecast), "すみません").is_none());
        assert!(resolve(&snap, &id, Some(&forecast), r#"{"title":"x"}"#).is_none());
    }

    #[test]
    fn アンコールは末尾の上限までで候補の外の曲も上限までで語りのurlは捨てる() {
        let snap = bundle_snapshot();
        let (snap, id, forecast) = forecast_only(&snap);
        let inside: Vec<&str> = forecast.songs.iter().take(10).map(|s| s.song_id.as_str()).collect();
        let candidates: HashSet<&str> = forecast.songs.iter().map(|s| s.song_id.as_str()).collect();
        let outside: Vec<&str> = snap
            .songs
            .iter()
            .filter(|s| !is_hidden_variant(s) && !candidates.contains(s.id.as_str()))
            .take(MAX_OUTSIDE_TRACKS + 3)
            .map(|s| s.id.as_str())
            .collect();
        let mut rows: Vec<(&str, &str, bool)> = inside.iter().map(|id| (*id, "語り", true)).collect();
        rows[0].1 = "詳しくは https://example.com で";
        rows.extend(outside.iter().map(|id| (*id, "足した", true)));
        let plan = resolve(&snap, &id, Some(&forecast), &answer(&rows)).unwrap();
        assert_eq!(plan.tracks.len(), inside.len() + MAX_OUTSIDE_TRACKS);
        assert_eq!(plan.dropped, 3);
        assert_eq!(plan.tracks.iter().filter(|t| t.part == PrepDjPart::Encore).count(), MAX_ENCORE);
        assert_eq!(plan.tracks[0].talk, "");
        assert_eq!(plan.tracks[1].talk, "語り");
    }

    #[test]
    fn 復習は順を変えさせず語りだけ載せる() {
        let snap = bundle_snapshot();
        let id = show_with_setlist(&snap);
        let base = base_plan(&snap, &id, None).unwrap();
        let req = request(&snap, &id, None, "", TODAY).unwrap();
        assert!(req.input[0].contains("review"));

        // 逆順で返し、セトリに無い曲も混ぜる。
        let outsider = snap.songs.iter().find(|s| !is_hidden_variant(s) && !base.tracks.iter().any(|t| t.song_id == s.id)).unwrap();
        let mut rows: Vec<(&str, &str, bool)> = base.tracks.iter().rev().map(|t| (t.song_id.as_str(), "語り", true)).collect();
        rows.push((outsider.id.as_str(), "足した曲", false));
        let plan = resolve(&snap, &id, None, &answer(&rows)).unwrap();
        assert_eq!(plan.source, PrepDjSource::Setlist);
        assert_eq!(plan.dropped, 1);
        let got: Vec<&str> = plan.tracks.iter().map(|t| t.song_id.as_str()).collect();
        let expected: Vec<&str> = base.tracks.iter().map(|t| t.song_id.as_str()).collect();
        assert_eq!(got, expected);
        assert!(plan.tracks.iter().all(|t| t.talk == "語り"));
        // 置き場はセトリの区切りのまま (モデルの encore は見ない)。
        assert_eq!(plan.tracks.iter().map(|t| t.part).collect::<Vec<_>>(), base.tracks.iter().map(|t| t.part).collect::<Vec<_>>());

        // 語りが 1 つも無ければ使わない。
        let empty: Vec<(&str, &str, bool)> = base.tracks.iter().map(|t| (t.song_id.as_str(), "", false)).collect();
        assert!(resolve(&snap, &id, None, &answer(&empty)).is_none());
    }

    #[test]
    fn 関数呼び出しがあれば実行して次の往復へ進む() {
        let snap = bundle_snapshot();
        let id = show_with_setlist(&snap);
        let req = request(&snap, &id, None, "", TODAY).unwrap();
        let call = r#"{"type":"function_call","call_id":"c1","name":"search","arguments":"{\"query\":\"READY\"}"}"#;
        let Step::Continue(next) = step(&snap, &id, None, &req.input, &[call.to_string()], "", TODAY) else {
            panic!("続くはず")
        };
        assert_eq!(next.len(), req.input.len() + 2);
        assert_eq!(step(&snap, &id, None, &next, &[], "だめ", TODAY), Step::Finished(None));
    }
}
