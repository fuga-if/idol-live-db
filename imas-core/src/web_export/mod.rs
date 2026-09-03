//! Web 出面 (静的サイト) 用の JSON エクスポータ。
//!
//! ## この層の責務 (これ以外を書かない)
//!
//! ここは **driving adapter** であって業務規則の置き場ではない。やってよいのは 3 つだけ:
//!
//! 1. `domain::*` の関数を呼ぶ
//! 2. 返り値を serde 構造体 ([`dto`]) に詰め替える
//! 3. 文字列の整形 (hex 化・URL セグメント化・秒→"4:32")
//!
//! 「どのレコードを出すか / どう並べるか / どう畳むか / どんな色にするか」を
//! **ここで決めてはいけない**。判断が要るものは `domain` に `pub fn` を足してから呼ぶ。
//! Astro (TypeScript) 側はさらに厳しく、JSON のフィールドを HTML の要素に置く以外を
//! 一切しない。だから DTO は「そのまま描ける形」まで作り込んである
//! (例: [`dto::Ref::path`] は encode 済みの完成形 URL。TS はこれを href に入れるだけ)。
//!
//! ## 新しい `#[uniffi::export]` は足さない
//!
//! FFI 面 (`tests/ffi_surface.rs` の一覧) は不変。ここは lib の中だが uniffi を通らない
//! 普通の Rust モジュールなので、iOS/Android のバインディングには一切現れない。
//!
//! ## ts-rs の出力先について
//!
//! DTO には `#[ts(export, export_to = "../../web/src/lib/schema/")]` が付いていて、
//! `cargo test --features web-export` が TS 型を書き出す。**`export_to` の基準は
//! `TS_RS_EXPORT_DIR` (既定 `<CARGO_MANIFEST_DIR>/bindings/`) であって crate ルートではない。**
//! つまり `../../` の 1 段目が `bindings/` を抜けるぶんで、2 段目でリポジトリルートに出る:
//!
//! ```text
//!   imas-core/bindings/ + ../../web/src/lib/schema/  =  <repo>/web/src/lib/schema/
//! ```
//!
//! ここを 1 段間違えると `imas-core/web/src/...` という別物が生えるので、
//! 版を上げるときは実際に出力先を目で見て確かめること。

pub mod content;
pub mod dto;
pub mod emit;
pub mod fixture;
pub mod restore;
pub mod theme;
pub mod url;
pub mod writer;

use std::path::PathBuf;

/// エクスポータの実行時エラー。終了コードは `main.rs` がこれから決める。
#[derive(Debug, thiserror::Error)]
pub enum WebExportError {
    #[error("引数エラー: {0}")]
    Args(String),
    #[error("DB エラー: {0}")]
    Db(String),
    #[error("出力エラー: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON エラー: {0}")]
    Json(#[from] serde_json::Error),
    #[error("不変条件違反: {0}")]
    Invariant(String),
}

impl WebExportError {
    /// プロセスの終了コード。CI がどの段階で落ちたかを exit code だけで判別できるようにする。
    pub fn exit_code(&self) -> i32 {
        match self {
            Self::Args(_) => 1,
            Self::Db(_) => 2,
            Self::Io(_) | Self::Json(_) => 3,
            Self::Invariant(_) => 4,
        }
    }
}

pub type Result<T> = std::result::Result<T, WebExportError>;

/// CLI 引数。clap を入れないのは、引数がこれだけで増える予定も無いから。
#[derive(Debug, Clone, Default)]
pub struct Args {
    /// `db/master.sql` (dump)。`db` と排他。
    pub sql: Option<PathBuf>,
    /// 既にある .sqlite を直接読む。`sql` と排他。
    pub db: Option<PathBuf>,
    /// `--sql` のときの中間 DB の置き場。
    pub work_db: Option<PathBuf>,
    /// 出力ディレクトリ (毎回まるごと作り直す)。
    pub out: Option<PathBuf>,
    /// JST の「今日」を固定する (テスト・再現用)。`YYYY-MM-DD`。
    pub today: Option<String>,
    /// 整形して書く (既定は minify)。
    pub pretty: bool,
    /// DB を読まず、各 DTO の代表値だけを書き出して終了する。
    /// web-coder が Astro を先行実装するためのフィクスチャ。
    pub emit_fixture: Option<PathBuf>,
    /// 出力せず、手書きフィクスチャが DTO でデシリアライズできるかだけ検証して終了する。
    pub fixture_check: Option<PathBuf>,
}

/// 書き出しの統計。stderr に出して CI から見える化する。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Stats {
    pub pages: usize,
    pub files: usize,
    pub bytes: u64,
    /// フォールバック slug に落ちた id の件数。
    pub fallback_slugs: usize,
    /// うち、危険な文字・予約語が理由のもの (データ側を直すべき)。
    pub fallback_unsafe: usize,
    /// うち、長すぎるのが理由のもの (URL が読めなくなるだけ)。
    pub fallback_too_long: usize,
}

/// エクスポータ本体。
pub fn run(args: &Args) -> Result<Stats> {
    if let Some(dir) = &args.emit_fixture {
        return fixture::emit(dir, args.pretty);
    }
    if let Some(dir) = &args.fixture_check {
        return fixture::check(dir);
    }
    emit::run(args)
}
