//! `db/master.sql` (dump) から作業用の SQLite を作る。
//!
//! `tools/build_db.sh` に相当する処理を Rust で行う。build_db.sh を呼ばないのは、
//! あちらの出力先が `ImasLiveDB/Resources/master.sqlite` 固定でアプリ同梱物を上書き
//! してしまうため。Web の出力は Web の作業ディレクトリで完結させる。
//!
//! FK 整合のゲートは掛けない。`sqlite_loader` が FK 孤児を読み飛ばす契約になっており、
//! 「アプリに同梱してよいか」はアプリ側の関心事だから (build_db.sh 側で守られている)。
//! `data_version` のゲートも掛けない。reseed 判定はアプリ固有で、Web には無関係。

use super::{Result, WebExportError};
use crate::domain::sha256::sha256_hex_bytes;
use std::path::Path;

/// dump を流し込んで `work_db` を作り直す。
pub fn restore(sql_path: &Path, work_db: &Path) -> Result<()> {
    let sql = std::fs::read_to_string(sql_path)?;
    if let Some(parent) = work_db.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // 作り直す。前回の残骸に新しい dump を重ねると、消えた行が残る。
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", work_db.display()));
    }
    let conn = rusqlite::Connection::open(work_db).map_err(|e| WebExportError::Db(e.to_string()))?;
    load_dump(&conn, &sql).map_err(|e| WebExportError::Db(e.to_string()))?;
    conn.close().map_err(|(_, e)| WebExportError::Db(e.to_string()))?;
    Ok(())
}

/// dump を `conn` に流し込む。
///
/// 外部キーは先に切る。dump は表を名前順に作って入れるので、最初の INSERT
/// (anniversaries) が、まだ無い brands を参照する。Linux の bundled SQLite は外部キーが
/// 既定で ON で、そこで `no such table: main.brands` になり `npm run export` が落ちる
/// (macOS は既定 OFF なので緑に見える)。トランザクションの中では PRAGMA が効かないので、
/// dump の BEGIN より前に流す。テスト用の復元 (`test_support::test_db`) も同じ。
fn load_dump(conn: &rusqlite::Connection, sql: &str) -> rusqlite::Result<()> {
    conn.pragma_update(None, "foreign_keys", false)?;
    // dump は BEGIN TRANSACTION / COMMIT を含むので execute_batch がそのまま使える。
    conn.execute_batch(sql)
}

/// dump の内容指紋。`shasum -a 256 db/master.sql` と同じ値。
///
/// `build_db.sh` が `meta.content_hash` に入れているのと**同じ規則**にしてある。
/// 版番号 (`data_version`) は人が管理する数字で内容とズレることがある (実際にズレて
/// 配信が止まった) ので、Web でも「内容が変われば必ず変わる」指紋の方を持っておく。
pub fn content_hash(sql_path: &Path) -> Result<String> {
    Ok(sha256_hex_bytes(&std::fs::read(sql_path)?))
}

#[cfg(test)]
mod tests {
    use super::*;

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
