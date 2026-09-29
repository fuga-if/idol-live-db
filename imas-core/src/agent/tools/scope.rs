//! 公演を絞る引数のほどき方。**公演を扱うツールは全部ここを通る。**
//!
//! 絞り込みの規則そのものは `domain::show_list_filtering` が正本で、ここがやるのは
//! 「JSON の引数を条件型に詰める」ことと「語彙外を候補つきで突き返す」ことだけ。
//!
//! 1 箇所にまとめたのは、軸の集合が割れていたから。`stats --kind
//! show_song_count_ranking` は brand / year / venue の 3 軸だけを受け、それ以外を
//! 名指しで拒否する `for axis in [...]` のループを持っていた一方、公演一覧は同じ
//! 引数名でもっと多くの軸を受ける、という状態になりかけていた。同じ `brand` が
//! ツールによって違う意味になるのは、読み手 (LLM) から見ていちばん質の悪い壊れ方。

use super::json::Obj;
use super::vocab::{brand_vocab, cast_role_vocab, checked, event_kind_vocab};
use super::{args, ToolError};
use crate::domain::event_grouping::Timeframe;
use crate::domain::show_list_filtering::{filter_show_indexes, ShowFilterCriteria};
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};

/// 公演の絞り込みに使う引数の名前。スキーマにもここにも同じ配列を使う
/// (「この kind ではこの軸は使えない」の検査もこれを数え上げる)。
pub const SHOW_SCOPE_ARGS: [&str; 10] = [
    "brand",
    "year",
    "venue",
    "event_id",
    "event_kind",
    "idol_id",
    "cast_role",
    "min_cast",
    "max_cast",
    "when",
];

/// 公演の絞り込み軸の JSON Schema。**説明文の正本**。
/// `extra` にツール固有の引数 (`limit` / `top` / `has_setlist`) を足せる。
pub fn show_scope_schema(extra: Value) -> Value {
    let mut props = json!({
        "brand": { "type": "string", "description": "ブランド id (例 ml / cg)。合同ライブは参加ブランドどれでも当たる。" },
        "year": { "type": "integer", "description": "公演日の年。" },
        "venue": { "type": "string", "description": "会場名。読み・旧名でも当たる。" },
        "event_id": { "type": "string", "description": "親イベント (ライブ) の id。" },
        "event_kind": { "type": "string", "description": "親イベントの種別 (live / festival / release_event)。発売記念イベントを外したいときに使う。`stats` の kind (集計の種類) とは別物なので名前を分けてある。" },
        "idol_id": { "type": "string", "description": "その人が出ていた公演だけ。cast_role と併せると役割まで絞れる。" },
        "cast_role": { "type": "string", "description": "出演の役割 (lead = 主演 / member)。idol_id が無ければ「その役割の人がいた公演」。" },
        "min_cast": { "type": "integer", "description": "出演者数の下限。" },
        "max_cast": { "type": "integer", "description": "出演者数の上限。少人数公演を探すときに使う。" },
        "when": { "type": "string", "enum": Timeframe::KEYS, "description": "既定 all。upcoming は近い順、それ以外は新しい順。" }
    });
    if let (Some(base), Some(add)) = (props.as_object_mut(), extra.as_object()) {
        base.extend(add.clone());
    }
    props
}

/// 引数 → 公演の絞り込み条件。語彙外・未知の id はここで突き返す。
///
/// `allow` に載っていない軸が渡されたら `BadArgs`。**黙って無視しない** —
/// 無視すると「絞ったつもりの数」を答えてしまう。
pub fn show_criteria(
    snap: &Snapshot,
    arguments: &Value,
    today_key: &str,
    allow: &[&str],
) -> Result<ShowFilterCriteria, ToolError> {
    for axis in SHOW_SCOPE_ARGS {
        if !allow.contains(&axis) && arguments.get(axis).is_some_and(|v| !v.is_null()) {
            return Err(ToolError::BadArgs(format!(
                "{axis} では絞れない (使える軸: {})",
                allow.join(" / ")
            )));
        }
    }

    let mut c = ShowFilterCriteria { today_key: today_key.to_string(), ..Default::default() };

    if let Some(brand) = args::str_opt(arguments, "brand") {
        c.brand_id = Some(checked("brand", brand, &brand_vocab(snap))?);
    }
    c.year = args::u32_opt(arguments, "year")?.map(|y| y.to_string());
    if let Some(venue) = args::str_opt(arguments, "venue") {
        // 会場は値域が広くて並べられないので、綴り違いは NotFound で返して
        // 名前をほどくツールへ送り返す (list_events の venue と同じ扱い)。
        if crate::domain::event_list_queries::show_indexes_at_venue(snap, &venue).is_empty() {
            return Err(ToolError::NotFound(format!("会場「{venue}」の公演が無い")));
        }
        c.venue = Some(venue);
    }
    if let Some(event_id) = args::str_opt(arguments, "event_id") {
        if !snap.event_index_by_id.contains_key(&event_id) {
            return Err(ToolError::NotFound(format!("ライブ {event_id} が無い")));
        }
        c.event_id = Some(event_id);
    }
    if let Some(kind) = args::str_opt(arguments, "event_kind") {
        c.event_kind = Some(checked("event_kind", kind, &event_kind_vocab(snap))?);
    }
    if let Some(idol_id) = args::str_opt(arguments, "idol_id") {
        c.idol = Some(
            snap.idol_index_by_id
                .get(&idol_id)
                .copied()
                .ok_or_else(|| ToolError::NotFound(format!("アイドル {idol_id} が無い")))?,
        );
    }
    if let Some(role) = args::str_opt(arguments, "cast_role") {
        c.cast_role = Some(checked("cast_role", role, &cast_role_vocab(snap))?);
    }
    c.min_cast = args::u32_opt(arguments, "min_cast")?;
    c.max_cast = args::u32_opt(arguments, "max_cast")?;
    c.has_setlist = args::bool_opt(arguments, "has_setlist")?;

    let raw = args::str_opt(arguments, "when");
    c.when = Timeframe::parse(raw.as_deref()).ok_or_else(|| {
        ToolError::BadArgs(format!("when は {} です", Timeframe::KEYS.join(" / ")))
    })?;
    Ok(c)
}

/// 絞った結果が 0 件だったときに添える手がかり。**どの軸を外せば当たるか**を返す。
///
/// 空配列だけを返すと、呼び手 (LLM) は「そういう公演は無い」と結論して書いてしまう。
/// 実際には「主演の記録がある公演がまだ 8 本しか無い」のように、DB の埋まり方が
/// 原因のことが多い。自由文の空振りには [`super::hints::no_hits`] が手がかりを返すのに、
/// **軸で絞った空振りだけが素通り**していた。
///
/// 軸を 1 つずつ外して件数を測る。2 つ以上外さないと当たらない場合は `relax_one` が
/// 空になり、それ自体が「組み合わせが厳しすぎる」という答えになる。
pub fn narrowing_hint(snap: &Snapshot, c: &ShowFilterCriteria) -> Value {
    /// 名前と外し方だけ。「その軸が効いているか」は外して条件が変わるかで判るので
    /// 別に持たない (別に持つと外し方と食い違ってもコンパイルが通ってしまう)。
    /// `when` と `has_setlist` も入れる (どちらも単独で 0 件を作れる)。
    /// 順序は [`SHOW_SCOPE_ARGS`] に合わせる。
    type Relaxable = (&'static str, fn(&mut ShowFilterCriteria));
    const RELAXABLE: [Relaxable; 11] = [
        ("brand", |c| c.brand_id = None),
        ("year", |c| c.year = None),
        ("venue", |c| c.venue = None),
        ("event_id", |c| c.event_id = None),
        ("event_kind", |c| c.event_kind = None),
        ("idol_id", |c| c.idol = None),
        ("cast_role", |c| c.cast_role = None),
        ("min_cast", |c| c.min_cast = None),
        ("max_cast", |c| c.max_cast = None),
        ("when", |c| c.when = Timeframe::All),
        ("has_setlist", |c| c.has_setlist = None),
    ];

    // 効いている軸 = 外すと条件が変わる軸。外した後の条件はここで 1 度だけ作る。
    let applied: Vec<(&str, ShowFilterCriteria)> = RELAXABLE
        .iter()
        .filter_map(|&(name, clear)| {
            let mut relaxed = c.clone();
            clear(&mut relaxed);
            (relaxed != *c).then_some((name, relaxed))
        })
        .collect();

    let mut o = Obj::new();
    o.put("message", NARROWED_TO_ZERO_MESSAGE);
    o.list("applied", applied.iter().map(|(name, _)| json!(name)).collect());
    o.list(
        "relax_one",
        applied
            .iter()
            .filter_map(|(name, relaxed)| {
                let total = filter_show_indexes(snap, relaxed).len();
                (total > 0).then(|| {
                    let mut r = Obj::new();
                    r.put("drop", json!(name));
                    r.put("total", total);
                    r.value()
                })
            })
            .collect(),
    );
    o.value()
}

/// 軸で絞って 0 件になったときの定型文。[`super::json::NO_HITS_MESSAGE`] (自由文の
/// 空振り) と分けてあるのは、直し方が違うため — あちらは綴り、こちらは条件の強さ。
pub const NARROWED_TO_ZERO_MESSAGE: &str = "この条件に当たる公演は無い。綴りの問題ではなく、条件が強すぎるか、その組み合わせの記録がまだ DB に無いかのどちらか。relax_one は軸を 1 つ外したときの件数で、空なら 2 つ以上外さないと当たらない。";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    const TODAY: &str = "2026-09-19";
    const ALL: [&str; 10] = SHOW_SCOPE_ARGS;

    #[test]
    fn 引数が条件型に詰まる() {
        let c = show_criteria(
            bundle_snapshot(),
            &json!({ "brand": "ml", "year": 2026, "cast_role": "lead", "max_cast": 16, "when": "past" }),
            TODAY,
            &ALL,
        )
        .unwrap();
        assert_eq!(c.brand_id.as_deref(), Some("ml"));
        assert_eq!(c.year.as_deref(), Some("2026"));
        assert_eq!(c.cast_role.as_deref(), Some("lead"));
        assert_eq!(c.max_cast, Some(16));
        assert_eq!(c.when, Timeframe::Past);
        assert_eq!(c.today_key, TODAY);
    }

    #[test]
    fn 使えない軸は黙って無視せず突き返す() {
        let err =
            show_criteria(bundle_snapshot(), &json!({ "cast_role": "lead" }), TODAY, &["brand"]).unwrap_err();
        assert!(matches!(&err, ToolError::BadArgs(m) if m.contains("cast_role")), "{err}");
        // null は「渡していない」と同じ扱い (LLM が省略のつもりで null を書く)。
        assert!(show_criteria(bundle_snapshot(), &json!({ "cast_role": null }), TODAY, &["brand"]).is_ok());
    }

    #[test]
    fn 語彙外と未知の_id_はそれぞれの形で返る() {
        let s = bundle_snapshot();
        assert!(matches!(
            show_criteria(s, &json!({ "brand": "cinderella" }), TODAY, &ALL),
            Err(ToolError::BadArgs(_))
        ));
        assert!(matches!(
            show_criteria(s, &json!({ "idol_id": "無い人" }), TODAY, &ALL),
            Err(ToolError::NotFound(_))
        ));
        assert!(matches!(
            show_criteria(s, &json!({ "event_id": "無いライブ" }), TODAY, &ALL),
            Err(ToolError::NotFound(_))
        ));
        assert!(matches!(
            show_criteria(s, &json!({ "venue": "無い会場" }), TODAY, &ALL),
            Err(ToolError::NotFound(_))
        ));
        assert!(matches!(
            show_criteria(s, &json!({ "when": "future" }), TODAY, &ALL),
            Err(ToolError::BadArgs(_))
        ));
    }
}
