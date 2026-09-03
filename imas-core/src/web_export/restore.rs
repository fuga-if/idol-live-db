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
    // dump は BEGIN TRANSACTION / COMMIT を含むので execute_batch がそのまま使える。
    conn.execute_batch(&sql).map_err(|e| WebExportError::Db(e.to_string()))?;
    conn.close().map_err(|(_, e)| WebExportError::Db(e.to_string()))?;
    Ok(())
}

/// dump の内容指紋。`shasum -a 256 db/master.sql` と同じ値。
///
/// `build_db.sh` が `meta.content_hash` に入れているのと**同じ規則**にしてある。
/// 版番号 (`data_version`) は人が管理する数字で内容とズレることがある (実際にズレて
/// 配信が止まった) ので、Web でも「内容が変われば必ず変わる」指紋の方を持っておく。
pub fn content_hash(sql_path: &Path) -> Result<String> {
    Ok(sha256_hex_bytes(&std::fs::read(sql_path)?))
}
