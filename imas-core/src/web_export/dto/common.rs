//! 全ページで共有する DTO。
//!
//! 共通規約 (全 DTO に効く):
//! * `#[serde(rename_all = "camelCase")]`
//! * `Option<T>` に `skip_serializing_if` を **付けない**。常にキーを出して TS 側を
//!   `T | null` に固定する (キー欠落と null を区別しなくて済む)。空の `Vec` も出す。
//! * 整数は `i32` / `u32` のみ。`i64` / `u64` を使わないのは、`JSON.parse` が number を
//!   返すのに ts-rs の既定が `bigint` になり、TS 側で無用な変換が要るため。
//!   (実データの最大値は setlist_items 13,762 件・秒数・容量のいずれも i32 に収まる)


/// JSON スキーマの版。TS ローダはこれが一致しない JSON を読んだら即 throw する。
///
/// **上げるときは 3 箇所を同時に直すこと。**片方だけ上げると、古い `web/data` を
/// 読んだまま新しい形として描いてしまう (壊れ方が「一部のフィールドが undefined」に
/// なるので、ビルドは通って画面だけ静かに崩れる):
///
/// 1. ここ (`imas-core/src/web_export/dto/common.rs`)
/// 2. `web/src/lib/data.ts` — JSON 読み込みの唯一の入口。不一致なら throw する
/// 3. `web/scripts/require-data.mjs` — ビルド前に `web/data` の版を確かめる
pub const SCHEMA_VERSION: u32 = 1;

web_dto! {
    /// サイト全体のメタ (`meta.json`)。
    pub struct SiteMeta {
        pub schema_version: u32,
        /// RFC3339 UTC。`--today` から導出する (`YYYY-MM-DDT00:00:00Z`)。
        /// 実時刻を入れないのは、同じ入力で 2 回流したときに出力がバイト一致する
        /// (= 再現性がある) ことをテストで固定したいから。
        pub generated_at: String,
        /// JST の「今日」。upcoming / past の分割はすべてこの 1 個から決まる。
        /// Astro もブラウザも `Date` を触らない。
        pub today_jst: String,
        pub data_version: Option<String>,
        pub content_hash: Option<String>,
        pub counts: Counts,
        pub app: AppLinks,
    }
}

web_dto! {
    /// 各コレクションの件数。トップの統計タイルと `/about/` が使う。
    #[derive(Copy, Eq)]
    pub struct Counts {
        pub events: u32,
        pub shows: u32,
        pub songs: u32,
        pub idols: u32,
        pub units: u32,
        pub venues: u32,
        pub brands: u32,
        pub setlist_items: u32,
    }
}

web_dto! {
    /// アプリ / 外部サイトへのリンク集。値の正はこの 1 箇所だけ。
    #[derive(Eq)]
    pub struct AppLinks {
        pub app_store_url: String,
        /// Google Play は 2026-09-04 時点で 404 のため `None`。出面にリンクを出さない。
        pub play_store_url: Option<String>,
        /// 公式 X アカウント。
        ///
        /// `Option` のままにしてあるのは、**リンクを出すかどうかの判断をデータ側に置く**ため。
        /// TS は「あればリンクを出す」だけを書けばよく、アカウントを畳んだり移したりしても
        /// 出面のコードを触らずに済む (Google Play を `None` にしてあるのと同じ扱い)。
        pub x_url: Option<String>,
        pub privacy_url: String,
        pub support_url: String,
        pub terms_url: String,
        pub repository_url: String,
    }
}

web_dto! {
    /// 他ページへのリンク 1 個。
    ///
    /// **web はこれ以上の情報から href を組み立てない。** [`Self::path`] をそのまま
    /// `href` に入れる。エンコードのコードを TS に書かせないための型。
    #[derive(Eq)]
    pub struct Ref {
        pub kind: RefKind,
        /// 生の id (アプリ連携・deeplink 用)。**href の材料にしない。**
        pub id: String,
        pub name: String,
        /// 補助表記 (公演なら日付、曲ならユニット名 等)。
        pub sub: Option<String>,
        /// 先頭・末尾スラッシュ付きの完成形 URL (percent-encode 済み)。
        pub path: String,
        /// `themes.css` のセレクタキー (`idol:<id>` / `brand:<id>` / `neutral`)。
        /// HTML は `data-theme` 属性にこれを 1 個置くだけでよい。
        pub theme_key: String,
        /// ジャケ画像 (Apple Music CDN)。曲以外は常に `None`。
        /// **これがサイト唯一の外部画像**で、版権物はこれ以外に載せない。
        pub artwork_url: Option<String>,
        /// アバター代わりの 1 文字 (アプリの `ImasAvatar` と同じ)。**必ず入る。**
        ///
        /// アイドルとユニットは表示名の先頭 1 文字、ブランドは短縮名の先頭 1 文字。
        /// 画像を載せない (版権物ゼロ) ので、これが唯一の「顔」になる。
        ///
        /// `Option` にしていないのは、TS 側から `?? name.slice(0, 1)` を消すため。
        /// 先頭 1 文字の切り出しは書記素クラスタの扱いが言語ごとに違うので、
        /// **切る場所を決めるのは 1 箇所**でなければならない。曲・ライブ・公演・会場でも
        /// 同じ規則で埋まるが、これらは表示に使わない。
        pub monogram: String,
    }
}

web_dto! {
    /// [`Ref`] が指す先の種別。
    #[derive(Copy, Eq)]
    pub enum RefKind {
        Event,
        Show,
        Song,
        Idol,
        Unit,
        Venue,
        Brand,
    }
}

impl RefKind {
    /// URL の第 1 セグメント (`/songs/…` の `songs`)。
    pub fn collection(self) -> &'static str {
        match self {
            Self::Event => "events",
            Self::Show => "shows",
            Self::Song => "songs",
            Self::Idol => "idols",
            Self::Unit => "units",
            Self::Venue => "venues",
            Self::Brand => "brands",
        }
    }
}

web_dto! {
    /// 「アプリで開く」導線。
    ///
    /// Web は閲覧専用なので、状態を持つ操作 (参加記録・投票・タグ・歌詞・コール) は
    /// すべてここからアプリへ送る。
    #[derive(Eq)]
    pub struct AppOpen {
        pub app_store_url: String,
        /// `imaslivedb://events/<id>` 等。**event / show にしか無い**
        /// (`DeeplinkRouter` が受けるのは events / shows / polls の 3 種だけ)。
        pub deeplink: Option<String>,
        /// 「参加記録・投票・歌詞・タグはアプリで」等の固定文。
        pub note: String,
    }
}

web_dto! {
    /// 検索エンジンへの指示。
    ///
    /// `other` ブランド (ラブライブ等、他フランチャイズの合同ライブ楽曲) 配下は
    /// [`Self::NoindexFollow`] にする。非公式ファンサイトが他フランチャイズ名で
    /// 検索流入を取りにいかないための判断で、**判断は Rust 側で済ませ**、Astro は
    /// `<meta name="robots">` と sitemap の filter に写すだけにする。
    #[derive(Copy, Eq)]
    pub enum Robots {
        #[serde(rename = "index,follow")]
        IndexFollow,
        #[serde(rename = "noindex,follow")]
        NoindexFollow,
    }
}

web_dto! {
    /// `<head>` に入れるものと、パンくず。
    pub struct SeoBlock {
        pub title: String,
        pub description: String,
        /// 絶対 URL。
        pub canonical: String,
        /// OGP 画像の絶対 URL。
        pub og_image: String,
        pub robots: Robots,
        /// `<script type="application/ld+json">` にそのまま流し込む値。
        /// 構造の判断 (どの型を出すか) は Rust 側で済ませてある。
        ///
        /// TS 型を手で指定しているのは、ts-rs の `serde-json-impl` に任せると
        /// `JsonValue` が `<CARGO_MANIFEST_DIR>/bindings/` に落ち、生成された `.ts` が
        /// `web/` の外を `import` しに行くため (Astro の tsconfig の外に出る)。
        /// JSON-LD の最上位は必ずオブジェクトなので、この 1 行で十分。
        #[ts(type = "Record<string, unknown>")]
        pub json_ld: serde_json::Value,
        pub breadcrumbs: Vec<Crumb>,
    }
}

web_dto! {
    /// パンくずの 1 要素。
    #[derive(Eq)]
    pub struct Crumb {
        pub name: String,
        pub path: String,
    }
}

web_dto! {
    /// 件数タイル 1 枚。
    ///
    /// どの件数を、どの順で、どのラベルとグリフで出すかは**そのページの意味の判断**なので
    /// Rust が決める。`Counts` を素で配って .astro が表を組むと、同じ表が画面ごとに
    /// コピーされ、実際にトップ 6 件・About 7 件・ブランド 4 件で中身が食い違っていた。
    #[derive(Eq)]
    pub struct StatTile {
        /// 見出しの記号 (`♪` `▤` `♬` …)。版権物を持たないので記号で見分ける。
        pub glyph: String,
        pub value: u32,
        pub label: String,
        /// 一覧への入口。押せないタイルは `None`。
        pub href: Option<String>,
    }
}

web_dto! {
    /// 一覧ページ間の切替リンク (ブランド別など)。
    ///
    /// クライアント状態を持たせないため、切替は必ず「別ページへのリンク」になる。
    #[derive(Eq)]
    pub struct NavLink {
        pub label: String,
        pub path: String,
        /// いま見ているページか (`aria-current="page"` を付ける材料)。
        pub current: bool,
        /// ブランド切替のときだけ入る。行にブランド色を当てるのに使う。
        pub theme_key: Option<String>,
        /// 件数を出せるときだけ入る。
        pub count: Option<u32>,
    }
}

impl NavLink {
    /// 押せる切替リンク 1 本。`current` は後から [`mark_current`] でまとめて立てる。
    pub fn new(label: &str, path: impl Into<String>) -> Self {
        Self { label: label.to_string(), path: path.into(), current: false, theme_key: None, count: None }
    }

    pub fn with_count(mut self, count: u32) -> Self {
        self.count = Some(count);
        self
    }

    pub fn with_theme(mut self, theme_key: String) -> Self {
        self.theme_key = Some(theme_key);
        self
    }
}

/// いま見ているページに当たるリンクへ `current` を立てる。
///
/// 各リンクを作るときに `path == current` を書くと、切替リンクを組む場所すべてに
/// 同じ比較が散る (実データでは 5 種類の一覧が同じことをしていた)。組み終わってから
/// 1 回で立てる。
pub fn mark_current(links: &mut [NavLink], current: &str) {
    for link in links {
        link.current = link.path == current;
    }
}

web_dto! {
    /// テーマトークン表 (`themes.json`)。
    ///
    /// 実際に配るのは Rust が書き出す単一の `themes.css` (`[data-theme="idol:xxx"]{…}`) で、
    /// この JSON は **CSS の生成元 + テスト用の突き合わせ材料**として置く。
    /// 出面がインライン style を配らないのは、CSP に `unsafe-inline` を要らなくするため。
    pub struct ThemeTable {
        pub schema_version: u32,
        /// キーは `idol:<idolId>` / `brand:<brandId>` / `neutral`。
        /// `BTreeMap` なのは出力をバイト一致で再現するため (`HashMap` を serde しない)。
        pub themes: std::collections::BTreeMap<String, ThemePair>,
    }
}

web_dto! {
    /// 1 テーマぶんのライト / ダーク。
    #[derive(Eq)]
    pub struct ThemePair {
        pub light: ThemeTokens,
        pub dark: ThemeTokens,
    }
}

web_dto! {
    /// `color_engine::derive(seed, brand, dark)` の結果を hex にしたもの。
    ///
    /// **ブランド id を seed に渡してはいけない** (`first_valid_hex` の doc: `"876"` が
    /// `#887766` として通ってしまう)。渡すのは `brands.color` の値だけ。
    #[derive(Eq)]
    pub struct ThemeTokens {
        pub accent: String,
        pub on_accent: String,
        pub tint: String,
        pub tint_strong: String,
        pub chip_bg: String,
        pub chip_text: String,
        pub ring: String,
        pub bar: String,
        pub dot: String,
        pub grad_from: String,
        pub grad_to: String,
        pub separator: String,
        pub hero_surface: String,
    }
}
