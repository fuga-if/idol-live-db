//! 検索索引 (`search/*.json`) と、畳み込みパリティ (`parity/fold.json`) の DTO。

use super::common::{RefKind, SeoBlock};

web_dto! {
    /// 検索ページ (`/search/`, `index/search.json`) の文面。
    ///
    /// 検索の中身 (索引) は `search/*.json` で、ここはページの見出し・説明・`<head>` だけ。
    /// 歌詞検索を出すかどうかで言うことが変わるので、文面も Rust が持つ
    /// (`content::LYRICS_ON_WEB` を見る)。
    pub struct SearchPage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        /// 見出しの下の説明。
        pub lede: String,
        /// 種別ごとに並べる件数の上限 (`domain::search_limits::WEB_SEARCH_LIMIT_PER_KIND`)。
        pub limit_per_kind: u32,
        /// 歌詞を探す最小文字数 (`domain::search_limits::WEB_LYRICS_SEARCH_MIN_CHARS`)。
        pub lyrics_min_chars: u32,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// シャードの一覧 (`search/manifest.json`)。
    /// island はまずこれを読み、4 本を並列取得する。
    #[derive(Eq)]
    pub struct SearchManifest {
        pub schema_version: u32,
        pub shards: Vec<SearchShardMeta>,
    }
}

web_dto! {
    /// シャード 1 本のメタ。
    #[derive(Eq)]
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
}

web_dto! {
    /// 検索索引の 1 シャード。
    ///
    /// **照合の式はブラウザ側の `row.f.includes(foldedQuery)` 1 行だけ。**
    /// 前方一致優先やスコアリングを足さない。並びは各シャードの元の並び
    /// (= コアが決めた順) をそのまま保つ。
    #[derive(Eq)]
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
}

web_dto! {
    /// 索引の 1 行。キーを 1 文字にしてあるのは、4 シャード合計で 1MB 級になるため。
    #[derive(Eq)]
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
        /// 生の id。**`k` と違うときだけ入る** (危険な文字を含む id がフォールバック slug に
        /// 落ちた行)。歌詞検索の結果 (API は生の id で返す) をこの行に結び付けるために要る。
        /// 出さないときは鍵ごと省く (4 シャード合計 1MB 級なので、空の鍵を全行に足さない)。
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub i: Option<String>,
    }
}

web_dto! {
    /// 畳み込みのパリティ用フィクスチャ (`parity/fold.json`)。
    ///
    /// wasm 版 (Plan W) でも TS 移植版 (Plan F) でも、これを全件通すのが検収になる。
    #[derive(Eq)]
    pub struct FoldParity {
        pub schema_version: u32,
        pub cases: Vec<FoldCase>,
    }
}

web_dto! {
    /// 入力と、コアが畳んだ結果。
    #[derive(Eq)]
    pub struct FoldCase {
        #[serde(rename = "in")]
        pub input: String,
        #[serde(rename = "out")]
        pub output: String,
    }
}
