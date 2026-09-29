//! 実データを読むテストの入口。DB のパスを直書きせず、ここを通す。
//!
//! どの DB を読むかは [`test_db`] が決める (既定は `db/master.sql` から復元したもの。
//! `IMAS_CORE_TEST_DB` で差し替えられる)。

pub(crate) mod test_db;

use crate::domain::snapshot::Snapshot;
use crate::inbound::snapshot_store::SnapshotStore;
use crate::outbound::sqlite_loader::load_snapshot;
use rusqlite::{Connection, OpenFlags};
use std::sync::{Arc, OnceLock};

/// 実データ DB のパス。
pub(crate) fn bundle_path() -> &'static str {
    test_db::path()
}

/// 実データのスナップショット。全テストで 1 つを共有する (不変なので安全で、ロードも 1 回で済む)。
pub(crate) fn bundle_snapshot() -> &'static Snapshot {
    static SNAP: OnceLock<Snapshot> = OnceLock::new();
    SNAP.get_or_init(|| load_snapshot(bundle_path()).expect("実データ DB からスナップショットを組める"))
}

/// 実データ DB への読み取り専用の接続 (SQL と突き合わせるテスト用)。
pub(crate) fn bundle_conn() -> Connection {
    Connection::open_with_flags(
        bundle_path(),
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .expect("実データ DB を開ける")
}

/// 実データを読み込んだ SnapshotStore (inbound の委譲を確かめるテスト用)。呼ぶたびに新しく作る。
pub(crate) fn bundle_store() -> Arc<SnapshotStore> {
    let store = SnapshotStore::new();
    store.load(bundle_path().to_string()).expect("実データ DB を SnapshotStore に読み込める");
    store
}

#[cfg(test)]
mod tests {
    // test_db.rs は tests/web_export.rs にも #[path] で入るので、2 回走らないようこちらに置く。
    use super::test_db::load_dump;
    use std::path::Path;

    /// 外部キーが既定で ON の SQLite (Linux の bundled) でも復元できる。
    #[test]
    fn restores_the_dump_even_when_foreign_keys_default_on() {
        let dump = Path::new(env!("CARGO_MANIFEST_DIR")).join("../db/master.sql");
        let sql = std::fs::read_to_string(dump).unwrap();
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.pragma_update(None, "foreign_keys", true).unwrap();
        load_dump(&conn, &sql).unwrap();
        let brands: i64 = conn.query_row("SELECT COUNT(*) FROM brands", [], |r| r.get(0)).unwrap();
        assert!(brands > 0);
    }
}
