//! 「こんな公演があったらどんなセトリになるか」を**呼び手が考えるための材料**
//! (list_shows・setlist_shape・song_position_profile・co_performed_songs)。
//!
//! # ここに予想は書かない
//!
//! 返すのは過去の事実だけ。「この曲が来そう」のスコアも、枠ごとの重みづけも持たない。
//! 予想を Rust に埋めると、外れたときに直す先が無く、DB が予想を持っているように
//! 見える。予想は、この 4 本が返した事実を読んだ LLM が組み立てる。
//!
//! # なぜ browse から分けたか
//!
//! `list_shows` だけなら `browse` に置いてもよかったが、`setlist_shape` は
//! **`list_shows` とまったく同じ軸で公演を絞る**必要がある (「翼が lead の公演の型」は
//! 「翼が lead の公演の一覧」と同じ集合でなければ意味が無い)。軸をほどく口
//! (`super::scope`) と絞り込みの規則 (`domain::show_list_filtering`) を共有する 4 本を
//! 1 ファイルに置く。
//!
//! # 規則は借りる
//!
//! このファイルが持つのは JSON の組み方だけ。絞り込みは `show_list_filtering`、
//! 型の計算は `domain::setlist_shape`、共起は `domain::performance_stats`、
//! 語彙の検査は `super::scope` / `super::vocab` が正本。

use super::json::{brand_ref, listing_with, Obj};
use super::scope::{narrowing_hint, show_criteria, show_scope_schema, SHOW_SCOPE_ARGS};
use super::{args, ToolError, ToolSpec};
use crate::domain::event_detail_queries::show_presence;
use crate::domain::event_grouping::is_upcoming_on;
use crate::domain::setlist_shape::{self as shape, Phase};
use crate::domain::show_list_filtering::{filter_show_indexes, ShowFilterCriteria};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 枠ごとのランキングを何件まで並べるか。主演公演が 6 件しかない以上、
/// 上位 8 件も並べれば「1 回だけ来た曲」まで見えるので十分。
const SLOT_TOP: u32 = 8;

// =============================================================================
// カタログ
// =============================================================================

pub fn catalog() -> Vec<ToolSpec> {
    vec![
        spec(
            "list_shows",
            "条件で公演 (1 日ぶん) を並べる。list_events はライブ単位なので\
             「出演者が 13 人の公演」「あの人が主演だった公演」は引けない — そのときはこちら。\
             idol_id と cast_role を組み合わせると「その人が lead (主演) だった公演」が出る。",
            show_scope_schema(json!({
                "has_setlist": { "type": "boolean", "description": "セトリが入っている公演だけ / 入っていない公演だけ。" },
                "limit": { "type": "integer", "description": "既定 30・最大 200。" }
            })),
            &[],
        ),
        spec(
            "setlist_shape",
            "公演群のセトリの「型」。曲数・区切りごとの曲数・1 曲目 / アンコール / 締めに\
             来やすい曲・ソロ枠の本数 (とそのうち主演が歌った本数)・出演者 1 人あたりの歌唱曲数 (主演 lead_songs と\
             それ以外 member_songs、および公演の全曲に対する割合 *_share_percent) を、\
             指定した公演の集合について返す。\
             絞り込みの軸は list_shows と同じ。\
             **これは予想ではなく過去の実績**で、標本にした公演数 (shows) が必ず添うので、\
             少ない標本から出た数字かどうかは呼び手が見て判断すること。",
            show_scope_schema(json!({
                "top": { "type": "integer", "description": "枠ごとのランキング件数。既定 8・最大 30。" }
            })),
            &[],
        ),
        spec(
            "song_position_profile",
            "ある曲が公演の「どこで」歌われるか。披露回数のうち 1 曲目・締め・アンコールが\
             何回か、区切り別の回数、公演内の相対位置 (序盤 / 中盤 / 終盤) の分布を返す。\
             song_performances が 1 回ずつの履歴を返すのに対し、こちらは位置の傾向をまとめる。",
            json!({
                "song_id": { "type": "string", "description": "曲の id。" }
            }),
            &["song_id"],
        ),
        spec(
            "co_performed_songs",
            "同じ公演で一緒に歌われやすい曲。together が一緒に来た公演数、\
             performances が相手の曲の総披露公演数 (分母)。1 公演で 2 回歌われても 1 と数える。",
            json!({
                "song_id": { "type": "string", "description": "曲の id。" },
                "limit": { "type": "integer", "description": "既定 20・最大 100。" }
            }),
            &["song_id"],
        ),
    ]
}

/// 自分の持ちツールなら `Some(結果)`、違うなら `None` (呼び手が次を試す)。
pub fn call(
    snap: &Snapshot,
    name: &str,
    arguments: &Value,
    today_key: &str,
) -> Option<Result<Value, ToolError>> {
    Some(match name {
        "list_shows" => list_shows(snap, arguments, today_key),
        "setlist_shape" => setlist_shape(snap, arguments, today_key),
        "song_position_profile" => song_position_profile(snap, arguments),
        "co_performed_songs" => co_performed_songs(snap, arguments),
        _ => return None,
    })
}

fn spec(name: &str, description: &str, properties: Value, required: &[&str]) -> ToolSpec {
    ToolSpec {
        name: name.to_string(),
        description: description.to_string(),
        input_schema: super::tool_schema(properties, required),
    }
}

/// 公演を絞る。`list_shows` と `setlist_shape` はここを通るので、
/// 「一覧」と「型」が必ず同じ集合から出る。
fn narrow_shows(
    snap: &Snapshot,
    arguments: &Value,
    today_key: &str,
) -> Result<(Vec<u32>, ShowFilterCriteria), ToolError> {
    let mut allow: Vec<&str> = SHOW_SCOPE_ARGS.to_vec();
    allow.push("has_setlist");
    let criteria = show_criteria(snap, arguments, today_key, &allow)?;
    // 条件も返すのは、0 件だったときに「どの軸が効いて 0 になったか」を
    // 言うため。呼び手の引数から組み直すと、ほどき方が二重管理になる。
    Ok((filter_show_indexes(snap, &criteria), criteria))
}

// =============================================================================
// list_shows
// =============================================================================

fn list_shows(snap: &Snapshot, arguments: &Value, today_key: &str) -> Result<Value, ToolError> {
    use super::browse::{show_header, take};

    let limit = args::limit(arguments, 30, 200)?;
    let (shows, criteria) = narrow_shows(snap, arguments, today_key)?;
    let total = shows.len();

    let rows = take(shows, limit)
        .into_iter()
        .map(|s| {
            let show = &snap.shows[s as usize];
            let event = &snap.events[show.event as usize];
            let mut o = Obj::new();
            // 「どの公演か」の書き方は browse と共通 (同じ鍵で同じ意味になる)。
            o.merge(show_header(snap, s));
            o.put("id", json!(show.id));
            o.opt("brand", brand_ref(snap, event.brand_id.as_deref()));
            o.put("cast_count", json!(show_presence(snap, s).len()));
            // 主演は数が少ないので名前まで出す (これが出れば「主演公演だったか」が
            // 一覧を見るだけで分かり、公演ごとに get_show を呼ばずに済む)。
            o.list("lead", role_names(snap, s, "lead"));
            o.put("upcoming", json!(is_upcoming_on(&show.date, today_key)));
            o.value()
        })
        .collect();

    let mut head = Obj::new();
    if total == 0 {
        // 空配列だけ返すと「そういう公演は無い」と書かれる。手がかりを先頭に置く。
        head.put("no_hits", narrowing_hint(snap, &criteria));
    }
    Ok(listing_with(head, "shows", total, rows))
}

/// その公演でその役割だった人の名前。並びは `cast_by_show` の前計算順。
fn role_names(snap: &Snapshot, show: u32, role: &str) -> Vec<Value> {
    snap.cast_by_show[show as usize]
        .iter()
        .filter(|l| l.cast_role == role)
        .map(|l| {
            let idol = &snap.idols[l.idol as usize];
            let mut o = Obj::new();
            o.put("id", idol.id.as_str());
            o.put("name", idol.name.as_str());
            o.value()
        })
        .collect()
}

// =============================================================================
// setlist_shape
// =============================================================================

fn setlist_shape(snap: &Snapshot, arguments: &Value, today_key: &str) -> Result<Value, ToolError> {
    // 件数ではなく「枠ごとの上位いくつ」なので鍵を limit と分ける
    // (同じ鍵にすると list_shows の limit と意味が混ざる)。丸め方は args と共通。
    let top = args::capped(arguments, "top", SLOT_TOP, 30)? as usize;
    let (shows, criteria) = narrow_shows(snap, arguments, today_key)?;
    let s = shape::setlist_shape(snap, &shows, top);

    let mut o = Obj::new();
    // 条件に 1 本も当たらなかったときだけ。当たったがセトリが無い場合は
    // shows_without_setlist がその事実を言うので、手がかりは要らない。
    if shows.is_empty() {
        o.put("no_hits", narrowing_hint(snap, &criteria));
    }
    o.put("shows", json!(s.shows()));
    // 0 でも載せる。落とすと「条件に当たった公演は全部セトリがあった」と読める。
    o.put("shows_without_setlist", json!(s.shows_without_setlist));
    // どの公演を標本にしたかを言えないと、数字の当否を呼び手が確かめられない。
    o.list(
        "sampled_shows",
        s.sampled
            .iter()
            .map(|&x| {
                let show = &snap.shows[x as usize];
                let mut r = Obj::new();
                r.put("id", show.id.as_str());
                r.put("date", show.date.as_str());
                r.put("name", show.name.as_str());
                r.value()
            })
            .collect(),
    );
    o.opt("song_count", s.song_count.as_ref().map(spread_json));
    o.list(
        "sections",
        s.sections
            .iter()
            .map(|sec| {
                let mut r = Obj::new();
                // 区切り無し (= 本編) は label ごと落とす。`null` を載せない規約どおり。
                r.opt("label", sec.label.clone());
                r.put("shows", json!(sec.shows()));
                r.put("songs", spread_json(&sec.songs));
                r.value()
            })
            .collect(),
    );
    o.list("openers", slot_rows(snap, &s.openers));
    o.list("encore", slot_rows(snap, &s.encore));
    o.list("closers", slot_rows(snap, &s.closers));
    o.opt("solo_slots", s.solo_slots.as_ref().map(spread_json));
    o.opt("lead_solo_slots", s.lead_solo_slots.as_ref().map(spread_json));
    // 主演が何曲歌うかは「主演公演のセトリ」を尋ねられたときの芯になる数字。
    // 比較対象 (member_songs) と対にして出す — 片方だけでは多い / 少ないが読めない。
    o.opt("lead_songs", s.lead_songs.as_ref().map(spread_json));
    o.opt("member_songs", s.member_songs.as_ref().map(spread_json));
    // 曲数は公演の規模 (23 〜 39 曲) に引きずられる。割合も併せて出さないと、
    // 規模の違う公演をまたいだ min / max が誤読される。
    o.opt("lead_share_percent", s.lead_share_percent.as_ref().map(spread_json));
    o.opt("member_share_percent", s.member_share_percent.as_ref().map(spread_json));
    Ok(o.value())
}

fn spread_json(s: &shape::Spread) -> Value {
    let mut o = Obj::new();
    o.put("samples", json!(s.samples));
    o.put("min", json!(s.min));
    o.put("median", json!(s.median));
    o.put("max", json!(s.max));
    o.value()
}

fn slot_rows(snap: &Snapshot, rows: &[shape::SlotTally]) -> Vec<Value> {
    rows.iter()
        .map(|t| {
            let mut o = Obj::new();
            o.put("id", t.song_id.as_str());
            o.opt("title", snap.song(&t.song_id).map(|s| s.title.clone()));
            o.put("times", json!(t.times));
            o.value()
        })
        .collect()
}

// =============================================================================
// song_position_profile
// =============================================================================

fn song_position_profile(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    let song_id = args::str_req(arguments, "song_id")?;
    let Some(&index) = snap.song_index_by_id.get(&song_id) else {
        return Err(ToolError::NotFound(format!("曲 {song_id} が無い")));
    };
    let p = shape::song_position_profile(snap, &song_id);

    let mut o = Obj::new();
    o.put("song", super::browse::song_row(snap, index));
    o.put("performances", json!(p.performances));
    o.put("opener", json!(p.opener));
    o.put("closer", json!(p.closer));
    o.put("encore", json!(p.encore));
    o.list(
        "sections",
        p.sections
            .iter()
            .map(|(label, times)| {
                let mut r = Obj::new();
                r.opt("label", label.clone());
                r.put("times", json!(times));
                r.value()
            })
            .collect(),
    );
    // 序盤 / 中盤 / 終盤。公演ごとに曲数が違う (1〜34 曲) ので、生の曲順ではなく
    // 曲数で正規化した 3 等分。割り方も鍵の名前も setlist_shape::Phase が正本。
    let mut phase = Obj::new();
    for ph in Phase::ALL {
        phase.put(ph.key(), json!(p.phase(ph)));
    }
    o.put("position", phase.value());
    Ok(o.value())
}

// =============================================================================
// co_performed_songs
// =============================================================================

fn co_performed_songs(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::performance_stats::CoOccurIndex;

    let song_id = args::str_req(arguments, "song_id")?;
    let Some(&index) = snap.song_index_by_id.get(&song_id) else {
        return Err(ToolError::NotFound(format!("曲 {song_id} が無い")));
    };
    let limit = args::limit(arguments, 20, 100)?;

    // 計算は performance_stats が正本。ここは呼ぶだけ (新しい数え方を書かない)。
    let stats = CoOccurIndex::build(snap);
    // 総数を返すために打ち切らずに受け、件数はこちらで切る (「何曲と一緒に来たか」に
    // 答えられなくなるので、打ち切った件数だけを返さない — §4 の規約)。
    let all = stats.co_occurring(snap, &song_id, u32::MAX);
    let total = all.len();
    let rows: Vec<Value> = all
        .into_iter()
        .take(limit as usize)
        .map(|c| {
            let mut o = Obj::new();
            o.put("id", c.song_id.as_str());
            o.opt("title", snap.song(&c.song_id).map(|s| s.title.clone()));
            o.put("together", json!(c.together));
            o.put("performances", json!(c.performances));
            o.value()
        })
        .collect();

    let mut head = Obj::new();
    head.put("song", super::browse::song_row(snap, index));
    // 「一緒に来る率」の分母になる、対象曲そのものの公演数。
    head.put("song_shows", json!(stats.performances(index)));
    Ok(listing_with(head, "co_performed", total, rows))
}

// =============================================================================
// テスト
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;
    use crate::agent::tools::call_tool;

    const TODAY: &str = "2026-09-19";

    fn call(name: &str, args: Value) -> Value {
        call_tool(bundle_snapshot(), name, &args, TODAY).unwrap_or_else(|e| panic!("{name}: {e}"))
    }

    #[test]
    fn 主演公演が無い人でも_0_件で落ちない() {
        // 伊吹翼には主演公演が無い。0 件が返ること (エラーにしないこと) を固定する。
        let out = call("list_shows", json!({ "idol_id": "ml_伊吹翼", "cast_role": "lead" }));
        assert_eq!(out["total"], json!(0), "{out}");
        // 出演した公演そのものは沢山ある。
        let all = call("list_shows", json!({ "idol_id": "ml_伊吹翼" }));
        assert!(all["total"].as_u64().unwrap() > 50, "{all}");
    }

    #[test]
    fn 人数と今後過去で絞れる() {
        let few = call("list_shows", json!({ "brand": "ml", "max_cast": 8, "has_setlist": true }));
        for row in few["shows"].as_array().unwrap() {
            assert!(row["cast_count"].as_u64().unwrap() <= 8, "{row}");
            assert!(row["song_count"].as_u64().unwrap() > 0, "{row}");
        }
        let upcoming = call("list_shows", json!({ "when": "upcoming" }));
        for row in upcoming["shows"].as_array().unwrap() {
            assert_eq!(row["upcoming"], json!(true), "{row}");
        }
        // upcoming は近い順 (日付昇順)。
        let dates: Vec<&str> =
            upcoming["shows"].as_array().unwrap().iter().map(|r| r["date"].as_str().unwrap()).collect();
        assert!(dates.windows(2).all(|w| w[0] <= w[1]), "{dates:?}");
    }

    #[test]
    fn 種別で発売記念イベントを外せる() {
        // 発売記念イベント (2 曲のミニステージ) が混ざったままだと曲数の中央値が
        // 本公演の型を表さない。kind=live で外れることを固定する。
        let all = call("setlist_shape", json!({ "idol_id": "ml_伊吹翼", "max_cast": 16 }));
        let live = call("setlist_shape", json!({ "idol_id": "ml_伊吹翼", "max_cast": 16, "event_kind": "live" }));
        assert!(live["shows"].as_u64().unwrap() < all["shows"].as_u64().unwrap(), "{live}");
        assert!(
            live["song_count"]["median"].as_u64().unwrap()
                > all["song_count"]["median"].as_u64().unwrap(),
            "発売記念イベントが混ざったままの方が曲数が多い: {all} / {live}"
        );
    }

    #[test]
    fn 型は同じ軸で絞った公演から出る() {
        let listed = call("list_shows", json!({ "cast_role": "lead" }));
        let shaped = call("setlist_shape", json!({ "cast_role": "lead" }));
        // 一覧の件数 = 型の標本 + セトリ未入力。ここがズレたら軸が二重管理になっている。
        assert_eq!(
            listed["total"].as_u64().unwrap(),
            shaped["shows"].as_u64().unwrap() + shaped["shows_without_setlist"].as_u64().unwrap(),
            "一覧と型で公演の集合が違う: {listed} / {shaped}"
        );
        assert!(shaped["song_count"]["median"].as_u64().unwrap() >= 10, "{shaped}");
        assert!(!shaped["openers"].as_array().unwrap().is_empty(), "{shaped}");
        assert!(!shaped["closers"].as_array().unwrap().is_empty(), "{shaped}");
        assert!(shaped["solo_slots"]["max"].as_u64().unwrap() >= 1, "{shaped}");
    }

    #[test]
    fn 空振りは外すべき軸を名指しで返す() {
        // 伊吹翼に主演公演はまだ無い (「翼が主演ならどんなセトリか」の出発点)。
        let out = call("list_shows", json!({ "idol_id": "ml_伊吹翼", "cast_role": "lead" }));
        assert_eq!(out["total"].as_u64().unwrap(), 0, "{out}");
        let hint = &out["no_hits"];
        assert!(hint.is_object(), "0 件なのに手がかりが無い: {out}");

        let relax: Vec<(&str, u64)> = hint["relax_one"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| (r["drop"].as_str().unwrap(), r["total"].as_u64().unwrap()))
            .collect();
        // cast_role を外せば翼の出演公演、idol_id を外せば主演公演が出る。
        // どちらも 0 件ではないので、「翼という人がいない」わけでも
        // 「主演という概念が無い」わけでもないことが 1 回で分かる。
        assert!(relax.iter().any(|(d, n)| *d == "cast_role" && *n > 0), "{out}");
        assert!(relax.iter().any(|(d, n)| *d == "idol_id" && *n > 0), "{out}");
        assert_eq!(
            hint["applied"].as_array().unwrap().len(),
            2,
            "効いている軸だけを並べる: {out}"
        );
    }

    #[test]
    fn 型のツールでも空振りに手がかりが付く() {
        let out = call("setlist_shape", json!({ "idol_id": "ml_伊吹翼", "cast_role": "lead" }));
        assert_eq!(out["shows"].as_u64().unwrap(), 0, "{out}");
        assert!(out["no_hits"].is_object(), "{out}");
    }

    #[test]
    fn 主演の歌唱曲数は比較対象と対で返る() {
        let shaped = call("setlist_shape", json!({ "cast_role": "lead" }));
        let lead = &shaped["lead_songs"];
        let member = &shaped["member_songs"];
        assert!(lead.is_object() && member.is_object(), "対で返っていない: {shaped}");
        // 「19 曲」が多いのかは比較対象があって初めて読める。片方だけ返す形にしない。
        assert!(
            lead["min"].as_u64().unwrap() > member["median"].as_u64().unwrap(),
            "主演が他の出演者を上回らない: {shaped}"
        );
    }

    #[test]
    fn 主演の記録が無い集合では主演の欄ごと消える() {
        // ソロ公演のような「出演者表はあるが主演が立っていない」集合。
        let shaped = call("setlist_shape", json!({ "brand": "cg", "cast_role": "member" }));
        assert!(shaped["member_songs"].is_object(), "{shaped}");
        // null を置かずキーごと落とす (この DB の返し方の規約)。0 を返すと
        // 「主演が 0 曲歌った」と読めてしまう。
        assert!(shaped.get("lead_songs").is_none(), "主演の標本が無いのに欄がある: {shaped}");
    }

    #[test]
    fn 曲の位置は合計が披露回数に一致する() {
        // よく歌われる曲を 1 つ選ぶ。
        let top = call("stats", json!({ "kind": "song_play_ranking", "limit": 1 }));
        let song_id = top["items"][0]["id"].as_str().unwrap().to_string();
        let out = call("song_position_profile", json!({ "song_id": song_id }));
        let n = out["performances"].as_u64().unwrap();
        assert!(n > 0, "{out}");
        let p = &out["position"];
        assert_eq!(
            p["early"].as_u64().unwrap() + p["middle"].as_u64().unwrap() + p["late"].as_u64().unwrap(),
            n,
            "{out}"
        );
        assert!(out["closer"].as_u64().unwrap() <= n);
    }

    #[test]
    fn 共起は分母つきで返る() {
        let top = call("stats", json!({ "kind": "song_play_ranking", "limit": 1 }));
        let song_id = top["items"][0]["id"].as_str().unwrap().to_string();
        let out = call("co_performed_songs", json!({ "song_id": song_id, "limit": 5 }));
        let rows = out["co_performed"].as_array().unwrap();
        assert!(!rows.is_empty(), "{out}");
        for row in rows {
            assert!(row["performances"].as_u64() >= row["together"].as_u64(), "{row}");
            assert_ne!(row["id"].as_str().unwrap(), song_id, "自分自身が入っている");
        }
        assert!(out["song_shows"].as_u64().unwrap() > 0, "{out}");
    }

    #[test]
    fn 知らない_id_は_not_found() {
        for (tool, key) in
            [("song_position_profile", "song_id"), ("co_performed_songs", "song_id")]
        {
            let err = call_tool(bundle_snapshot(), tool, &json!({ key: "無い曲" }), TODAY).unwrap_err();
            assert!(matches!(err, ToolError::NotFound(_)), "{tool}: {err}");
        }
        let err =
            call_tool(bundle_snapshot(), "list_shows", &json!({ "idol_id": "無い人" }), TODAY).unwrap_err();
        assert!(matches!(err, ToolError::NotFound(_)), "{err}");
    }
}
