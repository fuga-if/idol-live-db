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
use imas_core::domain::song_list_queries::{song_list_indexes, SongListFilter, SongListSort};
use wasm_bindgen::prelude::*;

/// 組み立て済みの Snapshot を握るハンドル。
///
/// 生テーブルの JSON は 10MB あり、パースと索引構築で数百 ms かかる。呼ぶたびに
/// やり直さないよう、1 度だけ組んで JS 側に持たせる。
#[wasm_bindgen]
pub struct Query {
    snap: Snapshot,
}

/// 絞り込み条件。JS から渡す形。`SongListFilter` と 1:1 で、既定値は
/// **一覧ページを組んだときと同じ**にしてある (`SongListFilter::default` ではない)。
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SongQuery {
    pub brand_ids: Vec<String>,
    pub title: Option<String>,
    pub idol_name: Option<String>,
    pub idol_ids: Vec<String>,
    pub songwriter: Option<String>,
    pub cd_series: Option<String>,
    pub series_group: Option<String>,
    pub live_name: Option<String>,
    pub song_type: Option<String>,
    pub include_remixes: bool,
    pub include_other_brand: bool,
    pub exclude_live_only: bool,
    /// "kana" / "release" / "performance"。未知の値は "kana" に倒す。
    pub sort: String,
    /// 省略時はその並びの既定方向 (`SongListSort::default_ascending`)。
    pub ascending: Option<bool>,
}

impl Default for SongQuery {
    fn default() -> Self {
        Self {
            brand_ids: Vec::new(),
            title: None,
            idol_name: None,
            idol_ids: Vec::new(),
            songwriter: None,
            cd_series: None,
            series_group: None,
            live_name: None,
            song_type: None,
            include_remixes: false,
            include_other_brand: false,
            exclude_live_only: true,
            sort: "kana".to_string(),
            ascending: None,
        }
    }
}

impl SongQuery {
    fn to_filter(&self) -> SongListFilter {
        SongListFilter {
            brand_ids: self.brand_ids.clone(),
            title: self.title.clone(),
            idol_name: self.idol_name.clone(),
            idol_ids: self.idol_ids.clone(),
            songwriter: self.songwriter.clone(),
            cd_series: self.cd_series.clone(),
            series_group: self.series_group.clone(),
            live_name: self.live_name.clone(),
            song_type: self.song_type.clone(),
            include_remixes: self.include_remixes,
            include_other_brand: self.include_other_brand,
            exclude_live_only: self.exclude_live_only,
        }
    }

    fn sort(&self) -> SongListSort {
        match self.sort.as_str() {
            "release" => SongListSort::ReleaseDate,
            "performance" => SongListSort::PerformanceCount,
            _ => SongListSort::TitleKana,
        }
    }
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

    /// 曲の添字列を返す。**絞り込みも並び替えもコアがやる。**
    ///
    /// 返すのは `songs` テーブルの添字なので、受け手は行 id ではなく添字で引く。
    pub fn songs(&self, query_json: &str) -> Result<Vec<u32>, JsValue> {
        let q: SongQuery = serde_json::from_str(query_json)
            .map_err(|e| JsValue::from_str(&format!("条件を読めない: {e}")))?;
        Ok(song_list_indexes(&self.snap, &q.to_filter(), q.sort(), q.ascending, &[], &[]))
    }

    /// 曲の総数 (添字の上限を JS 側で確かめるため)。
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
            let got = query.songs(q).expect(q);
            let want = {
                let sq: SongQuery = serde_json::from_str(q).unwrap();
                imas_core::domain::song_list_queries::song_list_indexes(
                    &from_db, &sq.to_filter(), sq.sort(), sq.ascending, &[], &[],
                )
            };
            assert_eq!(got, want, "条件 {q} で結果が違う");
            assert!(!want.is_empty(), "条件 {q} が 0 件では確かめたことにならない");
        }
    }
}
