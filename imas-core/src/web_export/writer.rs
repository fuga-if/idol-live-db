//! 出力ディレクトリへの書き込みと、その統計。

use super::{Result, Stats, WebExportError};
use serde::Serialize;
use std::path::{Path, PathBuf};

/// 出力ディレクトリ 1 個ぶんの書き込み口。
///
/// **`--out` は毎回まるごと作り直す。** 差分更新をしないのは、消えたレコードのページが
/// 前回の出力として残るのを構造的に防ぐため (残っていても誰も気付けない類の事故になる)。
pub struct Writer {
    root: PathBuf,
    pretty: bool,
    stats: Stats,
}

impl Writer {
    /// ディレクトリを作り直して書き込みを始める。
    pub fn create(root: &Path, pretty: bool) -> Result<Self> {
        if root.exists() {
            std::fs::remove_dir_all(root)?;
        }
        std::fs::create_dir_all(root)?;
        Ok(Self { root: root.to_path_buf(), pretty, stats: Stats::default() })
    }

    /// JSON を 1 本書く。`rel` は出力ルートからの相対パス。
    pub fn write_json<T: Serialize>(&mut self, rel: &str, value: &T) -> Result<()> {
        let text = if self.pretty {
            serde_json::to_string_pretty(value)?
        } else {
            serde_json::to_string(value)?
        };
        self.write_text(rel, &text)
    }

    /// テキストを 1 本書く (`themes.css` 用)。
    pub fn write_text(&mut self, rel: &str, text: &str) -> Result<()> {
        let path = self.resolve(rel)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        // 一時ファイル → rename。書き込み途中で落ちても半端な JSON を残さない。
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, text)?;
        std::fs::rename(&tmp, &path)?;
        self.stats.files += 1;
        self.stats.bytes += text.len() as u64;
        Ok(())
    }

    /// ページを 1 枚数える (ファイル数とは別。1 ページ = 1 URL)。
    pub fn count_page(&mut self) {
        self.stats.pages += 1;
    }

    /// フォールバック slug に落ちた id を 1 件数える。
    pub fn count_fallback_slug(&mut self) {
        self.stats.fallback_slugs += 1;
    }

    pub fn stats(&self) -> &Stats {
        &self.stats
    }

    pub fn into_stats(self) -> Stats {
        self.stats
    }

    /// 相対パスを出力ルート配下に解決する。`..` で外に出ようとしたら不変条件違反。
    fn resolve(&self, rel: &str) -> Result<PathBuf> {
        if rel.starts_with('/') || rel.split('/').any(|seg| seg == ".." || seg.is_empty()) {
            return Err(WebExportError::Invariant(format!("出力先が不正: {rel}")));
        }
        Ok(self.root.join(rel))
    }
}
