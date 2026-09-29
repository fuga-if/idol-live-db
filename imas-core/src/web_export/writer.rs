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
    /// 作成済みのディレクトリ。7,640 ファイルすべてで `create_dir_all` を呼ぶと、
    /// 同じ 10 個ほどのディレクトリに対して毎回 syscall が走る。
    created_dirs: std::collections::HashSet<PathBuf>,
}

impl Writer {
    /// ディレクトリを作り直して書き込みを始める。
    pub fn create(root: &Path, pretty: bool) -> Result<Self> {
        if root.exists() {
            std::fs::remove_dir_all(root)?;
        }
        std::fs::create_dir_all(root)?;
        Ok(Self {
            root: root.to_path_buf(),
            pretty,
            stats: Stats::default(),
            created_dirs: std::collections::HashSet::new(),
        })
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
            if self.created_dirs.insert(parent.to_path_buf()) {
                std::fs::create_dir_all(parent)?;
            }
        }
        // 一時ファイル → rename。書き込み途中で落ちても半端な JSON を残さない。
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, text)?;
        std::fs::rename(&tmp, &path)?;
        self.stats.files += 1;
        self.stats.bytes += text.len() as u64;
        Ok(())
    }

    /// ページ数を数える (ファイル数とは別。1 ページ = 1 URL)。
    pub fn count_pages(&mut self, pages: usize) {
        self.stats.pages += pages;
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
