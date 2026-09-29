//! 語をほどく / 1 件の詳細を引くツール群 (resolve・search・get_*・vocabulary)。
//!
//! 規約 (`super` の注記も読むこと):
//! - 1 ツール = 1 `pub fn`。引数の取り出しは `super::args` の補助に寄せる。
//! - 返す JSON は「追加の往復なしに文章が書ける」形まで名前を解決する。id も必ず添える。
//! - 件数は既定の上限を持たせ、打ち切ったことが分かるように `truncated` を返す。
//!
//! ## 打ち切りの書き方
//!
//! 列が 1 本しかない応答 (`resolve`) は最上位に `total` / `truncated`。列が複数ある
//! 応答 (`search` / `get_idol` など) は `<列名>_total` / `<列名>_truncated` を
//! 列の隣に置く。列ごとに別のオブジェクトへ包むより、行の配列が配列のまま読める。
//!
//! ## null は省く / 0 は省かない
//!
//! 値が無い欄は鍵ごと落とす (LLM に読ませるので、`null` の羅列はトークンの無駄)。
//! ただし**件数は 0 でも必ず載せる** — 「披露回数の欄が無い」と「0 回」は別のことで、
//! 落とすと「データが無いから書かない」と「一度も歌われていない」を取り違える。
//!
//! ## 名前で 1 件に決めるとき
//!
//! `name` / `title` で引いて 2 件以上当たったら、**勝手に選ばず** `BadArgs` に候補を
//! 並べて返す。決めてよいのは「表記そのものの一致がちょうど 1 件」のときだけで、
//! その判断は `entity_resolution::resolve_unique` が持つ (ここには書かない)。

use super::json::{brand_ref, joint_brand_refs, Obj};
use super::{args, hints, ToolError, ToolSpec};
use crate::domain::entity_resolution::{
    self as resolution, EntityHit, EntityKind, Resolution,
};
use crate::domain::event_detail_queries as events;
use crate::domain::idol_queries as idols;
use crate::domain::idol_song_queries as idol_songs;
use crate::domain::search_queries;
use crate::domain::setlist_lineup::is_full_cast;
use crate::domain::event_grouping::is_upcoming_on;
use crate::domain::setlist_sections::numbered_setlist;
use crate::domain::snapshot::Snapshot;
use crate::domain::song_detail_queries as songs;
use crate::domain::costume_queries;
use crate::domain::performer_label::song_performer_label as credited_as;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// 一覧の既定件数と上限。LLM が 10000 と書いても上限で丸める (`args::limit`)。
const DEFAULT_LIMIT: u32 = 10;
const MAX_LIMIT: u32 = 50;
/// アイドルの代表曲・曲の関連曲のように「添えもの」の列を何件まで並べるか。
const SIDE_LIST_LIMIT: usize = 10;

/// このファイルが持つツールの定義。
pub fn catalog() -> Vec<ToolSpec> {
    vec![
        spec(
            "resolve",
            "人の言葉 (「デレマス」「春日未来」「横浜アリーナ」) からエンティティ候補を引く。\
             LLM は id を知らないので、get_* を呼ぶ前にまずこれで id を得る。\
             候補には kind / id / name と、選ぶための一言 hint が付く。\
             並びは当たり方の強さ順 (完全一致 → 前方一致 → 部分一致) なので、\
             曲名にも人名にもある語 (「未来」) は曲が上位を占める。\
             探している種別が決まっているなら kinds で絞ること (kind_totals に種別ごとの件数が出る)。",
            super::tool_schema(
                json!({
                    "query": { "type": "string", "description": "探す語。アイドル名・声優名・曲名・ライブ名・会場名など" },
                    "kinds": {
                        "type": "array",
                        "items": { "type": "string", "enum": ["idol", "song", "event", "show", "unit", "brand", "creator", "venue"] },
                        "description": "種別を絞る。省略すると全種別",
                    },
                    "limit": { "type": "integer", "description": "既定 10・上限 50" },
                }),
                &["query"],
            ),
        ),
        spec(
            "search",
            "曲 / アイドル / ライブを横断で検索する。アプリの検索欄と同じ当たり方\
             (大文字小文字と ひらがな↔カタカナを畳む部分一致)。\
             どの種別に何件あるかを一度に知りたいときはこちら、id を 1 つ決めたいときは resolve。",
            super::tool_schema(
                json!({
                    "query": { "type": "string", "description": "検索語" },
                    "limit": { "type": "integer", "description": "種別ごとの件数。既定 10・最大 20。それを超えた分は *_total と *_truncated で分かる" },
                }),
                &["query"],
            ),
        ),
        spec(
            "get_idol",
            "アイドル 1 人の全体像 (プロフィール・CV・所属ユニット・持ち歌と披露曲・ライブ出演)。\
             id か name のどちらかを渡す。name が複数に当たると候補を並べたエラーになる。",
            id_or_name_schema("name", "アイドル名。声優名・別名・ローマ字でも引ける"),
        ),
        spec(
            "get_song",
            "曲 1 曲の全体像 (ブランド・種別・配信日・作家・CD・名義・原唱者・披露履歴・関連曲)。\
             id か title のどちらかを渡す。歌詞本文は扱わない (JASRAC 作品コードの有無まで)。",
            id_or_name_schema("title", "曲名。読み (かな) でも引ける"),
        ),
        spec(
            "get_event",
            "ライブ 1 本 (ブランド・種別・公演一覧)。id か name のどちらかを渡す。\
             セットリストが要るときは公演 (show) を選んで get_show を呼ぶ。",
            id_or_name_schema("name", "ライブ名"),
        ),
        spec(
            "get_show",
            "公演 1 本のセットリスト全文 (曲順・セクション・歌唱者・出演者)。\
             id が要る (resolve の kind=show か get_event で得る)。",
            super::tool_schema(json!({ "id": { "type": "string", "description": "公演 id" } }), &["id"]),
        ),
        spec(
            "vocabulary",
            "この DB の語彙と規模 (ブランド一覧・song_type と event kind の取りうる値・\
             各表の件数・データ版・収録しているライブの日付範囲)。引数なし。\
             ブランド id・song_type・event kind の取りうる値や、収録範囲が分からないときに引く。",
            super::tool_schema(json!({}), &[]),
        ),
    ]
}

/// 自分の持ちツールなら `Some(結果)`、違うなら `None` (呼び手が次を試す)。
pub fn call(
    snap: &Snapshot,
    name: &str,
    args: &Value,
    today_key: &str,
) -> Option<Result<Value, ToolError>> {
    Some(match name {
        "resolve" => resolve(snap, args),
        "search" => search(snap, args),
        "get_idol" => get_idol(snap, args),
        "get_song" => get_song(snap, args),
        "get_event" => get_event(snap, args),
        "get_show" => get_show(snap, args),
        "vocabulary" => vocabulary(snap, today_key),
        _ => return None,
    })
}

// ---------------------------------------------------------------------------
// resolve
// ---------------------------------------------------------------------------

fn resolve(snap: &Snapshot, args: &Value) -> Result<Value, ToolError> {
    let query = args::str_req(args, "query")?;
    let kinds = parse_kinds(args)?;
    let limit = args::limit(args, DEFAULT_LIMIT, MAX_LIMIT)?;
    let found = resolution::resolve_with_total(snap, &query, &kinds, limit);

    let mut out = Obj::new();
    out.put("total", found.total);
    if found.total as usize > found.hits.len() {
        out.put("truncated", true);
    }
    // 種別ごとの件数。候補の並びは当たり方の強さ順なので、打ち切ると種別ごと
    // 見えなくなることがある (「未来」で上位 5 件が全部曲名になり、春日未来 が
    // 6 番目に落ちる)。件数が見えていれば kinds で絞り直せる。
    if found.by_kind.len() > 1 {
        let mut counts = Obj::new();
        for (kind, n) in &found.by_kind {
            counts.put(kind.as_str(), *n);
        }
        out.put("kind_totals", counts.value());
    }
    out.put("candidates", Value::Array(found.hits.iter().map(hit_json).collect()));
    // 0 件を素通りさせない。「当たらなかった」だけだと LLM は
    // 「その語は DB に無い」と書いてしまう。
    if found.total == 0 {
        out.put("no_hits", hints::no_hits(snap, &query, &kinds));
    }
    out.put("query", query);
    Ok(out.value())
}

fn hit_json(hit: &EntityHit) -> Value {
    let mut o = Obj::new();
    o.put("kind", hit.kind.as_str());
    o.put("id", hit.id.as_str());
    o.put("name", hit.name.as_str());
    o.opt("hint", non_blank(&hit.hint));
    if hit.exact {
        o.put("exact", true);
    }
    o.value()
}

fn parse_kinds(args: &Value) -> Result<Vec<EntityKind>, ToolError> {
    args::str_list(args, "kinds")
        .iter()
        .map(|k| {
            EntityKind::parse(k).ok_or_else(|| {
                let known: Vec<&str> = EntityKind::ALL.iter().map(|k| k.as_str()).collect();
                ToolError::BadArgs(format!("kinds に知らない種別: {k} (使えるのは {})", known.join(" / ")))
            })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// search
// ---------------------------------------------------------------------------

fn search(snap: &Snapshot, args: &Value) -> Result<Value, ToolError> {
    let query = args::str_req(args, "query")?;
    let limit = args::limit(args, DEFAULT_LIMIT, MAX_LIMIT)? as usize;
    // 当たり方も件数も画面の検索と同じ関数を通す (照合規則をここに書かない)。
    let hits = search_queries::global_search(snap, &query);
    let counts = search_queries::search_counts(snap, &query);

    let mut out = Obj::new();
    if counts.songs + counts.idols + counts.events == 0 {
        out.put("no_hits", hints::no_hits(snap, &query, &[]));
    }
    out.put("query", query);
    out.capped(
        "songs",
        hits.song_ids.iter().take(limit).filter_map(|id| song_brief(snap, id)).collect(),
        counts.songs as usize,
    );
    out.capped(
        "idols",
        hits.idol_ids.iter().take(limit).filter_map(|id| idol_brief(snap, id)).collect(),
        counts.idols as usize,
    );
    out.capped(
        "events",
        hits.event_ids.iter().take(limit).filter_map(|id| event_brief(snap, id)).collect(),
        counts.events as usize,
    );
    Ok(out.value())
}

// ---------------------------------------------------------------------------
// get_idol
// ---------------------------------------------------------------------------

fn get_idol(snap: &Snapshot, args: &Value) -> Result<Value, ToolError> {
    let id = pick(snap, args, EntityKind::Idol, "name")?;
    let ii = snap.idol_index_by_id[&id];
    let idol = &snap.idols[ii as usize];

    let mut o = Obj::new();
    o.put("id", idol.id.as_str());
    o.put("name", idol.name.as_str());
    o.opt("name_kana", idol.name_kana.as_deref());
    o.opt("name_romaji", idol.name_romaji.as_deref());
    o.opt("aliases", idol.aliases.as_deref());
    o.opt("brand", brand_ref(snap, idol.brand_id.as_deref()));
    // 多重所属 (ゲスト出演で別ブランドに紐づく人) は brand 1 つでは書けない。
    o.list(
        "brands",
        snap.brands_by_idol[ii as usize]
            .iter()
            .filter_map(|link| brand_ref(snap, Some(&snap.brands[link.brand as usize].id)))
            .collect(),
    );
    o.opt("birthday", idols::birthday_display(idol.birthday.as_deref()));
    o.opt("birthday_raw", idol.birthday.as_deref());
    o.opt("constellation", idol.constellation.as_deref());
    o.opt("blood_type", idol.blood_type.as_deref());
    o.opt("age", idol.age);
    o.opt("height", idols::height_display(idol.height));
    o.opt("weight", idol.weight.map(|w| w as i64));
    o.opt("birth_place", idol.birth_place.as_deref());
    o.opt("hobbies", idol.hobbies.as_deref());
    o.opt("talents", idol.talents.as_deref());
    o.opt("handedness", idol.handedness.as_deref());
    o.opt("attribute", idol.attribute.as_deref());
    o.opt("description", idol.description.as_deref());
    if idol.is_external {
        // 外部ゲスト (アイマス外からの出演者)。ブランド所属とは別の札。
        o.put("is_external", true);
    }

    o.opt("voice_actor", snap.current_voice_actor(ii).map(|va| va.name.clone()));
    let history = idols::voice_actor_history(snap, &id);
    // 歴代が 1 人だけなら voice_actor と同じことしか書いていない。
    if history.len() > 1 {
        o.put(
            "voice_actor_history",
            Value::Array(
                history
                    .iter()
                    .map(|va| {
                        let mut h = Obj::new();
                        h.put("name", va.name.as_str());
                        h.opt("valid_from", va.valid_from.as_deref());
                        h.opt("valid_to", va.valid_to.as_deref());
                        h.value()
                    })
                    .collect(),
            ),
        );
    }

    o.list(
        "units",
        idols::idol_units(snap, &id)
            .iter()
            .map(|u| {
                let mut x = Obj::new();
                x.put("id", u.id.as_str());
                x.put("name", u.name.as_str());
                x.put("is_permanent", u.is_permanent);
                x.value()
            })
            .collect(),
    );

    // 「持ち歌」(原唱) と「ライブで歌った曲」は別物。両方の件数を出す。
    o.put("original_song_count", idol_songs::idol_songs(snap, &id, Some("original")).len());
    let performed = idol_songs::idol_performed_songs(snap, &id);
    o.put("performed_song_count", performed.len());
    o.capped(
        "top_performed_songs",
        performed
            .iter()
            .take(SIDE_LIST_LIMIT)
            .map(|s| {
                let mut x = Obj::new();
                x.put("id", s.song_id.as_str());
                x.put("title", s.title.as_str());
                x.put("performed_count", s.perform_count);
                x.value()
            })
            .collect(),
        performed.len(),
    );

    // 出演公演は date DESC。最初 = 最新、最後 = 初出演。
    let shows = idols::idol_shows(snap, &id);
    o.put("show_count", shows.len());
    o.opt("first_show", shows.last().map(idol_show_json));
    o.opt("latest_show", shows.first().map(idol_show_json));
    Ok(o.value())
}

fn idol_show_json(s: &idols::IdolShowRecord) -> Value {
    let mut x = Obj::new();
    x.put("show_id", s.show_id.as_str());
    x.put("date", s.date.as_str());
    x.put("event_id", s.event_id.as_str());
    x.put("event_name", s.event_name.as_str());
    x.opt("show_name", non_blank(&s.show_name));
    x.opt("venue", s.venue.as_deref());
    x.value()
}

// ---------------------------------------------------------------------------
// get_song
// ---------------------------------------------------------------------------

fn get_song(snap: &Snapshot, args: &Value) -> Result<Value, ToolError> {
    let id = pick(snap, args, EntityKind::Song, "title")?;
    let si = snap.song_index_by_id[&id];
    let song = &snap.songs[si as usize];

    let mut o = Obj::new();
    o.put("id", song.id.as_str());
    o.put("title", song.title.as_str());
    o.opt("title_kana", song.title_kana.as_deref());
    o.opt("brand", brand_ref(snap, song.brand_id.as_deref()));
    o.list("joint_brands", joint_brand_refs(snap, song.joint_brand_ids.as_deref()));
    if song.is_collab {
        o.put("is_collab", true);
    }
    o.opt("song_type", song.song_type.as_deref());
    o.opt("release_date", song.release_date.as_deref());
    o.opt("duration_sec", song.duration_sec);
    o.opt("duration", song.duration_sec.map(minutes_seconds));
    o.opt("lyricist", song.lyricist.as_deref());
    o.opt("composer", song.composer.as_deref());
    o.opt("arranger", song.arranger.as_deref());
    o.opt("cd_title", song.cd_title.as_deref());
    o.opt("cd_series", song.cd_series.as_deref());
    o.opt("series_group", song.series_group.as_deref());
    // 名義は unit_name / singer_label の生値と、規則 (performer_label) の答えの両方。
    o.opt("unit_name", song.unit_name.as_deref());
    o.opt("singer_label", song.singer_label.as_deref());
    o.opt("credited_as", credited_as(snap, si));
    o.opt(
        "unit",
        song.unit_id.as_deref().and_then(|uid| snap.unit(uid)).map(|u| {
            let mut x = Obj::new();
            x.put("id", u.id.as_str());
            x.put("name", u.name.as_str());
            x.value()
        }),
    );
    o.list(
        "original_artists",
        snap.song_artists(&id, Some("original"))
            .iter()
            .map(|idol| {
                let mut x = Obj::new();
                x.put("id", idol.id.as_str());
                x.put("name", idol.name.as_str());
                x.value()
            })
            .collect(),
    );

    // 披露は 0 回にも意味がある (音源だけの曲か、ライブで歌われた曲か)。
    let history = songs::performance_history(snap, &id);
    o.put("performance_count", snap.performance_counts[si as usize]);
    o.opt("first_performance", history.last().map(performance_json));
    o.opt("latest_performance", history.first().map(performance_json));

    o.list(
        "related_songs",
        songs::related_songs(snap, &id, SIDE_LIST_LIMIT as u32)
            .iter()
            .map(|s| {
                let mut x = Obj::new();
                x.put("id", s.id.as_str());
                x.put("title", s.title.as_str());
                x.opt("brand_id", s.brand_id.as_deref());
                x.value()
            })
            .collect(),
    );

    o.put("has_kamisabi_card", song.has_kamisabi_card);
    o.opt("note", song.note.as_deref());
    // 歌詞本文はここから返さない (JASRAC の許諾が「D1 に置きダウンロードさせない」形)。
    // 作品コードの有無までが扱える範囲。
    o.put("has_jasrac_code", song.jasrac_code.is_some());
    o.opt("jasrac_code", song.jasrac_code.as_deref());
    Ok(o.value())
}

fn performance_json(p: &songs::PerformanceHistoryEntry) -> Value {
    let mut x = Obj::new();
    x.put("show_id", p.show_id.as_str());
    x.put("date", p.date.as_str());
    x.put("event_id", p.event_id.as_str());
    x.put("event_name", p.event_name.as_str());
    x.opt("show_name", non_blank(&p.show_name));
    x.opt("venue", p.venue.as_deref());
    x.put("ordinal", p.ordinal);
    x.value()
}

// ---------------------------------------------------------------------------
// get_event
// ---------------------------------------------------------------------------

fn get_event(snap: &Snapshot, args: &Value) -> Result<Value, ToolError> {
    let id = pick(snap, args, EntityKind::Event, "name")?;
    let ei = snap.event_index_by_id[&id];
    let event = &snap.events[ei as usize];

    let mut o = Obj::new();
    o.put("id", event.id.as_str());
    o.put("name", event.name.as_str());
    o.put("kind", event.kind.as_str());
    o.put("event_type", event.event_type.as_str());
    o.opt("brand", brand_ref(snap, event.brand_id.as_deref()));
    o.list("joint_brands", joint_brand_refs(snap, event.joint_brand_ids.as_deref()));
    o.put("is_solo", event.is_solo);
    o.put("is_streaming", event.is_streaming);
    if let Some((first, last)) = resolution::event_date_range(snap, ei) {
        o.put("first_date", first);
        o.put("last_date", last);
    }

    let stats = events::event_stats(snap, &id);
    o.put("show_count", stats.show_count);
    o.put("total_songs", stats.total_songs);
    o.put("unique_songs", stats.unique_songs);
    o.put("cast_count", stats.cast_count);

    o.put(
        "shows",
        Value::Array(
            snap.shows_by_event[ei as usize]
                .iter()
                .map(|&s| {
                    let show = &snap.shows[s as usize];
                    let mut x = Obj::new();
                    x.put("id", show.id.as_str());
                    x.opt("name", non_blank(&show.name));
                    x.put("date", show.date.as_str());
                    x.opt("venue", show.venue.as_deref());
                    x.opt("hall", show.hall.as_deref());
                    x.opt("start_time", show.start_time.as_deref());
                    // 0 は「セトリ未入力」を意味する (未来公演に多い)。落とさない。
                    x.put("setlist_song_count", snap.setlist_items_by_show[s as usize].len());
                    x.put("performer_count", events::show_presence(snap, s).len());
                    x.value()
                })
                .collect(),
        ),
    );
    Ok(o.value())
}

// ---------------------------------------------------------------------------
// get_show
// ---------------------------------------------------------------------------

fn get_show(snap: &Snapshot, args: &Value) -> Result<Value, ToolError> {
    let id = pick(snap, args, EntityKind::Show, "name")?;
    let si = snap.show_index_by_id[&id];
    let show = &snap.shows[si as usize];
    let event = &snap.events[show.event as usize];

    let mut o = Obj::new();
    o.put("id", show.id.as_str());
    o.opt("name", non_blank(&show.name));
    o.put("date", show.date.as_str());
    o.opt("venue", show.venue.as_deref());
    o.opt("hall", show.hall.as_deref());
    o.opt("venue_city", show.venue_city.as_deref());
    o.opt("start_time", show.start_time.as_deref());
    o.put("event", {
        let mut x = Obj::new();
        x.put("id", event.id.as_str());
        x.put("name", event.name.as_str());
        x.put("kind", event.kind.as_str());
        x.value()
    });

    // 「誰がいたか」の定義は show_presence (出演者表 ∪ 歌唱メンバー) が正本。
    // 出演者表が未入力で歌唱だけ入っている公演があるため、片方だけでは足りない。
    let cast_indexes = events::show_presence(snap, si);
    let cast_ids: BTreeSet<&str> =
        cast_indexes.iter().map(|&i| snap.idols[i as usize].id.as_str()).collect();
    o.put("cast_count", cast_indexes.len());
    o.put(
        "cast",
        Value::Array(
            cast_indexes
                .iter()
                .map(|&i| {
                    let idol = &snap.idols[i as usize];
                    let mut x = Obj::new();
                    x.put("id", idol.id.as_str());
                    x.put("name", idol.name.as_str());
                    x.opt("voice_actor", snap.current_voice_actor(i).map(|va| va.name.clone()));
                    x.opt("cast_role", snap.show_cast_role(si, i));
                    x.value()
                })
                .collect(),
        ),
    );

    let items = &snap.setlist_items_by_show[si as usize];
    o.put("setlist_song_count", items.len());
    o.put(
        "setlist",
        Value::Array(
            numbered_setlist(snap, si)
                .map(|(rank, i)| setlist_row(snap, i, rank, &cast_ids))
                .collect(),
        ),
    );
    Ok(o.value())
}

/// セトリ 1 行。`position` は**公演内の何曲目か** (1 始まり)。
///
/// 曲順の出し方は [`crate::domain::setlist_sections::numbered_setlist`] が正本
/// (生の `setlist_items.position` は公演をまたいだ通し番号で、そのまま読むと
/// 「7723 曲目」になる)。ここは呼び手が数えた番号を受け取るだけ。
fn setlist_row(
    snap: &Snapshot,
    item_index: u32,
    position: usize,
    cast_ids: &BTreeSet<&str>,
) -> Value {
    let item = &snap.setlist_items[item_index as usize];
    let song = &snap.songs[item.song as usize];
    let performers = &snap.performers_by_item[item_index as usize];
    let performer_ids: BTreeSet<&str> =
        performers.iter().map(|&i| snap.idols[i as usize].id.as_str()).collect();

    let mut x = Obj::new();
    x.put("id", item.id.as_str());
    x.put("position", position);
    x.opt("section", item.section.as_deref());
    x.put("song_id", song.id.as_str());
    x.put("title", song.title.as_str());
    x.opt("notes", item.notes.as_deref());
    x.opt("unit_name", item.unit_name.as_deref());
    x.put("performer_count", performers.len());
    // 出演者全員で歌う行は名前を並べ直さない (同じ応答の `cast` にそのまま載っている)。
    // 「全員」の判定は setlist_lineup が正本。**札を `performers` に混ぜない** —
    // 同じ鍵が配列だったり文字列だったりすると、読む側が型で分岐する羽目になる。
    if is_full_cast(cast_ids, &performer_ids) {
        x.put("full_cast", true);
    } else {
        x.list(
            "performers",
            performers
                .iter()
                .map(|&i| Value::String(snap.idols[i as usize].name.clone()))
                .collect(),
        );
    }
    x.list(
        "costumes",
        costume_queries::setlist_item_costumes(snap, &item.id)
            .iter()
            .map(|c| Value::String(c.chip_label.clone()))
            .collect(),
    );
    x.value()
}

// ---------------------------------------------------------------------------
// vocabulary
// ---------------------------------------------------------------------------

fn vocabulary(snap: &Snapshot, today_key: &str) -> Result<Value, ToolError> {
    let mut o = Obj::new();
    o.opt("data_version", snap.meta_value("data_version"));
    o.put("today", today_key);

    o.put(
        "brands",
        Value::Array(
            snap.brand_order
                .iter()
                .map(|&b| {
                    let brand = &snap.brands[b as usize];
                    // 形は brand_ref (全ツール共通) に揃え、ここは所属人数だけ足す。
                    let mut x = brand_ref(snap, Some(&brand.id)).unwrap_or_else(|| Value::Object(Default::default()));
                    if let Value::Object(map) = &mut x {
                        map.insert("idol_count".into(), snap.idols_by_brand[b as usize].len().into());
                    }
                    x
                })
                .collect(),
        ),
    );

    // 語彙はデータから数える。ここに定数表を置くと、DB に新しい値が入った日に嘘になる。
    o.put("song_type", tally(snap.songs.iter().map(|s| s.song_type.as_deref())));
    o.put("event_kind", tally(snap.events.iter().map(|e| Some(e.kind.as_str()))));
    o.put("event_type", tally(snap.events.iter().map(|e| Some(e.event_type.as_str()))));

    let mut counts = Obj::new();
    counts.put("songs", snap.songs.len());
    counts.put("idols", snap.idols.len());
    counts.put("units", snap.units.len());
    counts.put("events", snap.events.len());
    counts.put("shows", snap.shows.len());
    counts.put("setlist_items", snap.setlist_items.len());
    counts.put("venues", snap.venues.len());
    counts.put("creators", snap.creators.len());
    counts.put("costumes", snap.costumes.len());
    o.put("counts", counts.value());

    let dates = &snap.shows_in_date_order;
    if let (Some(&first), Some(&last)) = (dates.first(), dates.last()) {
        let mut range = Obj::new();
        range.put("first", snap.shows[first as usize].date.as_str());
        range.put("last", snap.shows[last as usize].date.as_str());
        // 末尾は発表済みの未来公演まで含む。「今日まで」と読み違えないよう分けて出す。
        // 「今後」の判断は event_grouping が正本 (部分日付は精度を揃えて比べる)。
        // ここで `date < today_key` と書き直すと、日程未定の年だけ決まった公演を
        // 開催済み側に数える。
        range.put(
            "upcoming",
            dates
                .iter()
                .filter(|&&s| is_upcoming_on(&snap.shows[s as usize].date, today_key))
                .count(),
        );
        o.put("show_date_range", range.value());
    }

    o.put(
        "notes",
        Value::Array(vec![
            Value::String(
                "歌詞本文は扱わない。JASRAC の許諾が「D1 に置きダウンロードさせない」形なので、\
                 返せるのは作品コードと掲載の有無まで。"
                    .into(),
            ),
            Value::String(
                "「披露回数」はこの DB に載っているセットリストの範囲での回数。\
                 セトリ未入力の公演があるので、実際の回数の下限として読むこと。"
                    .into(),
            ),
            Value::String(
                "brand_id='other' は「その他」ブランドで、アイマス外のゲストという意味ではない\
                 (外部ゲストは is_external)。"
                    .into(),
            ),
        ]),
    );
    Ok(o.value())
}

/// 取りうる値と件数を多い順に。値が無い行は `null` を数えず `unset` に寄せる。
fn tally<'a>(values: impl Iterator<Item = Option<&'a str>>) -> Value {
    let mut counts: BTreeMap<&str, u32> = BTreeMap::new();
    let mut unset = 0u32;
    for value in values {
        match value.filter(|v| !v.is_empty()) {
            Some(v) => *counts.entry(v).or_insert(0) += 1,
            None => unset += 1,
        }
    }
    let mut rows: Vec<(&str, u32)> = counts.into_iter().collect();
    rows.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
    let mut items: Vec<Value> = rows
        .into_iter()
        .map(|(value, count)| {
            let mut x = Obj::new();
            x.put("value", value);
            x.put("count", count);
            x.value()
        })
        .collect();
    if unset > 0 {
        let mut x = Obj::new();
        x.put("value", Value::Null);
        x.put("count", unset);
        items.push(x.value());
    }
    Value::Array(items)
}

// ---------------------------------------------------------------------------
// 共通 (id / name の受け方、短い行、JSON の組み立て)
// ---------------------------------------------------------------------------

/// `id` か `name` (曲は `title`) のどちらかから 1 件に決める。
fn pick(
    snap: &Snapshot,
    args: &Value,
    kind: EntityKind,
    name_key: &str,
) -> Result<String, ToolError> {
    if let Some(id) = args::str_opt(args, "id") {
        return exists(snap, kind, &id)
            .then_some(id.clone())
            .ok_or_else(|| ToolError::NotFound(format!("{} の id が無い: {id}", kind.as_str())));
    }
    let Some(name) = args::str_opt(args, name_key) else {
        return Err(ToolError::BadArgs(format!("id か {name_key} のどちらかが要ります")));
    };
    match resolution::resolve_unique(snap, &name, kind) {
        Resolution::One(hit) => Ok(hit.id),
        Resolution::Nothing => {
            Err(ToolError::NotFound(format!("「{name}」に当たる {} がありません", kind.as_str())))
        }
        Resolution::Many(hits) => {
            let listed = hits
                .iter()
                .map(|h| {
                    if h.hint.is_empty() {
                        format!("{} ({})", h.name, h.id)
                    } else {
                        format!("{} ({}, {})", h.name, h.id, h.hint)
                    }
                })
                .collect::<Vec<_>>()
                .join(" / ");
            Err(ToolError::BadArgs(format!(
                "「{name}」は複数に当たります。id を選んで渡し直してください (resolve でも絞れます): {listed}"
            )))
        }
    }
}

fn exists(snap: &Snapshot, kind: EntityKind, id: &str) -> bool {
    match kind {
        EntityKind::Idol => snap.idol(id).is_some(),
        EntityKind::Song => snap.song(id).is_some(),
        EntityKind::Event => snap.event(id).is_some(),
        EntityKind::Show => snap.show(id).is_some(),
        EntityKind::Unit => snap.unit(id).is_some(),
        EntityKind::Brand => snap.brand(id).is_some(),
        EntityKind::Venue => snap.venue(id).is_some(),
        EntityKind::Creator => snap.creators.iter().any(|c| c.id == id),
    }
}

fn song_brief(snap: &Snapshot, id: &str) -> Option<Value> {
    let &si = snap.song_index_by_id.get(id)?;
    let song = &snap.songs[si as usize];
    let mut x = Obj::new();
    x.put("id", song.id.as_str());
    x.put("title", song.title.as_str());
    x.opt("brand_id", song.brand_id.as_deref());
    x.opt("song_type", song.song_type.as_deref());
    x.opt("release_date", song.release_date.as_deref());
    x.opt("credited_as", credited_as(snap, si));
    x.put("performance_count", snap.performance_counts[si as usize]);
    Some(x.value())
}

fn idol_brief(snap: &Snapshot, id: &str) -> Option<Value> {
    let &ii = snap.idol_index_by_id.get(id)?;
    let idol = &snap.idols[ii as usize];
    let mut x = Obj::new();
    x.put("id", idol.id.as_str());
    x.put("name", idol.name.as_str());
    x.opt("brand_id", idol.brand_id.as_deref());
    x.opt("voice_actor", snap.current_voice_actor(ii).map(|va| va.name.clone()));
    Some(x.value())
}

fn event_brief(snap: &Snapshot, id: &str) -> Option<Value> {
    let &ei = snap.event_index_by_id.get(id)?;
    let event = &snap.events[ei as usize];
    let mut x = Obj::new();
    x.put("id", event.id.as_str());
    x.put("name", event.name.as_str());
    x.put("kind", event.kind.as_str());
    x.opt("brand_id", event.brand_id.as_deref());
    if let Some((first, last)) = resolution::event_date_range(snap, ei) {
        x.put("first_date", first);
        x.put("last_date", last);
    }
    x.put("show_count", snap.shows_by_event[ei as usize].len());
    Some(x.value())
}

/// 秒を `"4:32"` に。生の秒も別鍵で残すので、こちらは読みやすさのためだけ。
fn minutes_seconds(seconds: i64) -> String {
    format!("{}:{:02}", seconds / 60, seconds % 60)
}

fn non_blank(text: &str) -> Option<&str> {
    (!text.trim().is_empty()).then_some(text)
}

fn spec(name: &str, description: &str, input_schema: Value) -> ToolSpec {
    ToolSpec {
        name: name.to_string(),
        description: description.to_string(),
        input_schema,
    }
}

/// `id` と名前のどちらでも受けるツールのスキーマ。どちらも必須にしない
/// (両方必須にすると id を知っている呼び手が名前を捏造する)。
///
/// **以前は `format!` で JSON 文字列を直接組んでいた** (RedTeam 指摘)。`name_doc` に
/// `"` や改行が 1 つ入っただけで不正な JSON になり、`agent::mcp` の `tools/list` が
/// パースに失敗してこのツールを一覧から黙って落としていた (`dispatch` は名前で直接
/// 受け付けるので CLI では動き続け、誰も気づけない形だった)。`serde_json::json!` 経由で
/// 組めば、エスケープは serde_json に任せられるのでこの種の壊れ方がそもそも起こらない。
fn id_or_name_schema(name_key: &str, name_doc: &str) -> Value {
    let mut properties = serde_json::Map::new();
    properties.insert(
        "id".to_string(),
        json!({ "type": "string", "description": "id が分かっているときはこちら" }),
    );
    properties.insert(name_key.to_string(), json!({ "type": "string", "description": name_doc }));

    // `required: []` (誰も必須にしない) と `anyOf` (id か name_key のどちらかは要る) は
    // 共存できる。実際の制約は anyOf 側が持つ。
    let mut schema = super::tool_schema(Value::Object(properties), &[]);
    schema["anyOf"] = json!([{ "required": ["id"] }, { "required": [name_key] }]);
    schema
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;
    use crate::agent::tools::call_tool;
    use serde_json::json;

    const TODAY: &str = "2026-09-19";

    fn run(name: &str, args: Value) -> Value {
        call_tool(bundle_snapshot(), name, &args, TODAY).unwrap_or_else(|e| panic!("{name}: {e}"))
    }

    fn err(name: &str, args: Value) -> ToolError {
        call_tool(bundle_snapshot(), name, &args, TODAY).unwrap_err()
    }

    fn text(v: &Value, key: &str) -> String {
        v.get(key).and_then(Value::as_str).unwrap_or_else(|| panic!("{key} が無い: {v}")).to_string()
    }

    /// `id_or_name_schema` が以前 `format!` で JSON 文字列を組んでいたときの回帰確認。
    /// 説明文に `"` や改行が入っても (実際の呼び出しは全部固定文字列だが、将来ここを
    /// 動的な文言に変えても) 壊れた JSON を作らないことを固定する。
    #[test]
    fn id_or_name_schema_は特殊文字を含む説明でも妥当な_json_を組む() {
        let schema = id_or_name_schema("name", "改行\nと \"引用符\" を含む説明");
        assert_eq!(schema["type"], "object");
        assert_eq!(schema["additionalProperties"], Value::Bool(false));
        assert!(schema["properties"]["name"]["description"]
            .as_str()
            .unwrap()
            .contains('"'));
        assert_eq!(
            schema["anyOf"],
            json!([{ "required": ["id"] }, { "required": ["name"] }])
        );
    }

    /// 返った JSON だけで「春日未来は何者か」が書けること。
    #[test]
    fn get_idol_は1回で人物紹介が書ける() {
        let v = run("get_idol", json!({"name": "春日未来"}));
        assert_eq!(text(&v, "id"), "ml_春日未来");
        assert_eq!(text(&v, "name"), "春日未来");
        assert_eq!(v["brand"]["short_name"], "ミリオン");
        assert!(!text(&v, "voice_actor").is_empty());
        assert!(v.get("birthday").is_some(), "誕生日が要る: {v}");
        assert!(!v["units"].as_array().unwrap().is_empty(), "所属ユニット: {v}");
        assert!(v["original_song_count"].as_u64().unwrap() > 0);
        assert!(v["performed_song_count"].as_u64().unwrap() > 0);
        let top = &v["top_performed_songs"].as_array().unwrap()[0];
        assert!(top["performed_count"].as_u64().unwrap() > 0);
        assert!(v["show_count"].as_u64().unwrap() > 0);
        assert!(v["first_show"]["date"].as_str().unwrap() < v["latest_show"]["date"].as_str().unwrap());
        // null は鍵ごと落ちている。
        assert!(v.as_object().unwrap().values().all(|x| !x.is_null()));
    }

    #[test]
    fn get_song_は名義と原唱者と披露履歴を返す() {
        let v = run("get_song", json!({"title": "THE IDOLM@STER"}));
        assert_eq!(text(&v, "id"), "765as_the_idolmster");
        assert_eq!(v["brand"]["id"], "765as");
        assert_eq!(text(&v, "song_type"), "all");
        assert!(v["original_artists"].as_array().unwrap().len() > 1);
        assert!(v["performance_count"].as_u64().unwrap() > 0);
        let first = &v["first_performance"];
        let latest = &v["latest_performance"];
        assert_eq!(first["ordinal"], 1, "初披露は 1 回目: {first}");
        assert!(first["date"].as_str().unwrap() <= latest["date"].as_str().unwrap());
        assert!(!first["event_name"].as_str().unwrap().is_empty());
        // 歌詞は扱わない。作品コードの有無までしか出さない。
        assert!(v["has_jasrac_code"].is_boolean());
        assert!(v.get("lyrics").is_none());
        assert!(v["has_kamisabi_card"].is_boolean());
    }

    #[test]
    fn get_event_は公演一覧を日付つきで返す() {
        let v = run(
            "get_event",
            json!({"id": "ev_the_idolmster_million_live_10thlive_tour_act-1_hppy_4_you"}),
        );
        assert!(text(&v, "name").contains("10thLIVE"));
        assert_eq!(text(&v, "kind"), "live");
        assert_eq!(v["brand"]["id"], "ml");
        let shows = v["shows"].as_array().unwrap();
        assert!(!shows.is_empty());
        assert_eq!(v["show_count"].as_u64().unwrap() as usize, shows.len());
        for show in shows {
            assert_eq!(show["date"].as_str().unwrap().len(), 10, "YYYY-MM-DD: {show}");
            assert!(show["setlist_song_count"].is_number());
            assert!(show["performer_count"].is_number());
        }
        assert!(v["unique_songs"].as_u64().unwrap() > 0);
    }

    #[test]
    fn get_show_はセトリ全文を歌唱者つきで返す() {
        let event = run(
            "get_event",
            json!({"id": "ev_the_idolmster_million_live_10thlive_tour_act-1_hppy_4_you"}),
        );
        let show_id = event["shows"][0]["id"].as_str().unwrap().to_string();
        let v = run("get_show", json!({"id": show_id}));

        assert_eq!(text(&v, "id"), show_id);
        assert!(v["event"]["name"].as_str().unwrap().contains("MILLION LIVE"));
        assert!(v["cast"].as_array().unwrap().len() > 1);
        let setlist = v["setlist"].as_array().unwrap();
        assert!(!setlist.is_empty(), "セトリが空: {v}");
        // 曲順は 1 始まりの連番 = そのまま「N 曲目」と書ける
        // (生の setlist_items.position は公演をまたぐ通し番号で 4 桁になる)。
        let mut expected = 0i64;
        for row in setlist {
            expected += 1;
            assert_eq!(row["position"].as_i64().unwrap(), expected, "曲順が通し番号のまま: {row}");
            assert!(!row["title"].as_str().unwrap().is_empty());
            assert!(row["song_id"].as_str().unwrap().starts_with(|c: char| c.is_ascii_alphanumeric() || c.is_alphabetic()));
        }
        // 歌唱者は「名前の配列」か「全員 (full_cast)」のどちらか。鍵ごとに型が揺れない。
        assert!(setlist.iter().any(|r| r.get("performers").is_some()), "歌唱者がどこにも無い");
        assert!(setlist.iter().any(|r| r["full_cast"] == true), "全員で歌う行がまとまっていない");
        for row in setlist {
            if let Some(performers) = row.get("performers") {
                assert!(performers.is_array(), "performers は常に配列: {row}");
                assert!(row.get("full_cast").is_none(), "全員の行に名前も並べている: {row}");
            }
        }
    }

    #[test]
    fn 上位から押し出された種別も件数で見える() {
        // 「未来」は曲名の前方一致 (未来飛行) が人名の部分一致 (春日未来) に勝つので、
        // 上位 5 件に人が 1 人も出ない。並びの規則自体は筋が通っているので変えないが、
        // **当たっているのに見えない**まま返すと LLM は「そんな人はいない」と書く。
        let v = run("resolve", json!({ "query": "未来", "limit": 5 }));
        let kinds: Vec<&str> =
            v["candidates"].as_array().unwrap().iter().map(|c| c["kind"].as_str().unwrap()).collect();
        assert!(!kinds.contains(&"idol"), "前提が変わった (アイドルが上位に出ている): {kinds:?}");
        assert!(v["kind_totals"]["idol"].as_u64().unwrap() >= 1, "件数でも見えない: {v}");

        // 件数を見て絞り直せば 1 回で届く。
        let narrowed = run("resolve", json!({ "query": "未来", "kinds": ["idol"], "limit": 5 }));
        let names: Vec<&str> = narrowed["candidates"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["name"].as_str().unwrap())
            .collect();
        assert!(names.contains(&"春日未来"), "{names:?}");
    }

    #[test]
    fn resolve_は種別で絞れて上限で丸める() {
        let v = run("resolve", json!({"query": "ライブ", "kinds": "event", "limit": "3"}));
        let candidates = v["candidates"].as_array().unwrap();
        assert_eq!(candidates.len(), 3);
        assert!(candidates.iter().all(|c| c["kind"] == "event"));
        assert_eq!(v["truncated"], true);
        assert!(v["total"].as_u64().unwrap() > 3);
    }

    #[test]
    fn 知らない種別は語彙エラー() {
        let e = err("resolve", json!({"query": "x", "kinds": ["いない"]}));
        assert!(matches!(e, ToolError::BadArgs(_)), "{e:?}");
    }

    #[test]
    fn 名前が複数に当たったら候補を並べて止まる() {
        let e = err("get_event", json!({"name": "10th"}));
        match e {
            ToolError::BadArgs(message) => {
                assert!(message.contains("resolve"), "選び直し方が書かれていない: {message}");
                assert!(message.contains("ev_"), "候補の id が無い: {message}");
            }
            other => panic!("候補を並べた BadArgs のはず: {other:?}"),
        }
    }

    #[test]
    fn id_も名前も無いときと当たらないとき() {
        assert!(matches!(err("get_idol", json!({})), ToolError::BadArgs(_)));
        assert!(matches!(
            err("get_idol", json!({"id": "居ないアイドル"})),
            ToolError::NotFound(_)
        ));
        assert!(matches!(
            err("get_song", json!({"title": "そんな曲はありませんよ絶対に"})),
            ToolError::NotFound(_)
        ));
    }

    #[test]
    fn vocabulary_は語彙と規模を返す() {
        let v = run("vocabulary", json!({}));
        assert!(v["brands"].as_array().unwrap().len() >= 8);
        assert_eq!(v["brands"][0]["id"], "765as");
        assert!(v["brands"][0]["idol_count"].as_u64().unwrap() > 0);

        let song_types: Vec<&str> =
            v["song_type"].as_array().unwrap().iter().filter_map(|t| t["value"].as_str()).collect();
        assert!(song_types.contains(&"solo") && song_types.contains(&"cover"), "{song_types:?}");
        let kinds: Vec<&str> =
            v["event_kind"].as_array().unwrap().iter().filter_map(|t| t["value"].as_str()).collect();
        assert!(kinds.contains(&"live"), "{kinds:?}");

        assert!(v["counts"]["songs"].as_u64().unwrap() > 1000);
        assert!(v["counts"]["shows"].as_u64().unwrap() > 100);
        assert_eq!(v["today"], TODAY);
        assert!(v["data_version"].is_string());
        assert!(v["show_date_range"]["first"].as_str().unwrap() < v["show_date_range"]["last"].as_str().unwrap());
        // 歌詞を扱わないことが返答そのものに書いてある。
        let notes = v["notes"].as_array().unwrap();
        assert!(notes.iter().any(|n| n.as_str().unwrap().contains("歌詞")), "{notes:?}");
    }

    /// 歌詞本文への導線を返さないこと。`lyrics_url` は 3,062 曲中 2,000 曲以上に
    /// 入っていて、`serde_json::to_value(song)` と 1 行書けば漏れる形をしている。
    /// JASRAC の許諾は「D1 に置きダウンロードさせない」前提なので、機械で固定する。
    #[test]
    fn 歌詞への導線は_json_のどこにも出ない() {
        let keys = ["lyrics_url", "lyrics", "preview_url", "isrc"];
        let calls = [
            ("get_song", json!({"title": "THE IDOLM@STER"})),
            ("get_idol", json!({"name": "春日未来"})),
            ("search", json!({"query": "アイドル"})),
            ("resolve", json!({"query": "アイドル"})),
            ("get_event", json!({"name": "THE IDOLM@STER MILLION LIVE! 10thLIVE TOUR Act-1 H@PPY 4 YOU!"})),
        ];
        for (name, args) in calls {
            let text = run(name, args).to_string();
            for key in keys {
                assert!(!text.contains(key), "{name} に {key} が漏れている");
            }
            assert!(!text.contains("http"), "{name} に外部 URL が漏れている");
        }
    }
}
