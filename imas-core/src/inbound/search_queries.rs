//! 横断検索のスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `GlobalSearchReading.search` (実体 `AppDatabase.searchAsync` →
//! `searchQuery`)。ここは domain::search_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_list_queries.rs と同じ):
//! - 1 ユーザー操作 (検索実行) = 1 呼び出し。曲/アイドル/イベントの 3 結果を
//!   `GlobalSearchHits` (表示順の id 列 3 本) にまとめて 1 往復で返す。
//! - 実体化 (Song/Idol/Event の組み立て) はプラットフォーム側が自国の store で行う。
//! - user_marks 非依存なので解決済み id 集合の引数は無い。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::search_queries::{self as queries, GlobalSearchHits};

#[uniffi::export]
impl SnapshotStore {
    /// 横断検索 (曲/アイドル/イベント各 20 件まで・rowid 順)。
    /// SQL 時代の search(query:) 相当。空文字クエリは各テーブル先頭 20 件 (元 SQL と同じ)。
    pub fn global_search(&self, query: String) -> Result<GlobalSearchHits, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::global_search(&snap, &query))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loaded_store() -> std::sync::Arc<SnapshotStore> {
        let store = SnapshotStore::new();
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        store.load(db).expect("bundle DB はロードできる");
        store
    }

    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(store.global_search("夢".into()), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        let hits = store.global_search("夢".into()).unwrap();
        assert_eq!(hits.song_ids.len(), 20, "「夢」は LIMIT いっぱいまで当たる");
        assert!(!hits.idol_ids.is_empty());
        assert!(!hits.event_ids.is_empty());

        let none = store.global_search("zzz存在しない検索語".into()).unwrap();
        assert!(none.song_ids.is_empty() && none.idol_ids.is_empty() && none.event_ids.is_empty());
    }

    /// 共有 CARGO_TARGET_DIR の成果物混入の回帰ガード (domain 側と同型)。
    /// このテストバイナリが「いまディスクにあるこのファイル」から作られたことを照合し、
    /// 別ツリー由来の陳腐化バイナリによる静かな偽合格を落として知らせる。
    #[test]
    fn test_binary_was_built_from_this_tree() {
        let baked = include_str!("search_queries.rs");
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/src/inbound/search_queries.rs");
        let on_disk = std::fs::read_to_string(path).unwrap_or_else(|e| {
            panic!("ビルド元ツリーの {path} を読めない = 陳腐化した成果物で検証している: {e}")
        });
        assert!(baked == on_disk, "ビルド元とディスク上の {path} が不一致 = 陳腐化した成果物で検証している");
    }
}
