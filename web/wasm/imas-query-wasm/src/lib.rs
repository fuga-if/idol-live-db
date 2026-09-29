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
