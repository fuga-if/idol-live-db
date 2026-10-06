//! 一覧の絞り込み・並べ替えをブラウザで行うための薄いラッパ。
//!
//! **規則はここに無い。** やることは 3 つだけ:
//!   1. Web 出面が配った生テーブル (JSON) を `RawTables` に戻す
//!   2. `snapshot_build::build` で Snapshot を組む (索引はここで組み直す。派生は配らない)
//!   3. `song_list_indexes` / `list_facets` などコアの関数をそのまま呼び、結果を JSON で返す
//!
//! 条件の解釈も並び順も、選択肢の集合も `imas-core` の domain が持っているので、アプリと web で
//! 結果が食い違う余地が無い。選択肢の型 (`SongFacets` / `IdolFacets`) も domain にあり、
//! TS 側の型は ts-rs が出す。

use imas_core::domain::snapshot::Snapshot;
use imas_core::domain::snapshot_build::{self, RawTables};
use imas_core::domain::song_list_queries::{song_list_indexes, SongQuery};
use imas_core::domain::idol_list_filtering::{
    filter_idol_list, idol_list_entries, sort_idol_list, IdolListEntry, IdolQuery,
};
use imas_core::domain::producer_card::{
    card_link_view, card_qr_link_view, decode_producer_card, producer_card_display_design,
    producer_card_face, CardLinkView, CardOshiEntry,
};
use imas_core::domain::{idol_queries, list_facets};
use wasm_bindgen::prelude::*;

/// 組み立て済みの Snapshot を握るハンドル。
///
/// 生テーブルの JSON は 10MB あり、パースと索引構築で数百 ms かかる。呼ぶたびに
/// やり直さないよう、1 度だけ組んで JS 側に持たせる。
#[wasm_bindgen]
pub struct Query {
    snap: Snapshot,
    /// アイドル一覧の行。`filter_idol_list` は行の列を渡す形なので、
    /// 打鍵のたびに組み直さないよう 1 度だけ作る。
    idol_entries: Vec<IdolListEntry>,
    /// idol_id → 現任 CV 名。検索対象なので条件に毎回渡す。
    cast_names: std::collections::HashMap<String, String>,
}

#[wasm_bindgen]
impl Query {
    /// 生テーブルの JSON から組む。**索引はここで組み直す** (配られたものは使わない)。
    #[wasm_bindgen(constructor)]
    pub fn new(tables_json: &str) -> Result<Query, JsValue> {
        let raw: RawTables = serde_json::from_str(tables_json)
            .map_err(|e| JsValue::from_str(&format!("生テーブルを読めない: {e}")))?;
        let snap = snapshot_build::build(raw);
        let idol_entries = idol_list_entries(&snap);
        let cast_names = idol_queries::idol_cast_names(&snap);
        Ok(Query { snap, idol_entries, cast_names })
    }

    /// 条件に合う曲 id を、並び順どおりに返す。**絞り込みも並び替えもコアがやる。**
    ///
    /// 添字ではなく id を返すのは、ページの行と Snapshot の添字を結び付けないため。
    /// 添字で渡すと、配った生テーブルとページの生成が同じ版であることが暗黙の前提になる。
    pub fn song_ids(&self, query_json: &str) -> Result<Vec<String>, JsValue> {
        let q: SongQuery = serde_json::from_str(query_json)
            .map_err(|e| JsValue::from_str(&format!("条件を読めない: {e}")))?;
        let indexes =
            song_list_indexes(&self.snap, &q.to_filter(), q.sort_order(), q.ascending, &[], &[]);
        Ok(indexes.iter().map(|&i| self.snap.songs[i as usize].id.clone()).collect())
    }

    /// 楽曲一覧の選択肢 (`list_facets::SongFacets` の JSON)。**中身を決めるのは domain** で、JS は並べるだけ。
    pub fn facets(&self) -> Result<String, JsValue> {
        to_json(&list_facets::song_facets(&self.snap, &self.idol_entries))
    }

    /// 条件に合うアイドル id を、並び順どおりに返す。
    ///
    /// 曲と同じで、**絞り込みも並べ替えもコアがやる**。アプリの
    /// `filter_idol_list` / `sort_idol_list` をそのまま通す。
    pub fn idol_ids(&self, query_json: &str) -> Result<Vec<String>, JsValue> {
        let q: IdolQuery = serde_json::from_str(query_json)
            .map_err(|e| JsValue::from_str(&format!("条件を読めない: {e}")))?;
        let kept = filter_idol_list(&self.idol_entries, &q.to_criteria(self.cast_names.clone()));
        // 絞ったあとの行を並べ替える (アプリと同じ順序: 絞る → 並べる)。
        let kept_entries: Vec<IdolListEntry> =
            kept.iter().map(|&i| self.idol_entries[i as usize].clone()).collect();
        let order = sort_idol_list(&kept_entries, q.sort_kind(), q.ascending);
        Ok(order.iter().map(|&i| kept_entries[i as usize].idol_id.clone()).collect())
    }

    /// アイドル一覧の選択肢 (`list_facets::IdolFacets` の JSON)。
    pub fn idol_facets(&self) -> Result<String, JsValue> {
        to_json(&list_facets::idol_facets(&self.snap, &self.idol_entries))
    }

    /// 曲の総数。
    pub fn song_count(&self) -> usize {
        self.snap.songs.len()
    }
}

fn to_json(value: &impl serde::Serialize) -> Result<String, JsValue> {
    serde_json::to_string(value).map_err(|e| JsValue::from_str(&format!("選択肢を組めない: {e}")))
}

// ---------------------------------------------------------------------------
// P名刺 (`/p/`) — Snapshot を要らない、入口だけの読み解き。
// ---------------------------------------------------------------------------
//
// 名刺の形式の正は `imas_core::domain::producer_card`。ここは `decode_producer_card` /
// `card_link_view` を呼んで、ページがそのまま描ける形の JSON に詰め替えるだけ
// (TS には読み解きの判断を 1 行も書かせない)。
// `Query` (Snapshot 組み直し) を経由しないのは、名刺の読み解きが生テーブル
// (10MB 級) を要らないため。名刺ページはこれだけを wasm から呼ぶ。

/// 名刺の中身をそのまま描ける形にしたもの。フィールド名は JS 側で camelCase になる
/// (`#[serde(rename_all = "camelCase")]`)。
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct CardView {
    name: String,
    message: String,
    since_year: Option<u16>,
    /// `p/catalog.json` の `idols` と突き合わせる。並び順は名刺の並び順のまま。
    oshi_idol_ids: Vec<String>,
    /// `card_link_view` まで通した形 (label/display/url)。TS は URL を組まない。
    links: Vec<CardLinkView>,
    show_count: Option<u32>,
    song_count: Option<u32>,
    /// `p/catalog.json` の `upcomingShows` と突き合わせる。今後の公演でなければ
    /// (台帳に無ければ) ページ側が欄ごと出さない。
    next_show_id: Option<String>,
    attended_count: u32,
    attended_truncated: bool,
    /// `"YYYY.MM.DD 時点"`。`issued_on` (`YYYY-MM-DD`、producer_card が保証する形) を
    /// 区切りだけ変えたもの (日付の規則ではなく表記の整形なので wasm 側でやる)。
    issued_on_display: String,
    /// 名刺のデザインのキー (`card_design_info().key`。既定のデザインも必ず入る)。
    /// Web は自作の画像を持たない (QR に画像は入らない) ので、自作の画像の名刺は入場証になる。
    /// ページは `data-design` に置き、CSS が並びと同梱の書体 (`/fonts/card/`) を引く。
    design: String,
    /// 自分の QR (リンクの 1 本の形。題は「QR」)。無ければ `null`。
    qr_link: Option<CardLinkView>,
}

/// 名刺の URL (または `#` の後ろだけ) を読み解く。名刺でなければ `null`。
#[wasm_bindgen]
pub fn decode_producer_card_json(text: &str) -> Result<JsValue, JsValue> {
    let Some(card) = decode_producer_card(text) else {
        return Ok(JsValue::NULL);
    };
    let design = producer_card_display_design(&card, false).key;
    let qr_link = card.qr_url.as_deref().map(card_qr_link_view);
    let view = CardView {
        name: card.name,
        message: card.message,
        since_year: card.since_year,
        oshi_idol_ids: card.oshi_idol_ids,
        links: card.links.iter().map(card_link_view).collect(),
        show_count: card.show_count,
        song_count: card.song_count,
        next_show_id: card.next_show_id,
        attended_count: card.attended.len() as u32,
        attended_truncated: card.attended_truncated,
        issued_on_display: issued_on_display(&card.issued_on),
        design,
        qr_link,
    };
    let json = to_json(&view)?;
    Ok(JsValue::from_str(&json))
}

/// 名刺の表 (91:55) に載せるもの (`producer_card_face`: 表に並べる担当をブランドごとにまとめたもの・
/// 判子の下の 1 行・数で畳んだ人数・ハンドル 1 つ・P 歴の印字)。`drawable_json` は台帳
/// (`p/catalog.json`) にある担当の `CardOshiEntry` の配列の JSON (`[{idolId, name, brandId, brandLabel}]`。
/// ページが台帳から詰めたもの)。名刺でなければ `null`。
#[wasm_bindgen]
pub fn producer_card_face_json(text: &str, drawable_json: &str) -> Result<JsValue, JsValue> {
    let Some(card) = decode_producer_card(text) else {
        return Ok(JsValue::NULL);
    };
    let drawable: Vec<CardOshiEntry> =
        serde_json::from_str(drawable_json).map_err(|e| JsValue::from_str(&e.to_string()))?;
    let json = to_json(&producer_card_face(&card, &drawable))?;
    Ok(JsValue::from_str(&json))
}

/// `"2026-10-06"` → `"2026.10.06 時点"`。既に `YYYY-MM-DD` である前提
/// (`producer_card::encode_producer_card` が保証する) で、壊れていれば原文を出す。
fn issued_on_display(issued_on: &str) -> String {
    let parts: Vec<&str> = issued_on.split('-').collect();
    match parts.as_slice() {
        [y, m, d] => format!("{y}.{m}.{d} 時点"),
        _ => issued_on.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ブラウザで組んだ Snapshot が、DB から組んだものと同じ絞り込み結果を返すこと。
    ///
    /// **この出面の正しさの根拠。** 生テーブルだけを配って受け手が `build` で
    /// 組み直す方式なので、「配ったもので組んだ Snapshot」と「DB から組んだ Snapshot」が
    /// 同じ答えを出すことを固定しておく。ズレたら派生の組み直しが壊れている。
    #[test]
    fn tables_shipped_to_the_browser_give_the_same_answers_as_the_db() {
        let db = format!("{}/../../../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        let raw = imas_core::outbound::sqlite_loader::load_raw_tables(&db).expect("生テーブル");
        let from_db = imas_core::outbound::sqlite_loader::load_snapshot(&db).expect("DB から");

        // 配る経路と同じく JSON を経由させる (serde の往復も含めて確かめる)。
        let json = serde_json::to_string(&raw).expect("JSON にできる");
        let query = Query::new(&json).expect("生テーブルから組める");

        assert_eq!(query.song_count(), from_db.songs.len());

        for q in [
            r#"{}"#,
            r#"{"brandIds":["ml"]}"#,
            r#"{"brandIds":["ml"],"songType":"solo"}"#,
            r#"{"sort":"performance"}"#,
            r#"{"sort":"release","ascending":true}"#,
            r#"{"songwriter":"BNSI"}"#,
            r#"{"title":"みらい"}"#,
        ] {
            let got = query.song_ids(q).expect(q);
            let want: Vec<String> = {
                let sq: SongQuery = serde_json::from_str(q).unwrap();
                imas_core::domain::song_list_queries::song_list_indexes(
                    &from_db, &sq.to_filter(), sq.sort_order(), sq.ascending, &[], &[],
                )
                .iter()
                .map(|&i| from_db.songs[i as usize].id.clone())
                .collect()
            };
            assert_eq!(got, want, "条件 {q} で結果が違う");
        }

        // アイドル一覧も同じく、DB から組んだ Snapshot と同じ結果になること。
        let db_entries = idol_list_entries(&from_db);
        let db_casts = idol_queries::idol_cast_names(&from_db);
        for q in [
            r#"{}"#,
            r#"{"brandIds":["cg"]}"#,
            r#"{"attribute":"cute"}"#,
            r#"{"birthMonth":3}"#,
            r#"{"searchText":"はるか"}"#,
            r#"{"sort":"height"}"#,
            r#"{"sort":"kana","ascending":true}"#,
            r#"{"brandIds":["ml"],"birthMonth":7,"sort":"age"}"#,
        ] {
            let got = query.idol_ids(q).expect(q);
            let want: Vec<String> = {
                let iq: IdolQuery = serde_json::from_str(q).unwrap();
                let kept = filter_idol_list(&db_entries, &iq.to_criteria(db_casts.clone()));
                let kept_entries: Vec<IdolListEntry> =
                    kept.iter().map(|&i| db_entries[i as usize].clone()).collect();
                sort_idol_list(&kept_entries, iq.sort_kind(), iq.ascending)
                    .iter()
                    .map(|&i| kept_entries[i as usize].idol_id.clone())
                    .collect()
            };
            assert_eq!(got, want, "アイドルの条件 {q} で結果が違う");
            assert!(!want.is_empty(), "条件 {q} が 0 件では確かめたことにならない");
        }
    }
}
