//! 一覧の絞り込み・並べ替えをブラウザで行うための薄いラッパ。
//!
//! **規則はここに無い。** やることは 3 つだけ:
//!   1. Web 出面が配った生テーブル (JSON) を `RawTables` に戻す
//!   2. `snapshot_build::build` で Snapshot を組む (索引はここで組み直す。派生は配らない)
//!   3. `song_list_indexes` などコアの関数をそのまま呼び、添字列を返す
//!
//! 条件の解釈も並び順も `imas-core` の domain が持っているので、アプリと web で
//! 結果が食い違う余地が無い。事前計算していた頃は「軸ごとの集合を配って受け手が積を取る」
//! 形だったため、軸を増やすたびに配る側の作り込みが要った。

use imas_core::domain::snapshot::Snapshot;
use imas_core::domain::snapshot_build::{self, RawTables};
use imas_core::domain::song_list_queries::{
    song_list_indexes, song_list_sort_options_without_user_marks, SongQuery,
};
use imas_core::domain::{idol_queries, song_detail_queries};
use wasm_bindgen::prelude::*;

/// 組み立て済みの Snapshot を握るハンドル。
///
/// 生テーブルの JSON は 10MB あり、パースと索引構築で数百 ms かかる。呼ぶたびに
/// やり直さないよう、1 度だけ組んで JS 側に持たせる。
#[wasm_bindgen]
pub struct Query {
    snap: Snapshot,
}

/// 選択肢 1 件。value は `SongQuery` にそのまま渡す文字列。
#[derive(serde::Serialize)]
struct Opt {
    value: String,
    label: String,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Facets {
    brands: Vec<Opt>,
    idols: Vec<Opt>,
    cd_series: Vec<Opt>,
    series_groups: Vec<Opt>,
    /// 並べ替えの選択肢。既定方向もコアが持つ値をそのまま渡す。
    sorts: Vec<SortOpt>,
}

/// 並べ替え 1 件。
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct SortOpt {
    key: String,
    label: String,
    default_ascending: bool,
}

/// 表示名がそのまま条件になる列 (CD シリーズ・シリーズ) の選択肢。
fn same_value_options(names: Vec<String>) -> Vec<Opt> {
    names.into_iter().map(|v| Opt { value: v.clone(), label: v }).collect()
}

#[wasm_bindgen]
impl Query {
    /// 生テーブルの JSON から組む。**索引はここで組み直す** (配られたものは使わない)。
    #[wasm_bindgen(constructor)]
    pub fn new(tables_json: &str) -> Result<Query, JsValue> {
        let raw: RawTables = serde_json::from_str(tables_json)
            .map_err(|e| JsValue::from_str(&format!("生テーブルを読めない: {e}")))?;
        Ok(Query { snap: snapshot_build::build(raw) })
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

    /// 絞り込みの選択肢。**中身を決めるのは Snapshot** で、JS は並べるだけ。
    ///
    /// 値そのもの (ブランド id・アイドル id・CD シリーズ名) はコアが持つ文字列を
    /// そのまま返す。JS 側で組み立て直すと `SongQuery` に渡す値がズレる。
    pub fn facets(&self) -> Result<String, JsValue> {
        // **選択肢を組む関数はアプリと同じもの**を呼ぶ。ここで snap を自前で
        // 走査すると、並びだけが他の画面と違う一覧になる (実際にアイドルは
        // rowid 順・シリーズは辞書順になっていて、アプリのピッカーと食い違っていた)。
        let brands = idol_queries::brand_records(&self.snap)
            .into_iter()
            .map(|b| Opt { value: b.id, label: b.name })
            .collect();
        let idols = idol_queries::all_idols_for_picker(&self.snap)
            .into_iter()
            .map(|i| Opt { value: i.id, label: i.name })
            .collect();
        let cd_series = same_value_options(
            song_detail_queries::album_summaries(&self.snap, &[], None)
                .into_iter()
                .map(|a| a.cd_series)
                .collect(),
        );
        let series_groups =
            same_value_options(song_detail_queries::series_group_names(&self.snap, &[]));
        let sorts = song_list_sort_options_without_user_marks()
            .into_iter()
            .map(|o| SortOpt {
                key: o.key,
                label: o.label,
                default_ascending: o.default_ascending,
            })
            .collect();

        serde_json::to_string(&Facets { brands, idols, cd_series, series_groups, sorts })
            .map_err(|e| JsValue::from_str(&format!("選択肢を組めない: {e}")))
    }

    /// 曲の総数。
    pub fn song_count(&self) -> usize {
        self.snap.songs.len()
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
    fn 配った生テーブルから組んでもDBから組んだのと同じ結果になる() {
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
            assert!(!want.is_empty(), "条件 {q} が 0 件では確かめたことにならない");
        }
    }
}
