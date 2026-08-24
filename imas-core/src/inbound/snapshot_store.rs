//! スナップショットの保持と差し替え (FFI 面)。
//!
//! アプリは起動時にこれを 1 個作り、DB パスを渡して load する。CloudKit sync 完了後に
//! reload すると新スナップショットへ原子的に差し替わる (読み手はロック待ちなし・
//! 直前の Arc を掴んでいた呼び出しは古い方を読み切って自然に手放す)。
//! クエリ API は各ドメインのファイル (song_queries.rs 等) が `impl SnapshotStore` を
//! 分割して生やす。ロジックは domain 側に置き、ここと各 impl は委譲に徹する。

use crate::domain::snapshot::Snapshot;
use std::sync::{Arc, RwLock};

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum SnapshotError {
    #[error("スナップショット読み込み失敗: {0}")]
    LoadFailed(String),
    #[error("スナップショット未ロード")]
    NotLoaded,
}

/// ロード結果の要約 (呼び出し側のログ・診断用)。
#[derive(uniffi::Record)]
pub struct SnapshotStats {
    pub songs: u32,
    pub idols: u32,
}

#[derive(uniffi::Object)]
pub struct SnapshotStore {
    inner: RwLock<Option<Arc<Snapshot>>>,
}

#[uniffi::export]
impl SnapshotStore {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self { inner: RwLock::new(None) })
    }

    /// DB を読み切って新スナップショットへ差し替える。失敗時は現行を維持する
    /// (呼び出し側は旧スナップショット or SQL 経路で継続できる)。
    pub fn load(&self, db_path: String) -> Result<SnapshotStats, SnapshotError> {
        let snapshot = crate::outbound::sqlite_loader::load_snapshot(&db_path)
            .map_err(SnapshotError::LoadFailed)?;
        let stats = SnapshotStats {
            songs: snapshot.songs.len() as u32,
            idols: snapshot.idols.len() as u32,
        };
        *self.inner.write().expect("snapshot lock poisoned") = Some(Arc::new(snapshot));
        Ok(stats)
    }

    pub fn is_loaded(&self) -> bool {
        self.inner.read().expect("snapshot lock poisoned").is_some()
    }

    /// メモリ警告時の明示破棄 (次の load まで未ロードに戻る)。
    pub fn unload(&self) {
        *self.inner.write().expect("snapshot lock poisoned") = None;
    }
}

impl SnapshotStore {
    /// クエリ実装 (各 impl 分割ファイル) が現行スナップショットを掴むための内部口。
    pub(crate) fn current(&self) -> Result<Arc<Snapshot>, SnapshotError> {
        self.inner
            .read()
            .expect("snapshot lock poisoned")
            .clone()
            .ok_or(SnapshotError::NotLoaded)
    }
}
