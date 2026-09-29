//! 条件で並べる / 数えるツール群 (list_*・idol_songs・song_performances・setlist_diff・stats)。
//!
//! 規約 (`super` の注記も読むこと):
//! - 1 ツール = 1 `pub fn`。引数の取り出しは `super::args` の補助に寄せる。
//! - 返す JSON は「追加の往復なしに文章が書ける」形まで名前を解決する。id も必ず添える。
//! - 件数は既定の上限を持たせ、打ち切ったことが分かるように `truncated` を返す。
//!
//! ## 絞り込みと並び順はここに書かない
//!
//! どの曲が条件に当たるか・どう並ぶかは `song_list_queries` / `idol_list_filtering` /
//! `event_list_filtering` が正本で、アプリも Web もそこを通っている。このファイルは
//! **引数を正本の条件型へ詰め替えて呼ぶだけ**にする。軸が足りないときは正本側に足す
//! (ここに自前の述語を書くと、iOS・Web・LLM で「当たる曲」が三者三様になる)。
//!
//! 正本に無くて足したもの:
//! - `song_list_queries::songs_in_release_range` (リリース日の範囲)
//! - `event_list_queries::event_ids_at_venue` (会場 → イベントの逆引き)
//! - `setlist_diff::compare_setlists` (2 公演のセットリスト比較)
//!
//! ## 語彙外の値は黙って 0 件にしない
//!
//! LLM は `brand` に "cinderella" のような**それらしい綴り**を入れてくる。0 件を返すと
//! 「そんなライブは無かった」と書いてしまい、空振りに気づけない。取りうる値を並べた
//! [`ToolError::BadArgs`] で返して、次の 1 手で直せるようにする。
//! id 系 (`idol_id` / `unit_id` 等) は値域が広すぎて並べられないので
//! [`ToolError::NotFound`] にして、名前をほどくツールへ送り返す。

use super::json::{brand_ref, joint_brand_refs, listing, listing_with, Obj};
use super::scope::show_criteria;
use super::vocab::{
    brand_vocab, checked, checked_date_bound, distinct, event_kind_vocab, event_type_vocab,
    idol_vocab, sample,
    song_type_vocab,
};
use super::{args, ToolError, ToolSpec};
use crate::domain::snapshot::{Idol, Snapshot};
use serde_json::{json, Value};
use std::cmp::Reverse;
use std::collections::{BTreeSet, HashSet};

// =============================================================================
// カタログ
// =============================================================================

/// このファイルが持つツールの定義。
pub fn catalog() -> Vec<ToolSpec> {
    vec![
        spec(
            "list_idols",
            "条件でアイドルを並べる。誕生月・星座・出身地・血液型・属性・CV・所属ユニットで絞れる。\
             ブランドや属性の取りうる値は語彙ツールで引ける (知らない値を渡すと候補つきのエラーが返る)。",
            json!({
                "brand": { "type": "string", "description": "ブランド id (例 cg / ml / sc / gakuen)。" },
                "birth_month": { "type": "integer", "minimum": 1, "maximum": 12, "description": "誕生月。" },
                "constellation": { "type": "string", "description": "星座 (例 獅子座)。" },
                "birth_place": { "type": "string", "description": "出身地 (例 東京)。" },
                "blood_type": { "type": "string", "description": "血液型 (A / B / O / AB)。" },
                "attribute": { "type": "string", "description": "ブランド内の属性 (例 cute / cool / passion)。" },
                "voice_actor": { "type": "string", "description": "CV (声優) 名の完全一致。歴代すべてが対象。" },
                "unit_id": { "type": "string", "description": "所属ユニットの id。" },
                "query": { "type": "string", "description": "名前 / 読み / 別名 / 愛称の部分一致。CV 名は見ない (voice_actor を使う)。" },
                "sort": { "type": "string", "description": "official (既定) / kana / age / height / weight / birthday / debut。" },
                "limit": { "type": "integer", "description": "既定 30・最大 200。" }
            }),
            &[],
        ),
        spec(
            "list_songs",
            "条件で曲を並べる。ブランド・曲種別・原唱者・ユニット・CD シリーズ・リリース時期で絞れる。\
             一覧の母集団はアプリの曲一覧と同じで、ライブ履歴にしか出てこない曲 (カタログ情報が皆無の曲) と\
             リミックス等の派生曲は含めない。",
            json!({
                "brand": { "type": "string", "description": "ブランド id。合同曲は参加ブランドどれでも当たる。" },
                "song_type": { "type": "string", "description": "曲種別 (solo / unit / all / cover / tie_in)。all は全体曲。" },
                "idol_id": { "type": "string", "description": "原唱者 (song_artists.role='original') の idol_id。ライブで歌っただけの曲は含まない。" },
                "unit_id": { "type": "string", "description": "ユニット名義の曲 (songs.unit_id) の unit_id。" },
                "cd_series": { "type": "string", "description": "CD シリーズ名の部分一致。" },
                "series_group": { "type": "string", "description": "上位シリーズ名の完全一致。" },
                "released_from": { "type": "string", "description": "リリース日の下限。YYYY / YYYY-MM / YYYY-MM-DD。" },
                "released_to": { "type": "string", "description": "リリース日の上限。粗い指定はその年/月をすべて含む。" },
                "query": { "type": "string", "description": "曲名 / 読みの部分一致。" },
                "sort": { "type": "string", "description": "kana (既定) / release / performance。" },
                "limit": { "type": "integer", "description": "既定 30・最大 200。" }
            }),
            &[],
        ),
        spec(
            "list_events",
            "条件でライブ (イベント) を並べる。ブランド・開催年・会場・種別・今後/過去で絞れる。\
             1 イベントは複数公演 (日程) を持つので、日付は初日と最終日で返る。",
            json!({
                "brand": { "type": "string", "description": "ブランド id。合同ライブは参加ブランドどれでも当たる。" },
                "year": { "type": "integer", "description": "初日の開催年。" },
                "venue": { "type": "string", "description": "会場名。読み・旧名でも当たる。" },
                "kind": { "type": "string", "description": "live / festival / release_event。" },
                "event_type": {
                    "type": "string",
                    "description": "催しの性格。anniversary (周年・ナンバリング本公演) / orchestra (オケ) / \
                                    external_event (他社の催しへの出演) / birthday (生誕・バースデー) / \
                                    release_event (発売記念) / broadcast (番組・配信) / \
                                    live (それ以外の自社公演)。\
                                    「AS の周年では」のような絞り込みはこちら。\
                                    配信があったかは別の軸なので shows.stream_platform を見る。",
                },
                "when": { "type": "string", "enum": ["upcoming", "past", "all"], "description": "既定 all。upcoming は近い順、それ以外は新しい順。" },
                "query": { "type": "string", "description": "ライブ名の部分一致。" },
                "limit": { "type": "integer", "description": "既定 30・最大 200。" }
            }),
            &[],
        ),
        spec(
            "idol_songs",
            "あるアイドルの曲。原唱 (持ち歌) と、ライブで歌った曲は別物なので分けて返す。\
             ユニット名義の持ち歌も別立てで返す (個人の song_artists には出てこないため)。\
             原唱の各行には原唱者の人数 (artist_count) が付き、リミックス等の派生曲には derived が立つ。\
             「その人ひとりの持ち歌」が何曲かは solo_count が答える (role=solo でその曲だけ引ける)。",
            json!({
                "idol_id": { "type": "string", "description": "アイドルの id。" },
                "role": { "type": "string", "enum": ["original", "solo", "performed", "all"], "description": "既定 all。solo は原唱者がその人 1 人だけの曲 (派生曲を除く)。" },
                "limit": { "type": "integer", "description": "区分ごとの上限。既定 50・最大 300。" }
            }),
            &["idol_id"],
        ),
        spec(
            "song_performances",
            "ある曲の披露履歴 (新しい順)。日付・公演・会場・そのときの歌唱者・通算何回目かを返す。\
             出演者全員で歌った回は歌唱者の名前を並べず full_cast で示す。\
             各行の event_type (周年 / オケ / 外部イベント …) で「オケマスを除けば 10 年ぶり」\
             のように数え直せる。",
            json!({
                "song_id": { "type": "string", "description": "曲の id。" },
                "limit": { "type": "integer", "description": "既定 50・最大 500。" }
            }),
            &["song_id"],
        ),
        spec(
            "setlist_diff",
            "2 つの公演のセットリストを比べる。両方でやった曲・片方だけの曲・曲順が同じかを返す。",
            json!({
                "show_id_a": { "type": "string", "description": "公演 A の id。" },
                "show_id_b": { "type": "string", "description": "公演 B の id。" }
            }),
            &["show_id_a", "show_id_b"],
        ),
        spec(
            "stats",
            "集計。披露回数ランキング・出演公演数ランキング・公演別曲数ランキング・\
             ブランド別曲数・年別/月別公演数・CD シリーズ一覧。\
             show_song_count_ranking は brand / year / venue で絞れるので、\
             「2024 年のデレマスのライブで一番曲数が多かった公演」はこれ 1 回で出る。",
            json!({
                "kind": {
                    "type": "string",
                    "enum": STATS_KINDS,
                    "description": "集計の種類。"
                },
                "brand": { "type": "string", "description": "show_song_count_ranking のみ。ブランド id で絞る。" },
                "year": { "type": "integer", "description": "show_song_count_ranking のみ。公演日の年で絞る。" },
                "venue": { "type": "string", "description": "show_song_count_ranking のみ。会場名で絞る (読み・旧名でも当たる)。" },
                "limit": { "type": "integer", "description": "ランキングは既定 20、一覧系は既定で全件。最大 1000。" }
            }),
            &["kind"],
        ),
        spec(
            "songs_for_cast",
            "出演者の顔ぶれで歌える曲を探す。**原唱者が全員そろう曲**を返す。\
             list_songs の idol_id は「その人が入っている曲」なので、残りの原唱者が\
             その日いるかを見ていない — 編成から曲を決めるときはこちら。\
             max_missing を 1 にすると「あと 1 人呼べば歌える曲」も出て、\
             誰が足りないかが missing に入る (「この曲をやるには誰が要るか」の向きに使える)。\
             並びは欠員の少ない順 → 披露回数の多い順。派生曲 ((◯◯ Ver.) 等) は外す。",
            json!({
                "idol_ids": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "出演者のアイドル id の配列。resolve か get_show で得ること。"
                },
                "max_missing": { "type": "integer", "description": "原唱者が何人まで欠けてよいか。既定 0 (完全にそろう曲だけ)・最大 3。" },
                "min_artists": { "type": "integer", "description": "原唱者の人数の下限。ソロを外したいときに 2。" },
                "max_artists": { "type": "integer", "description": "原唱者の人数の上限。全体曲を外したいときに 5 など。" },
                "limit": { "type": "integer", "description": "既定 40・最大 200。" }
            }),
            &["idol_ids"],
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
        "list_idols" => list_idols(snap, args),
        "list_songs" => list_songs(snap, args),
        "list_events" => list_events(snap, args, today_key),
        "idol_songs" => idol_songs(snap, args),
        "song_performances" => song_performances(snap, args),
        "setlist_diff" => setlist_diff(snap, args),
        "stats" => stats(snap, args),
        "songs_for_cast" => songs_for_cast(snap, args),
        _ => return None,
    })
}

fn spec(name: &str, description: &str, properties: Value, required: &[&str]) -> ToolSpec {
    ToolSpec {
        name: name.to_string(),
        description: description.to_string(),
        // 封の組み立ては super::tool_schema に集約 (lookup / proposal と共通)。
        input_schema: super::tool_schema(properties, required),
    }
}

// =============================================================================
// 返す形の共通部品
// =============================================================================

/// 先頭 `limit` 件だけ残す (総数は呼び出し側が先に控えておく)。
pub(super) fn take<T>(mut items: Vec<T>, limit: u32) -> Vec<T> {
    items.truncate(limit as usize);
    items
}

/// 条件を 1 本足すたびに「いままでの候補との積」を取る。
///
/// 正本の絞り込み (`filter_song_indexes` 等) が持っていない軸は、その軸の**正本の関数**
/// (`unit_song_ids` / `idols_by_constellation` 等) が返す集合と交差させて実現する。
/// ここで述語を書き直さないのは、軸ごとの当たり方を 2 箇所に持たないため。
fn narrow<T: std::hash::Hash + Eq + Clone>(
    allow: &mut Option<HashSet<T>>,
    candidates: impl IntoIterator<Item = T>,
) {
    let next: HashSet<T> = candidates.into_iter().collect();
    *allow = Some(match allow.take() {
        Some(current) => current.intersection(&next).cloned().collect(),
        None => next,
    });
}

/// `stats` の `kind`。スキーマにも `BadArgs` の文面にも同じ配列を使う。
/// 他の語彙と違ってデータ由来ではなく**このツールが持つ機能の一覧**なので、
/// `vocab` (実データから作る語彙) ではなくここに置く。
const STATS_KINDS: [&str; 7] = [
    "song_play_ranking",
    "cast_show_ranking",
    "show_song_count_ranking",
    "brand_song_counts",
    "yearly_show_counts",
    "monthly_show_counts",
    "cd_series_list",
];

// =============================================================================
// 行の射影 (名前まで解決する)
// =============================================================================

fn idol_row(snap: &Snapshot, idol: &Idol) -> Value {
    use crate::domain::idol_queries::{birthday_display, height_display};
    let mut o = Obj::new();
    o.put("id", json!(idol.id));
    o.put("name", json!(idol.name));
    o.opt("name_kana", idol.name_kana.clone());
    o.opt("brand", brand_ref(snap, idol.brand_id.as_deref()));
    o.opt("attribute", idol.attribute.clone());
    o.opt("birthday", birthday_display(idol.birthday.as_deref()));
    o.opt("constellation", idol.constellation.clone());
    o.opt("blood_type", idol.blood_type.clone());
    o.opt("birth_place", idol.birth_place.clone());
    o.opt("age", idol.age);
    o.opt("height", height_display(idol.height));
    let index = snap.idol_index_by_id[&idol.id];
    o.opt("voice_actor", snap.current_voice_actor(index).map(|v| v.name.clone()));
    o.value()
}

/// 曲 1 行。原唱者は人数が多い曲 (全体曲) で名前を並べると読む量が跳ね上がるので、
/// 数だけを必ず返し、名前は並べても読める人数のときだけ添える。
// =============================================================================
// songs_for_cast
// =============================================================================

fn songs_for_cast(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::cast_song_matching::songs_for_cast as match_songs;

    let ids = arguments
        .get("idol_ids")
        .and_then(|v| v.as_array())
        .ok_or_else(|| ToolError::BadArgs("idol_ids (配列) が要る".into()))?;
    if ids.is_empty() {
        return Err(ToolError::BadArgs("idol_ids が空".into()));
    }
    // 未知の id を黙って落とさない。落とすと「その顔ぶれでは歌える曲が少ない」と
    // 読めてしまい、綴り違いが結果の違いに化ける。
    let cast: Vec<u32> = ids
        .iter()
        .map(|v| {
            let id = v.as_str().ok_or_else(|| ToolError::BadArgs("idol_ids は文字列の配列".into()))?;
            snap.idol_index_by_id
                .get(id)
                .copied()
                .ok_or_else(|| ToolError::NotFound(format!("アイドル {id} が無い")))
        })
        .collect::<Result<_, _>>()?;

    let max_missing = args::capped(arguments, "max_missing", 0, 3)?;
    let min_artists = args::u32_opt(arguments, "min_artists")?;
    let max_artists = args::u32_opt(arguments, "max_artists")?;
    let limit = args::limit(arguments, 40, 200)?;

    let hits = match_songs(snap, &cast, max_missing, min_artists, max_artists, limit as usize);
    let rows: Vec<Value> = hits
        .iter()
        .map(|h| {
            let song = &snap.songs[h.song as usize];
            let mut o = Obj::new();
            o.put("song_id", json!(song.id));
            o.put("title", json!(song.title));
            o.opt("unit_name", song.unit_name.clone());
            o.put("artist_count", json!(h.artists.len()));
            o.put(
                "artists",
                json!(h.artists.iter().map(|&a| snap.idols[a as usize].name.as_str()).collect::<Vec<_>>()),
            );
            // 空なら載せない (この DB の返し方の規約)。載っていれば「足りない人」。
            if !h.missing.is_empty() {
                o.put(
                    "missing",
                    json!(h.missing.iter().map(|&a| snap.idols[a as usize].name.as_str()).collect::<Vec<_>>()),
                );
            }
            o.put("performance_count", json!(h.performances));
            o.value()
        })
        .collect();
    Ok(listing("songs", rows.len(), rows))
}

pub(super) fn song_row(snap: &Snapshot, index: u32) -> Value {
    use crate::domain::performer_label::song_performer_label;
    const NAMED_ARTISTS_MAX: usize = 10;
    let song = &snap.songs[index as usize];
    let mut o = Obj::new();
    o.put("id", json!(song.id));
    o.put("title", json!(song.title));
    o.opt("title_kana", song.title_kana.clone());
    o.opt("brand", brand_ref(snap, song.brand_id.as_deref()));
    o.opt("song_type", song.song_type.clone());
    o.opt("release_date", song.release_date.clone());
    o.opt("cd_series", song.cd_series.clone());
    o.opt("series_group", song.series_group.clone());
    o.opt("unit_name", song.unit_name.clone());
    o.opt("singer_label", song.singer_label.clone());
    // 1 行で書くときの名義。組み方は performer_label が正本 (画面と同じ言い方になる)。
    o.opt("credited_as", song_performer_label(snap, index));
    o.put("performance_count", json!(snap.performance_counts[index as usize]));

    let artists = original_artists(snap, index);
    o.put("artist_count", json!(artists.len()));
    if !artists.is_empty() && artists.len() <= NAMED_ARTISTS_MAX {
        let names: Vec<&str> = artists.iter().map(|i| i.name.as_str()).collect();
        o.put("artists", json!(names));
    }
    o.value()
}

/// 原唱者 (`song_artists.role='original'`)。並びは idol の公式順 (前計算済み)。
/// 濾し方は `Snapshot::song_artists` が正本 — ここで `role == "original"` を書かない。
fn original_artists(snap: &Snapshot, song: u32) -> Vec<&crate::domain::snapshot::Idol> {
    snap.song_artists(&snap.songs[song as usize].id, Some("original"))
}

/// 曲 id → 添字。行の射影で 1 行につき 1 度だけ引いて使い回す
/// (以前は同じ行の `artist_count` / `derived` / ソロ判定が各々引き直していた)。
fn song_index(snap: &Snapshot, song_id: &str) -> Option<u32> {
    snap.song_index_by_id.get(song_id).copied()
}

/// 公演 1 件の見出し (どの公演かを 1 行で書けるだけの情報)。
pub(super) fn show_header(snap: &Snapshot, show_index: u32) -> Value {
    let show = &snap.shows[show_index as usize];
    let event = &snap.events[show.event as usize];
    let mut o = Obj::new();
    o.put("show_id", json!(show.id));
    o.put("show_name", json!(show.name));
    o.put("event_id", json!(event.id));
    o.put("event_name", json!(event.name));
    o.put("date", json!(show.date));
    o.opt("venue", show.venue.clone());
    o.put("song_count", json!(snap.setlist_items_by_show[show_index as usize].len()));
    o.value()
}

// =============================================================================
// list_idols
// =============================================================================

fn list_idols(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::idol_list_filtering::{
        filter_idol_list, idol_list_entries, sort_idol_list, IdolQuery, IdolSortKind,
        ALL_SORT_KINDS,
    };
    use crate::domain::idol_queries::{
        idol_cast_names, idols_by_blood_type, idols_by_birth_place, idols_by_constellation,
        idols_by_voice_actor,
    };

    let limit = args::limit(arguments, 30, 200)?;
    let mut query = IdolQuery::default();

    if let Some(brand) = args::str_opt(arguments, "brand") {
        query.brand_ids = vec![checked("brand", brand, &brand_vocab(snap))?];
    }
    if let Some(attribute) = args::str_opt(arguments, "attribute") {
        let vocab = idol_vocab(snap, |i| i.attribute.as_deref());
        query.attribute = Some(checked("attribute", attribute, &vocab)?);
    }
    if let Some(month) = args::u32_opt(arguments, "birth_month")? {
        if !(1..=12).contains(&month) {
            return Err(ToolError::BadArgs("birth_month は 1〜12 です".into()));
        }
        query.birth_month = Some(month);
    }
    if let Some(text) = args::str_opt(arguments, "query") {
        query.search_text = text;
    }
    let sort_keys: Vec<String> = ALL_SORT_KINDS.iter().map(|k| k.key().to_string()).collect();
    if let Some(sort) = args::str_opt(arguments, "sort") {
        query.sort = checked("sort", sort, &sort_keys)?;
    }

    // 正本が持たない軸は、その軸の正本の関数が返す id 集合と交差させる。
    let mut allow: Option<HashSet<String>> = None;
    if let Some(value) = args::str_opt(arguments, "constellation") {
        let vocab = idol_vocab(snap, |i| i.constellation.as_deref());
        let value = checked("constellation", value, &vocab)?;
        narrow(&mut allow, idols_by_constellation(snap, &value).into_iter().map(|r| r.id));
    }
    if let Some(value) = args::str_opt(arguments, "birth_place") {
        let vocab = idol_vocab(snap, |i| i.birth_place.as_deref());
        let value = checked("birth_place", value, &vocab)?;
        narrow(&mut allow, idols_by_birth_place(snap, &value).into_iter().map(|r| r.id));
    }
    if let Some(value) = args::str_opt(arguments, "blood_type") {
        let vocab = idol_vocab(snap, |i| i.blood_type.as_deref());
        let value = checked("blood_type", value, &vocab)?;
        narrow(&mut allow, idols_by_blood_type(snap, &value).into_iter().map(|r| r.id));
    }
    if let Some(name) = args::str_opt(arguments, "voice_actor") {
        // CV 名は完全一致でしか引けない (歴代分の索引がそうなっている)。
        // 語彙は数百件あって並べられないので、ほどき直しを促す NotFound に倒す。
        let hits = idols_by_voice_actor(snap, &name);
        if hits.is_empty() {
            return Err(ToolError::NotFound(format!(
                "CV「{name}」の担当アイドルがいない (表記ゆれの可能性がある。名前をほどいてから渡すこと)"
            )));
        }
        narrow(&mut allow, hits.into_iter().map(|r| r.id));
    }
    if let Some(unit_id) = args::str_opt(arguments, "unit_id") {
        let members = crate::domain::unit_queries::unit_member_idol_ids(snap, &unit_id);
        if members.is_empty() {
            return Err(ToolError::NotFound(format!("ユニット {unit_id} が無いか、メンバーがいない")));
        }
        narrow(&mut allow, members);
    }

    let entries = idol_list_entries(snap);
    let kept: HashSet<u32> =
        filter_idol_list(&entries, &query.to_criteria(idol_cast_names(snap))).into_iter().collect();
    let sort_kind = IdolSortKind::from_key(&query.sort);
    let ordered: Vec<u32> = sort_idol_list(&entries, sort_kind, query.ascending)
        .into_iter()
        .filter(|i| kept.contains(i))
        .filter(|i| {
            allow.as_ref().is_none_or(|ids| ids.contains(&entries[*i as usize].idol_id))
        })
        .collect();

    let total = ordered.len();
    let rows = take(ordered, limit)
        .into_iter()
        .filter_map(|i| snap.idol(&entries[i as usize].idol_id))
        .map(|idol| idol_row(snap, idol))
        .collect();
    Ok(listing("idols", total, rows))
}

// =============================================================================
// list_songs
// =============================================================================

fn list_songs(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::song_detail_queries::series_group_names;
    use crate::domain::song_list_queries::{
        song_list_indexes, song_list_sort_options_without_user_marks, songs_in_release_range,
        SongQuery,
    };
    use crate::domain::stats_queries::cd_series_list;

    let limit = args::limit(arguments, 30, 200)?;
    // 既定はアプリの曲一覧と同じ (ライブ履歴だけの曲と派生曲を隠す)。
    // ここを素の `SongListFilter::default()` にすると、一覧に無い曲まで数に入る。
    let mut query = SongQuery::default();

    if let Some(brand) = args::str_opt(arguments, "brand") {
        query.brand_ids = vec![checked("brand", brand, &brand_vocab(snap))?];
    }
    if let Some(song_type) = args::str_opt(arguments, "song_type") {
        query.song_type = Some(checked("song_type", song_type, &song_type_vocab(snap))?);
    }
    if let Some(idol_id) = args::str_opt(arguments, "idol_id") {
        if snap.idol(&idol_id).is_none() {
            return Err(ToolError::NotFound(format!("アイドル {idol_id} が無い")));
        }
        query.idol_ids = vec![idol_id];
    }
    if let Some(series) = args::str_opt(arguments, "cd_series") {
        let all = cd_series_list(snap);
        // cd_series は部分一致で当てるので、語彙との一致も部分一致で見る。
        if !all.iter().any(|s| s.contains(&series)) {
            return Err(ToolError::BadArgs(format!(
                "cd_series に「{series}」を含むシリーズは無い。取りうる値: {}",
                sample(&all)
            )));
        }
        query.cd_series = Some(series);
    }
    if let Some(group) = args::str_opt(arguments, "series_group") {
        query.series_group = Some(checked("series_group", group, &series_group_names(snap, &[]))?);
    }
    if let Some(text) = args::str_opt(arguments, "query") {
        query.title = Some(text);
    }
    let sort_keys: Vec<String> =
        song_list_sort_options_without_user_marks().into_iter().map(|o| o.key).collect();
    if let Some(sort) = args::str_opt(arguments, "sort") {
        query.sort = checked("sort", sort, &sort_keys)?;
    }

    let mut allow: Option<HashSet<u32>> = None;
    if let Some(unit_id) = args::str_opt(arguments, "unit_id") {
        if snap.unit(&unit_id).is_none() {
            return Err(ToolError::NotFound(format!("ユニット {unit_id} が無い")));
        }
        let ids = crate::domain::unit_queries::unit_song_ids(snap, &unit_id);
        narrow(&mut allow, ids.iter().filter_map(|id| snap.song_index_by_id.get(id).copied()));
    }
    let from = args::str_opt(arguments, "released_from")
        .map(|v| checked_date_bound("released_from", v))
        .transpose()?;
    let to = args::str_opt(arguments, "released_to")
        .map(|v| checked_date_bound("released_to", v))
        .transpose()?;
    if from.is_some() || to.is_some() {
        narrow(&mut allow, songs_in_release_range(snap, from.as_deref(), to.as_deref()));
    }

    let indexes: Vec<u32> = song_list_indexes(
        snap,
        &query.to_filter(),
        query.sort_order(),
        query.ascending,
        &[],
        &[],
    )
    .into_iter()
    .filter(|i| allow.as_ref().is_none_or(|ids| ids.contains(i)))
    .collect();

    let total = indexes.len();
    let rows = take(indexes, limit).into_iter().map(|i| song_row(snap, i)).collect();
    Ok(listing("songs", total, rows))
}

// =============================================================================
// list_events
// =============================================================================

fn list_events(snap: &Snapshot, arguments: &Value, today_key: &str) -> Result<Value, ToolError> {
    use crate::domain::event_grouping::{event_is_upcoming, year_key};
    use crate::domain::event_list_filtering::{
        filter_event_indices, EventFilterCriteria, EventFilterItem,
    };
    use crate::domain::event_list_queries::{event_ids_at_venue, events_with_first_date};

    let limit = args::limit(arguments, 30, 200)?;
    let brand = args::str_opt(arguments, "brand")
        .map(|b| checked("brand", b, &brand_vocab(snap)))
        .transpose()?;
    let kind = args::str_opt(arguments, "kind")
        .map(|k| checked("kind", k, &event_kind_vocab(snap)))
        .transpose()?;
    let event_type = args::str_opt(arguments, "event_type")
        .map(|t| checked("event_type", t, &event_type_vocab(snap)))
        .transpose()?;
    let when = args::str_opt(arguments, "when").unwrap_or_else(|| "all".to_string());
    if !matches!(when.as_str(), "upcoming" | "past" | "all") {
        return Err(ToolError::BadArgs("when は upcoming / past / all です".into()));
    }
    let venue = args::str_opt(arguments, "venue");
    let year = args::u32_opt(arguments, "year")?;

    // kind を明示しなければ全種別。`events_with_first_date` の既定 (live+festival) だと
    // 発売記念イベントが黙って消えるので、語彙から作った全種別を渡す。
    let kinds: Vec<String> = kind.into_iter().collect::<Vec<_>>();
    let kinds = if kinds.is_empty() { event_kind_vocab(snap) } else { kinds };
    let records = events_with_first_date(snap, None, true, false, Some(&kinds));

    let items: Vec<EventFilterItem> = records
        .iter()
        .map(|r| EventFilterItem {
            id: r.event.id.clone(),
            brand_id: r.event.brand_id.clone(),
            joint_brand_ids: r.event.joint_brand_ids.clone(),
            name: r.event.name.clone(),
            kind: r.event.kind.clone(),
            event_type: r.event.event_type.clone(),
        })
        .collect();
    let criteria = EventFilterCriteria {
        selected_brand_ids: brand.into_iter().collect(),
        excluded_kinds: Vec::new(),
        search_text: args::str_opt(arguments, "query").unwrap_or_default(),
        attendance_filter: "all".to_string(),
        attended_event_ids: Vec::new(),
        require_favorite: false,
        favorite_ids: Vec::new(),
        require_note: false,
        note_ids: Vec::new(),
        venue: venue.clone().unwrap_or_default(),
        venue_event_ids: venue.map(|v| event_ids_at_venue(snap, &v)).unwrap_or_default(),
        // 種別の絞り込みは下の event_type 引数 (完全一致) が担うので、ここでは畳まない。
        exclude_broadcast: false,
    };

    let mut kept: Vec<u32> = filter_event_indices(&items, &criteria)
        .into_iter()
        .filter(|&i| {
            let record = &records[i as usize];
            event_type.as_ref().is_none_or(|t| &record.event.event_type == t)
        })
        .filter(|&i| {
            let record = &records[i as usize];
            year.is_none_or(|y| year_key(record.first_date.as_deref()) == Some(y.to_string()))
        })
        .filter(|&i| {
            let record = &records[i as usize];
            let upcoming = event_is_upcoming(
                record.first_date.as_deref(),
                record.last_date.as_deref(),
                today_key,
            );
            match when.as_str() {
                "upcoming" => upcoming,
                "past" => !upcoming,
                _ => true,
            }
        })
        .collect();
    // 元の並びは初日の降順 (新しい順)。今後の予定だけは「近い順」で読みたい。
    if when == "upcoming" {
        kept.reverse();
    }

    let total = kept.len();
    let rows = take(kept, limit)
        .into_iter()
        .map(|i| {
            let record = &records[i as usize];
            let index = snap.event_index_by_id[&record.event.id];
            let mut o = Obj::new();
            o.put("id", json!(record.event.id));
            o.put("name", json!(record.event.name));
            o.opt("brand", brand_ref(snap, record.event.brand_id.as_deref()));
            o.list("joint_brands", joint_brand_refs(snap, record.event.joint_brand_ids.as_deref()));
            o.put("kind", json!(record.event.kind));
            // 未分類は空なので出さない。空文字を返すと「分類が live でない」と
            // 読み違えられる。
            if !record.event.event_type.is_empty() {
                o.put("event_type", json!(record.event.event_type));
            }
            o.opt("first_date", record.first_date.clone());
            o.opt("last_date", record.last_date.clone());
            let shows = &snap.shows_by_event[index as usize];
            o.put("show_count", json!(shows.len()));
            let venues: Vec<String> = distinct(
                shows.iter().map(|&s| snap.shows[s as usize].venue.as_deref()),
            );
            if !venues.is_empty() {
                o.put("venues", json!(venues));
            }
            o.put(
                "upcoming",
                json!(event_is_upcoming(
                    record.first_date.as_deref(),
                    record.last_date.as_deref(),
                    today_key
                )),
            );
            o.value()
        })
        .collect();
    Ok(listing("events", total, rows))
}

// =============================================================================
// idol_songs
// =============================================================================

fn idol_songs(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::idol_song_queries::{idol_performed_songs, idol_unit_song_ids};
    use crate::domain::song_list_queries::{is_hidden_variant, is_solo_song};

    let idol_id = args::str_req(arguments, "idol_id")?;
    let Some(idol) = snap.idol(&idol_id) else {
        return Err(ToolError::NotFound(format!("アイドル {idol_id} が無い")));
    };
    let limit = args::limit(arguments, 50, 300)?;
    let role = args::str_opt(arguments, "role").unwrap_or_else(|| "all".to_string());
    if !matches!(role.as_str(), "original" | "solo" | "performed" | "all") {
        return Err(ToolError::BadArgs("role は original / solo / performed / all です".into()));
    }

    let mut out = Obj::new();
    out.put("idol", idol_row(snap, idol));

    if role != "performed" {
        // 原唱 (持ち歌)。song_artists.role='original' の行だけ。
        let mut originals =
            crate::domain::idol_song_queries::idol_songs(snap, &idol_id, Some("original"));
        // 「持ち歌 84 曲」のうち大半が `(伊吹 翼 Ver.)` のような派生曲で、
        // 残りも合唱曲、ということが起きる。件数だけでは実態が分からないので、
        // 行ごとに**原唱者の人数**と**派生曲かどうか**を添える。どちらも既存の正本
        // (`song_list_queries::is_solo_song` / `is_hidden_variant`) の判断で、
        // ここで数え直さない。
        let solo = |song: u32| is_solo_song(snap, song) && !is_hidden_variant(&snap.songs[song as usize]);
        // 「その人ひとりの持ち歌が何曲か」は role を問わず 1 回で答えられるようにする
        // (role=solo をもう一度呼ばせない)。
        let solo_count =
            originals.iter().filter(|r| song_index(snap, &r.song_id).is_some_and(solo)).count();
        out.put("solo_count", json!(solo_count));

        let key = if role == "solo" {
            originals.retain(|r| song_index(snap, &r.song_id).is_some_and(solo));
            "solo"
        } else {
            "original"
        };
        let total = originals.len();
        let rows = take(originals, limit)
            .into_iter()
            .filter_map(|r| song_index(snap, &r.song_id).map(|i| (r, i)))
            .map(|(r, i)| {
                let mut o = Obj::new();
                o.put("id", json!(r.song_id));
                o.put("title", json!(r.title));
                o.opt("release_date", r.release_date);
                o.opt("unit_name", r.unit_name);
                o.put("artist_count", json!(original_artists(snap, i).len()));
                if is_hidden_variant(&snap.songs[i as usize]) {
                    o.put("derived", json!(true));
                }
                o.value()
            })
            .collect();
        out.capped(key, rows, total);

        // ユニット名義の持ち歌 (songs.unit_id 由来)。個人の song_artists には
        // 出てこないことがあるので、原唱とは別立てで返す。
        let unit_ids = idol_unit_song_ids(snap, &idol_id);
        let total = unit_ids.len();
        let rows = take(unit_ids, limit)
            .into_iter()
            .filter_map(|id| snap.song_index_by_id.get(&id).copied())
            .map(|i| {
                let song = &snap.songs[i as usize];
                let mut o = Obj::new();
                o.put("id", json!(song.id));
                o.put("title", json!(song.title));
                o.opt("release_date", song.release_date.clone());
                o.opt("unit_name", song.unit_name.clone());
                o.value()
            })
            .collect();
        out.capped("unit_songs", rows, total);
    }

    if role != "original" {
        // ライブで歌った曲。持ち歌とは別物 (他人の曲を歌うことも、持ち歌を
        // 一度も歌っていないこともある)。
        let performed = idol_performed_songs(snap, &idol_id);
        let total = performed.len();
        let rows = take(performed, limit)
            .into_iter()
            .map(|r| {
                let mut o = Obj::new();
                o.put("id", json!(r.song_id));
                o.put("title", json!(r.title));
                o.put("perform_count", json!(r.perform_count));
                o.opt("unit_name", r.unit_name);
                o.value()
            })
            .collect();
        out.capped("performed", rows, total);
    }

    Ok(out.value())
}

// =============================================================================
// song_performances
// =============================================================================

fn song_performances(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::setlist_lineup::{is_full_cast, summarize};
    use crate::domain::setlist_sections::track_number;
    use crate::domain::song_detail_queries::{
        performance_history, performance_item_indices, performance_ordinal_label,
    };

    let song_id = args::str_req(arguments, "song_id")?;
    let Some(&song_index) = snap.song_index_by_id.get(&song_id) else {
        return Err(ToolError::NotFound(format!("曲 {song_id} が無い")));
    };
    let limit = args::limit(arguments, 20, 500)?;

    let history = performance_history(snap, &song_id);
    let items = performance_item_indices(snap, &song_id).to_vec();
    let total = history.len();
    // 「いつぶりか」は種別で数え直されるもの (「オケマスを除けば 10 年ぶり」)。
    // 履歴の各行に催しの種別を添えて、呼び手が除外して数え直せるようにする。
    let event_type = |event_id: &str| {
        let index = *snap.event_index_by_id.get(event_id)?;
        let value = snap.events[index as usize].event_type.as_str();
        (!value.is_empty()).then(|| json!(value))
    };
    let performance_end = |entry: &crate::domain::song_detail_queries::PerformanceHistoryEntry| {
        let mut o = Obj::new();
        o.put("date", json!(entry.date));
        o.put("event_name", json!(entry.event_name));
        o.opt("event_type", event_type(&entry.event_id));
        o.put("show_id", json!(entry.show_id));
        o.put("ordinal", json!(entry.ordinal));
        o.value()
    };
    let history_ends = (history.first().map(performance_end), history.last().map(performance_end));
    let original_idols = original_artists(snap, song_index);
    let originals: Vec<&str> = original_idols.iter().map(|i| i.id.as_str()).collect();

    let rows: Vec<Value> = history
        .into_iter()
        .zip(items)
        .take(limit as usize)
        .map(|(entry, item)| {
            let mut o = Obj::new();
            o.put("show_id", json!(entry.show_id));
            o.put("event_id", json!(entry.event_id));
            o.put("event_name", json!(entry.event_name));
            o.opt("event_type", event_type(&entry.event_id));
            o.put("show_name", json!(entry.show_name));
            o.put("date", json!(entry.date));
            o.opt("venue", entry.venue);
            let show = snap.setlist_items[item as usize].show;
            o.put("position", json!(track_number(snap, item)));
            o.opt("section", entry.section);
            o.put("ordinal", json!(entry.ordinal));
            o.put("ordinal_label", json!(performance_ordinal_label(entry.ordinal)));

            let performers: Vec<&str> = snap.performers_by_item[item as usize]
                .iter()
                .map(|&i| snap.idols[i as usize].id.as_str())
                .collect();
            let performer_set: BTreeSet<&str> = performers.iter().copied().collect();
            o.put("singer_count", json!(performers.len()));

            let cast: BTreeSet<&str> = snap.cast_by_show[show as usize]
                .iter()
                .map(|l| snap.idols[l.idol as usize].id.as_str())
                .collect();
            let full_cast = is_full_cast(&cast, &performer_set);
            if full_cast {
                // 「出演者全員」で言い切れるなら名前は並べない。人数の多い全体曲で
                // 30 人ぶんの名前を毎回積むと、読む側の予算をそれだけで食い潰す。
                o.put("full_cast", json!(true));
            } else if !performers.is_empty() {
                let names: Vec<String> = snap.performers_by_item[item as usize]
                    .iter()
                    .map(|&i| snap.idols[i as usize].name.clone())
                    .collect();
                o.put("singers", json!(names));
            }
            if let Some(summary) = summarize(&originals, &performer_set, &cast, full_cast) {
                o.put("lineup", json!(summary.label()));
            }
            o.value()
        })
        .collect();

    let mut head = Obj::new();
    head.put("song", song_row(snap, song_index));
    // 履歴は新しい順なので、打ち切ると**初披露が必ず落ちる**。「初披露はいつ?」は
    // よく訊かれるのに、行を全部返さないと答えられないのでは限度を上げ続けるしかない。
    // 両端だけは見出しに置いて、打ち切りと無関係に答えられるようにする。
    head.opt("first_performance", history_ends.1);
    head.opt("latest_performance", history_ends.0);
    Ok(listing_with(head, "performances", total, rows))
}

// =============================================================================
// setlist_diff
// =============================================================================

fn setlist_diff(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::setlist_diff::{compare_setlists, SetlistItemDiffRow};
    use crate::domain::setlist_sections::numbered_setlist;

    let a = show_index(snap, &args::str_req(arguments, "show_id_a")?)?;
    let b = show_index(snap, &args::str_req(arguments, "show_id_b")?)?;

    let rows_of = |show: u32| -> Vec<SetlistItemDiffRow> {
        // 生の position は公演をまたぐ通し番号なので曲順に直して渡す
        // (比較の結果がそのまま「何曲目」として読める)。曲順の規則は setlist_sections が正本。
        numbered_setlist(snap, show)
            .map(|(rank, i)| {
                let item = &snap.setlist_items[i as usize];
                SetlistItemDiffRow {
                    id: item.id.clone(),
                    song_id: snap.songs[item.song as usize].id.clone(),
                    position: rank as i64,
                    section: item.section.clone(),
                }
            })
            .collect()
    };
    let comparison = compare_setlists(&rows_of(a), &rows_of(b));

    let title = |song_id: &str| snap.song(song_id).map(|s| s.title.clone());
    let slot_rows = |slots: &[crate::domain::setlist_diff::SetlistSlot]| -> Vec<Value> {
        slots
            .iter()
            .map(|s| {
                let mut o = Obj::new();
                o.put("song_id", json!(s.song_id));
                o.opt("title", title(&s.song_id));
                o.put("position", json!(s.position));
                o.opt("section", s.section.clone());
                o.value()
            })
            .collect()
    };

    let mut out = Obj::new();
    out.put("a", show_header(snap, a));
    out.put("b", show_header(snap, b));
    out.put("shared_count", json!(comparison.shared.len()));
    out.put("same_order", json!(comparison.same_order));
    out.put(
        "shared",
        json!(comparison
            .shared
            .iter()
            .map(|s| {
                let mut o = Obj::new();
                o.put("song_id", json!(s.song_id));
                o.opt("title", title(&s.song_id));
                o.put("position_a", json!(s.position_a));
                o.put("position_b", json!(s.position_b));
                o.value()
            })
            .collect::<Vec<_>>()),
    );
    out.put("only_a", json!(slot_rows(&comparison.only_a)));
    out.put("only_b", json!(slot_rows(&comparison.only_b)));
    Ok(out.value())
}

/// `stats --kind show_song_count_ranking` の絞り込み (brand / year / venue)。
///
/// 軸のほどき方も絞り込みの規則も、公演を扱う他のツールと同じ経路
/// (`scope::show_criteria` → `show_list_filtering::filter_show_indexes`) を通す。
/// ここに述語を書くと、同じ「デレマスのライブ」が一覧と集計で違う集合になる。
fn scoped_show_indexes(snap: &Snapshot, arguments: &Value) -> Result<Vec<u32>, ToolError> {
    use crate::domain::show_list_filtering::filter_show_indexes;
    // このランキングが持つ軸は 3 つだけ。他の軸を付けられたら黙って無視せず突き返す
    // (無視すると「絞ったつもりの数」を答えてしまう)。today_key は when を使わないので
    // 読まれない。
    let criteria = show_criteria(snap, arguments, "", &["brand", "year", "venue"])?;
    Ok(filter_show_indexes(snap, &criteria))
}

fn show_index(snap: &Snapshot, show_id: &str) -> Result<u32, ToolError> {
    snap.show_index_by_id
        .get(show_id)
        .copied()
        .ok_or_else(|| ToolError::NotFound(format!("公演 {show_id} が無い")))
}

// =============================================================================
// stats
// =============================================================================

fn stats(snap: &Snapshot, arguments: &Value) -> Result<Value, ToolError> {
    use crate::domain::stats_queries::{
        brand_song_counts, cast_show_count_ranking, cd_series_list, monthly_show_counts,
        song_play_count_ranking, yearly_show_counts,
    };

    let kind = args::str_req(arguments, "kind")?;
    if !STATS_KINDS.contains(&kind.as_str()) {
        return Err(ToolError::BadArgs(format!(
            "kind に「{kind}」は無い。取りうる値: {}",
            STATS_KINDS.join(" / ")
        )));
    }
    // ランキングは「上位いくつか」を見るもの、一覧系は全部見るもの。既定が違う。
    let ranking = matches!(
        kind.as_str(),
        "song_play_ranking" | "cast_show_ranking" | "show_song_count_ranking"
    );
    let limit = args::limit(arguments, if ranking { 20 } else { 1000 }, 1000)?;

    // 絞り込みの軸を持つのは公演別ランキングだけ。他の kind に付けられたら
    // 黙って無視しない (無視すると「絞ったつもりの数」を答えてしまう)。
    // 軸の名前は scope が数え上げるので、ここで並べ直さない。
    if kind != "show_song_count_ranking" {
        show_criteria(snap, arguments, "", &[])
            .map_err(|e| match e {
                ToolError::BadArgs(m) => ToolError::BadArgs(format!(
                    "{m} — 公演の絞り込みができるのは kind=show_song_count_ranking のときだけ"
                )),
                other => other,
            })?;
    }

    let (total, rows): (usize, Vec<Value>) = match kind.as_str() {
        "song_play_ranking" => {
            let total = snap.performance_counts.iter().filter(|&&c| c > 0).count();
            let rows = song_play_count_ranking(snap, limit)
                .into_iter()
                .map(|r| {
                    let mut o = Obj::new();
                    o.put("id", json!(r.id));
                    o.put("title", json!(r.title));
                    o.put("play_count", json!(r.play_count));
                    o.opt("brand", brand_ref(snap, r.brand_id.as_deref()));
                    o.value()
                })
                .collect();
            (total, rows)
        }
        "show_song_count_ranking" => {
            let mut shows = scoped_show_indexes(snap, arguments)?;
            let total = shows.len();
            // 同数は公演の添字で決定的に (日付順の入力なので、古い方が先に来る)。
            shows.sort_by_key(|&s| {
                (Reverse(snap.setlist_items_by_show[s as usize].len()), s)
            });
            shows.truncate(limit as usize);
            let rows = shows
                .into_iter()
                .map(|s| {
                    let mut o = Obj::new();
                    o.merge(show_header(snap, s));
                    o.put("id", json!(snap.shows[s as usize].id));
                    // 「一番出演者が多かった公演」も同じ 1 回で答えられるように添える。
                    // 人数の定義は show_presence (出演者表 ∪ 歌唱メンバー) で、
                    // get_show / list_shows の cast_count と同じもの。以前はここだけ
                    // show_cast の行数で、同じ鍵が 2 つの意味を持っていた。
                    o.put(
                        "cast_count",
                        json!(crate::domain::event_detail_queries::show_presence(snap, s).len()),
                    );
                    o.value()
                })
                .collect();
            (total, rows)
        }
        "cast_show_ranking" => {
            let total = snap.cast_shows_by_idol.iter().filter(|s| !s.is_empty()).count();
            let rows = cast_show_count_ranking(snap, limit)
                .into_iter()
                .map(|r| json!({ "id": r.id, "name": r.name, "show_count": r.show_count }))
                .collect();
            (total, rows)
        }
        "brand_song_counts" => {
            let all = brand_song_counts(snap);
            let total = all.len();
            let rows = take(all, limit)
                .into_iter()
                .map(|r| json!({ "id": r.id, "name": r.short_name, "song_count": r.song_count }))
                .collect();
            (total, rows)
        }
        "yearly_show_counts" => {
            let all = yearly_show_counts(snap);
            let total = all.len();
            let rows = take(all, limit)
                .into_iter()
                .map(|r| json!({ "id": r.year, "year": r.year, "show_count": r.show_count }))
                .collect();
            (total, rows)
        }
        "monthly_show_counts" => {
            let all: Vec<(String, u32)> = monthly_show_counts(snap).into_iter().collect();
            let total = all.len();
            let rows = take(all, limit)
                .into_iter()
                .map(|(month, count)| json!({ "id": month, "month": month, "show_count": count }))
                .collect();
            (total, rows)
        }
        _ => {
            let all = cd_series_list(snap);
            let total = all.len();
            let rows =
                take(all, limit).into_iter().map(|name| json!({ "id": name, "name": name })).collect();
            (total, rows)
        }
    };

    let mut head = Obj::new();
    head.put("kind", json!(kind));
    Ok(listing_with(head, "items", total, rows))
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

    fn run(name: &str, arguments: Value) -> Value {
        call_tool(bundle_snapshot(), name, &arguments, TODAY)
            .unwrap_or_else(|e| panic!("{name} が失敗した: {e}"))
    }

    fn err(name: &str, arguments: Value) -> ToolError {
        call_tool(bundle_snapshot(), name, &arguments, TODAY).expect_err("エラーになるはず")
    }

    fn rows<'a>(value: &'a Value, key: &str) -> &'a Vec<Value> {
        value[key].as_array().unwrap_or_else(|| panic!("{key} が配列でない: {value}"))
    }

    fn text(value: &Value, key: &str) -> String {
        value[key].as_str().unwrap_or_else(|| panic!("{key} が文字列でない: {value}")).to_string()
    }

    // ---- list_idols ----

    #[test]
    fn 七月生まれのアイドルを引いて文章が書ける() {
        let out = run("list_idols", json!({ "birth_month": 7, "limit": 200 }));
        let idols = rows(&out, "idols");
        assert!(idols.len() > 20, "7 月生まれが 20 人以下はおかしい: {}", idols.len());
        assert_eq!(out["total"].as_u64().unwrap() as usize, idols.len());

        // 返った 1 件だけで「誰が・どのブランドで・いつ生まれ」が書ける。
        let first = &idols[0];
        assert!(!text(first, "id").is_empty());
        assert!(!text(first, "name").is_empty());
        assert!(text(first, "birthday").starts_with("7月"), "誕生日が 7 月でない: {first}");
        assert!(first["brand"]["short_name"].is_string(), "ブランド名が無い: {first}");

        // null のキーは出さない (年齢未設定のアイドルで確かめる)。
        for idol in idols {
            assert!(!idol.as_object().unwrap().values().any(Value::is_null), "null が混じった: {idol}");
        }
    }

    #[test]
    fn ブランドと誕生月は_and_で効く() {
        let all = run("list_idols", json!({ "birth_month": 7, "limit": 200 }));
        let cg = run("list_idols", json!({ "brand": "cg", "birth_month": 7, "limit": 200 }));
        assert!(cg["total"].as_u64().unwrap() > 0);
        assert!(cg["total"].as_u64().unwrap() < all["total"].as_u64().unwrap());
        for idol in rows(&cg, "idols") {
            assert_eq!(idol["brand"]["id"], "cg");
            assert!(text(idol, "birthday").starts_with("7月"));
        }
    }

    #[test]
    fn 星座と血液型は正本の関数と同じ集合になる() {
        use crate::domain::idol_queries::idols_by_constellation;
        let out = run("list_idols", json!({ "constellation": "獅子座", "limit": 200 }));
        // 一覧は外部ゲストを含まないので「正本の結果に含まれる」ことを見る。
        let canonical: HashSet<String> =
            idols_by_constellation(bundle_snapshot(), "獅子座").into_iter().map(|r| r.id).collect();
        for idol in rows(&out, "idols") {
            assert!(canonical.contains(&text(idol, "id")), "正本に無い: {idol}");
        }
        assert!(out["total"].as_u64().unwrap() > 20);

        let blood = run("list_idols", json!({ "blood_type": "AB", "limit": 200 }));
        for idol in rows(&blood, "idols") {
            assert_eq!(text(idol, "blood_type"), "AB");
        }
    }

    #[test]
    fn 声優名でアイドルを引ける() {
        let out = run("list_idols", json!({ "voice_actor": "大橋彩香" }));
        let names: Vec<String> = rows(&out, "idols").iter().map(|i| text(i, "name")).collect();
        assert!(names.contains(&"島村卯月".to_string()), "大橋彩香 の担当に島村卯月がいない: {names:?}");
    }

    #[test]
    fn 並べ替えは正本の軸を使う() {
        let out = run("list_idols", json!({ "sort": "height", "limit": 5 }));
        let heights: Vec<String> = rows(&out, "idols").iter().map(|i| text(i, "height")).collect();
        assert_eq!(heights.len(), 5);
        // 既定方向は降順 (高い順)。
        let cm = |s: &String| s.trim_end_matches("cm").parse::<f64>().unwrap();
        assert!(heights.windows(2).all(|w| cm(&w[0]) >= cm(&w[1])), "高い順でない: {heights:?}");
    }

    #[test]
    fn 誕生月の範囲外は弾く() {
        assert!(matches!(err("list_idols", json!({ "birth_month": 13 })), ToolError::BadArgs(_)));
    }

    // ---- list_songs ----

    #[test]
    fn シンデレラガールズのユニット曲をリリース順で引ける() {
        let out = run(
            "list_songs",
            json!({ "brand": "cg", "song_type": "unit", "sort": "release", "limit": 5 }),
        );
        let songs = rows(&out, "songs");
        assert_eq!(songs.len(), 5);
        assert!(out["truncated"].as_bool().unwrap());
        assert!(out["total"].as_u64().unwrap() > 100);

        let dates: Vec<String> = songs.iter().map(|s| text(s, "release_date")).collect();
        assert!(dates.windows(2).all(|w| w[0] >= w[1]), "新しい順でない: {dates:?}");
        for song in songs {
            assert_eq!(text(song, "song_type"), "unit");
            assert!(song["performance_count"].is_number());
            assert!(song["artist_count"].is_number());
        }
    }

    #[test]
    fn リリース日の範囲は粗い指定でもその年を丸ごと含む() {
        let out = run(
            "list_songs",
            json!({ "released_from": "2024", "released_to": "2024", "limit": 200 }),
        );
        let songs = rows(&out, "songs");
        assert!(!songs.is_empty());
        for song in songs {
            assert!(text(song, "release_date").starts_with("2024"), "{song}");
        }
    }

    #[test]
    fn 原唱者で絞ると全体曲まで含めて引ける() {
        // 島村卯月の持ち歌 (song_artists.role='original')。
        let out = run("list_songs", json!({ "idol_id": "cg_島村卯月", "limit": 200 }));
        assert!(out["total"].as_u64().unwrap() > 10, "{out}");

        // 原唱者の絞り込みと曲名の絞り込みが AND で効く。
        let one = run("list_songs", json!({ "idol_id": "cg_島村卯月", "query": "S(mile)ING" }));
        let titles: Vec<String> = rows(&one, "songs").iter().map(|s| text(s, "title")).collect();
        assert!(titles.iter().any(|t| t.starts_with("S(mile)ING")), "持ち歌が引けていない: {titles:?}");
        // 本人の持ち歌でない曲は同じ語でも出ない。
        let other = run("list_songs", json!({ "idol_id": "cg_渋谷凛", "query": "S(mile)ING" }));
        assert_eq!(other["total"], 0, "{other}");
    }

    #[test]
    fn 原唱者が多い曲は名前を並べず人数だけ返す() {
        let out = run("list_songs", json!({ "song_type": "all", "limit": 200 }));
        let many = rows(&out, "songs")
            .iter()
            .find(|s| s["artist_count"].as_u64().unwrap() > 10)
            .expect("原唱者 11 人以上の全体曲がある");
        assert!(many.get("artists").is_none(), "人数が多いのに名前を並べている: {many}");

        let few = rows(&out, "songs")
            .iter()
            .find(|s| (1..=10).contains(&s["artist_count"].as_u64().unwrap()));
        if let Some(few) = few {
            assert!(few.get("artists").is_some(), "人数が少ないのに名前が無い: {few}");
        }
    }

    #[test]
    fn 知らない_cd_シリーズは候補つきで弾く() {
        let e = err("list_songs", json!({ "cd_series": "存在しないシリーズ名" }));
        let ToolError::BadArgs(message) = e else { panic!("BadArgs でない") };
        assert!(message.contains("取りうる値"), "{message}");
    }

    #[test]
    fn リリース日の書式違いは弾く() {
        assert!(matches!(
            err("list_songs", json!({ "released_from": "2024/01/01" })),
            ToolError::BadArgs(_)
        ));
    }

    // ---- list_events ----

    #[test]
    fn シンデレラガールズの_2024_年のライブを引いて文章が書ける() {
        let out = run("list_events", json!({ "brand": "cg", "year": 2024, "limit": 50 }));
        let events = rows(&out, "events");
        assert!(events.len() >= 8, "2024 年の cg のライブが少なすぎる: {}", events.len());

        let names: Vec<String> = events.iter().map(|e| text(e, "name")).collect();
        assert!(
            names.iter().any(|n| n.contains("ConnecTrip")),
            "ConnecTrip! が入っていない: {names:?}"
        );
        for event in events {
            assert!(text(event, "first_date").starts_with("2024"), "{event}");
            assert!(event["show_count"].as_u64().unwrap() >= 1);
            // 会場まで返るので「どこで何公演やったか」がこの 1 回で書ける。
            assert!(event.get("venues").is_some(), "会場が無い: {event}");
        }
    }

    #[test]
    fn 会場で引くと読みでも旧名でも当たる() {
        let ids = |out: &Value| -> HashSet<String> {
            out["events"].as_array().unwrap().iter().map(|e| text(e, "id")).collect()
        };
        let kanji = ids(&run("list_events", json!({ "venue": "横浜アリーナ", "limit": 200 })));
        let kana = ids(&run("list_events", json!({ "venue": "よこはまありーな", "limit": 200 })));
        assert!(kanji.len() > 3, "横浜アリーナのライブが少なすぎる: {}", kanji.len());
        // 読みは会場マスタ経由なので、`venue_id` を持たない古い公演のぶんだけ少なくなる。
        // そこは生文字列でしか引きようがない (会場マスタに無いものの読みは持てない)。
        assert!(!kana.is_empty(), "読みで 0 件 = 会場マスタの綴りを見ていない");
        assert!(kana.is_subset(&kanji), "読みでしか当たらないライブがある: {kana:?}");
    }

    #[test]
    fn 今後と過去は今日を境に分かれる() {
        let past = run("list_events", json!({ "when": "past", "limit": 200 }));
        let upcoming = run("list_events", json!({ "when": "upcoming", "limit": 200 }));
        let all = run("list_events", json!({ "when": "all", "limit": 1 }));
        assert_eq!(
            past["total"].as_u64().unwrap() + upcoming["total"].as_u64().unwrap(),
            all["total"].as_u64().unwrap(),
            "今後と過去が全体の分割になっていない"
        );
        for event in rows(&past, "events") {
            assert!(!event["upcoming"].as_bool().unwrap());
        }
        // 過去は新しい順。
        let dates: Vec<String> = rows(&past, "events").iter().map(|e| text(e, "first_date")).collect();
        assert!(dates.windows(2).all(|w| w[0] >= w[1]), "新しい順でない: {:?}", &dates[..5]);
    }

    #[test]
    fn 催しの種別で絞れる() {
        // 「AS の周年では」のような絞り込みの軸。語彙は実データの DISTINCT なので、
        // 分類がまだ入っていない DB でも「その値で絞ったらその値だけ返る」は成り立つ。
        let snapshot = bundle_snapshot();
        let vocabulary = super::event_type_vocab(snapshot);
        for value in &vocabulary {
            let listed = run("list_events", json!({ "event_type": value, "limit": 200 }));
            assert!(listed["total"].as_u64().unwrap() > 0, "{value} が 0 件");
            for event in rows(&listed, "events") {
                assert_eq!(text(event, "event_type"), *value);
            }
        }
        // 語彙外は黙って 0 件にせず、候補つきで突き返す。
        let error = err("list_events", json!({ "event_type": "オケ" }));
        assert!(matches!(error, ToolError::BadArgs(m) if m.contains("event_type")));
    }

    // ---- idol_songs ----

    #[test]
    fn 持ち歌とライブで歌った曲は別に返る() {
        let out = run("idol_songs", json!({ "idol_id": "cg_島村卯月", "limit": 300 }));
        assert_eq!(text(&out["idol"], "name"), "島村卯月");
        // 列が複数あるので打ち切りは `<列名>_total` / `<列名>_truncated` (lookup と同じ流儀)。
        let original = out["original_total"].as_u64().unwrap();
        let performed = out["performed_total"].as_u64().unwrap();
        assert!(original > 0 && performed > 0);
        assert_ne!(original, performed, "原唱と披露が同数 = どちらかを取り違えている疑い");
        // limit 300 なので打ち切っていない = truncated の鍵自体が出ない。
        assert!(out.get("original_truncated").is_none(), "{out}");
        assert_eq!(rows(&out, "original").len() as u64, original);

        // ライブで歌った側には回数が付く (「何回歌ったか」を追加の往復なしで書ける)。
        assert!(rows(&out, "performed")[0]["perform_count"].as_u64().unwrap() >= 1);
        // ユニット名義の持ち歌も別立てで返る。
        assert!(out["unit_songs"].is_array() && out["unit_songs_total"].is_number());
    }

    #[test]
    fn role_で区分を絞れる() {
        let original = run("idol_songs", json!({ "idol_id": "cg_島村卯月", "role": "original" }));
        assert!(original.get("performed").is_none() && original.get("performed_total").is_none());
        let performed = run("idol_songs", json!({ "idol_id": "cg_島村卯月", "role": "performed" }));
        assert!(performed.get("original").is_none() && performed.get("original_total").is_none());
    }

    #[test]
    fn 知らないアイドルは_not_found() {
        assert!(matches!(
            err("idol_songs", json!({ "idol_id": "存在しないアイドル" })),
            ToolError::NotFound(_)
        ));
        assert!(matches!(err("idol_songs", json!({})), ToolError::BadArgs(_)));
    }

    // ---- song_performances ----

    #[test]
    fn 披露履歴から公演と歌唱者が書ける() {
        // 披露回数の多い曲を実データから選ぶ (id をテストに焼き付けない)。
        let ranking = run("stats", json!({ "kind": "song_play_ranking", "limit": 1 }));
        let song_id = text(&rows(&ranking, "items")[0], "id");

        let out = run("song_performances", json!({ "song_id": song_id, "limit": 10 }));
        let performances = rows(&out, "performances");
        assert_eq!(performances.len(), 10);
        assert!(out["truncated"].as_bool().unwrap());
        assert_eq!(out["total"].as_u64().unwrap(), out["song"]["performance_count"].as_u64().unwrap());

        // 新しい順。
        let dates: Vec<String> = performances.iter().map(|p| text(p, "date")).collect();
        assert!(dates.windows(2).all(|w| w[0] >= w[1]), "新しい順でない: {dates:?}");

        for p in performances {
            assert!(!text(p, "event_name").is_empty());
            assert!(text(p, "ordinal_label").ends_with("回目") || text(p, "ordinal_label") == "初披露");
            assert!(p["singer_count"].is_number());
            // 曲順は公演の中での「何曲目」。生の position (公演をまたぐ通し番号) を
            // そのまま出すと 12852 曲目のような読めない数になる。
            let position = p["position"].as_u64().unwrap();
            assert!((1..=60).contains(&position), "曲順が公演内の番号でない: {p}");
            // 全員で歌った回は名前を並べず full_cast で示す。
            assert!(
                p.get("full_cast").is_some() || p.get("singers").is_some() || p["singer_count"] == json!(0),
                "歌唱者の情報が無い: {p}"
            );
        }
    }

    #[test]
    fn 初披露は_1_回目でなく初披露と呼ぶ() {
        let ranking = run("stats", json!({ "kind": "song_play_ranking", "limit": 1 }));
        let song_id = text(&rows(&ranking, "items")[0], "id");
        let out = run("song_performances", json!({ "song_id": song_id, "limit": 500 }));

        // 履歴は新しい順なので、打ち切ると初披露は必ず行から落ちる。
        // 見出しの first_performance で答えられること (= 限度を上げなくてよいこと) を固定する。
        assert_eq!(out["first_performance"]["ordinal"], json!(1), "{out}");
        assert!(
            out["first_performance"]["date"].as_str().unwrap()
                < out["latest_performance"]["date"].as_str().unwrap()
        );
        // 見出しの「直近」は行の先頭と同じ披露 (別の並びを持ち込んでいない)。
        assert_eq!(out["latest_performance"]["show_id"], rows(&out, "performances")[0]["show_id"]);

        // 行に載っている範囲でも「何回目」の言い方は守られる。
        let newest = &rows(&out, "performances")[0];
        assert!(text(newest, "ordinal_label").ends_with("回目"));
    }

    // ---- setlist_diff ----

    #[test]
    fn 別の公演を比べると共通曲と片方だけの曲が出る() {
        // 同じツアーの 2 公演 (ConnecTrip! の大阪と東京) を比べる。
        let a = tour_show("ev_the_idolmster_cinderella_girls_unit_live_tour_connectrip_大阪公演");
        let b = tour_show("ev_the_idolmster_cinderella_girls_unit_live_tour_connectrip_東京公演");
        let out = run("setlist_diff", json!({ "show_id_a": a, "show_id_b": b }));

        assert!(out["shared_count"].as_u64().unwrap() > 0, "同じツアーで共通曲が 0: {out}");
        let shared = rows(&out, "shared");
        let songs_a = out["a"]["song_count"].as_u64().unwrap();
        let songs_b = out["b"]["song_count"].as_u64().unwrap();
        for song in shared {
            assert!(!text(song, "title").is_empty(), "曲名が解決できていない: {song}");
            // 曲順は公演内の「何曲目」に収まる。
            assert!((1..=songs_a).contains(&song["position_a"].as_u64().unwrap()), "{song}");
            assert!((1..=songs_b).contains(&song["position_b"].as_u64().unwrap()), "{song}");
        }
        // 片方だけの曲にも曲名が付く (id だけ返して呼び直させない)。
        for song in rows(&out, "only_a").iter().chain(rows(&out, "only_b")) {
            assert!(song.get("title").is_some(), "{song}");
        }
        assert!(out["a"]["date"].is_string() && out["b"]["date"].is_string());
    }

    /// イベント id からその配下の最初の公演 id を取る (テストの下ごしらえ)。
    fn tour_show(event_id: &str) -> String {
        let index = bundle_snapshot().event_index_by_id[event_id];
        let show = bundle_snapshot().shows_by_event[index as usize][0];
        bundle_snapshot().shows[show as usize].id.clone()
    }

    // ---- stats ----

    #[test]
    fn 全種別の集計が引ける() {
        for kind in STATS_KINDS {
            let out = run("stats", json!({ "kind": kind }));
            assert_eq!(text(&out, "kind"), kind);
            let items = rows(&out, "items");
            assert!(!items.is_empty(), "{kind} が空");
            for item in items {
                assert!(item.get("id").is_some(), "{kind} の行に id が無い: {item}");
            }
        }
    }

    #[test]
    fn 一番曲数が多かった公演が_1_回で出る() {
        // RedTeam 実測で 11 往復かかっていた問い:
        // 「2024 年のデレマスのライブで一番曲数が多かった公演は?」
        let out = run(
            "stats",
            json!({ "kind": "show_song_count_ranking", "brand": "cg", "year": 2024, "limit": 3 }),
        );
        let items = rows(&out, "items");
        assert!(!items.is_empty());
        let counts: Vec<u64> = items.iter().map(|i| i["song_count"].as_u64().unwrap()).collect();
        assert!(counts.windows(2).all(|w| w[0] >= w[1]), "多い順でない: {counts:?}");

        // 1 行だけで「いつ・どのライブの・どの公演が・何曲」まで書ける。
        let top = &items[0];
        assert!(text(top, "date").starts_with("2024"));
        assert!(!text(top, "event_name").is_empty());
        assert!(!text(top, "show_id").is_empty());
        assert!(top["cast_count"].is_number(), "出演者数も同じ 1 回で: {top}");
        assert!(out["total"].as_u64().unwrap() >= items.len() as u64);
    }

    #[test]
    fn 会場で絞った公演別ランキングも引ける() {
        let out = run(
            "stats",
            json!({ "kind": "show_song_count_ranking", "venue": "横浜アリーナ", "limit": 5 }),
        );
        assert!(out["total"].as_u64().unwrap() > 0);
        for item in rows(&out, "items") {
            assert!(text(item, "venue").contains("横浜アリーナ"), "{item}");
        }
        assert!(matches!(
            err("stats", json!({ "kind": "show_song_count_ranking", "venue": "無い会場" })),
            ToolError::NotFound(_)
        ));
    }

    #[test]
    fn 絞り込みの軸を使えない集計に付けたら弾く() {
        // 黙って無視すると「絞ったつもりの数」を答えてしまう。
        assert!(matches!(
            err("stats", json!({ "kind": "song_play_ranking", "brand": "cg" })),
            ToolError::BadArgs(_)
        ));
    }

    #[test]
    fn 大きな_limit_は大きさで切って理由を返す() {
        // QA 実測: song_play_ranking --limit 1000 が 167KB、list_songs --limit 200 が 132KB。
        let out = run("stats", json!({ "kind": "song_play_ranking", "limit": 1000 }));
        assert_eq!(out["truncated_reason"], json!("size"), "{}", &out.to_string()[..200]);
        assert!(serde_json::to_string(&out).unwrap().len() < 40 * 1024);
        // 総数は切っても返る (「何曲ありますか」には答えられる)。
        assert!(out["total"].as_u64().unwrap() > rows(&out, "items").len() as u64);
    }

    #[test]
    fn 語彙外の集計種別は取りうる値を並べて返す() {
        let ToolError::BadArgs(message) = err("stats", json!({ "kind": "何か" })) else {
            panic!("BadArgs でない")
        };
        for kind in STATS_KINDS {
            assert!(message.contains(kind), "{kind} が候補に無い: {message}");
        }
    }

    // ---- 歌詞は載せない ----

    #[test]
    fn 歌詞本文を返す経路が無い() {
        let out = run("list_songs", json!({ "limit": 50 }));
        for song in rows(&out, "songs") {
            for key in song.as_object().unwrap().keys() {
                assert!(!key.contains("lyric"), "歌詞の欄が混じった: {key}");
            }
        }
    }

    /// 共有 CARGO_TARGET_DIR の成果物混入の回帰ガード (domain のテストと同型)。
    #[test]
    fn test_binary_was_built_from_this_tree() {
        let baked = include_str!("browse.rs");
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/src/agent/tools/browse.rs");
        let on_disk = std::fs::read_to_string(path).unwrap_or_else(|e| {
            panic!("ビルド元ツリーの {path} を読めない = 陳腐化した成果物で検証している: {e}")
        });
        assert!(baked == on_disk, "ビルド元とディスク上の {path} が不一致 = 陳腐化した成果物で検証している");
    }
}
