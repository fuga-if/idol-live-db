//! 検索索引 (`search/*.json`) と、畳み込みパリティ (`parity/fold.json`) の DTO。

use super::common::RefKind;
use serde::{Deserialize, Serialize};

/// シャードの一覧 (`search/manifest.json`)。
/// island はまずこれを読み、4 本を並列取得する。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SearchManifest {
    pub schema_version: u32,
    pub shards: Vec<SearchShardMeta>,
}

/// シャード 1 本のメタ。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SearchShardMeta {
    pub kind: RefKind,
    /// 取得先 (`/search/songs.json`)。
    ///
    /// フィールド名が `path` でないのは、**JSON 中の `path` は必ずページの URL**、
    /// という不変条件を全体で保つため (到達性テストが `path` を機械的に辿れる)。
    /// これはページではなくデータファイルの場所なので `url` にしてある。
    pub url: String,
    /// セクション見出しに出す日本語 (「楽曲」「アイドル」…)。
    pub label: String,
    pub count: u32,
    pub bytes: u32,
}

/// 検索索引の 1 シャード。
///
/// **照合の式はブラウザ側の `row.f.includes(foldedQuery)` 1 行だけ。**
/// 前方一致優先やスコアリングを足さない。並びは各シャードの元の並び
/// (= コアが決めた順) をそのまま保つ。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SearchShard {
    pub schema_version: u32,
    pub kind: RefKind,
    /// 畳み済みフィールドの区切り (`"\u{0001}"`)。
    ///
    /// 連結して 1 本にするとフィールド境界をまたぐ偽陽性が出る
    /// (`TextSearchIndex` がフィールドを連結しない理由と同じ)。検索語にこの文字は
    /// 入らないので、区切りを挟んだ `includes` は `TextSearchIndex::matches` と等価になる。
    /// **定数だが JSON に明示する** — ブラウザ側に規則をハードコードさせないため。
    pub sep: String,
    /// 行の href を組む前置き (`"/songs/"`)。
    /// href は `pathPrefix + encodeURIComponent(row.k) + "/"`。これは**配管であって規則ではない**
    /// (規則側の判断 = 危険な id をどう安全化するかは `row.k` に織り込み済み)。
    pub path_prefix: String,
    pub rows: Vec<SearchRow>,
}

/// 索引の 1 行。キーを 1 文字にしてあるのは、4 シャード合計で 1MB 級になるため。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SearchRow {
    /// 表示名。
    pub n: String,
    /// 補助表記 (曲=ユニット名 / ライブ=年 / 会場=都道府県 / アイドル=ブランド名)。
    pub s: Option<String>,
    /// URL セグメントの素材。
    ///
    /// **生の id とは限らない**: 危険な文字を含む id はフォールバック slug に落ちており、
    /// ここにはその結果 (= `url::path_key` の出力) が入る。生 id を使うと該当ページが
    /// 404 になるので、href はこの値だけから組むこと。
    pub k: String,
    /// 畳み済みフィールドを `sep` で連結したもの。
    pub f: String,
}

/// 畳み込みのパリティ用フィクスチャ (`parity/fold.json`)。
///
/// wasm 版 (Plan W) でも TS 移植版 (Plan F) でも、これを全件通すのが検収になる。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct FoldParity {
    pub schema_version: u32,
    pub cases: Vec<FoldCase>,
}

/// 入力と、コアが畳んだ結果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct FoldCase {
    #[serde(rename = "in")]
    pub input: String,
    #[serde(rename = "out")]
    pub output: String,
}
