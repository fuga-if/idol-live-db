//! テストが読む実データ DB を用意する。
//!
//! - 既定: 正本の `db/master.sql` から復元した SQLite。CI と同じ入力で、手元の
//!   `ImasLiveDB/Resources/master.sqlite` (作り直していないと古い) には左右されない。
//! - `IMAS_CORE_TEST_DB=<path>`: その SQLite をそのまま読む (同梱 DB で確かめたいときなど)。
//!
//! 復元はプロセスをまたいで 1 回にする。target の下に dump の内容ごとの名前で置き、
//! 同じ dump なら次のプロセスはそれを開くだけ。一時ファイルに書いてから rename するので、
//! 並んで走ったテストが書きかけの DB を読むことはない。
//!
//! `tools/build_db.sh` のゲート (FK・data_version・公式順) と content_hash はここでは掛けない。
//! どれも「アプリに同梱してよいか」の検査で、コアのテストの入力には関係しない
//! (`web_export::restore` と同じ扱い)。
//!
//! lib のテストと `tests/web_export.rs` の両方から使うので、std と rusqlite にだけ依存する。

use std::hash::{DefaultHasher, Hasher};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// 読む DB を差し替える環境変数。
pub const TEST_DB_ENV: &str = "IMAS_CORE_TEST_DB";

/// テストが読む DB のパス。最初の呼び出しで用意し、以降は同じ値を返す。
/// 用意できなければ、何が足りないかを書いて panic する。
pub fn path() -> &'static str {
    static PATH: OnceLock<String> = OnceLock::new();
    PATH.get_or_init(|| prepare().unwrap_or_else(|message| panic!("\n{message}\n")))
}

fn prepare() -> Result<String, String> {
    if let Some(path) = std::env::var_os(TEST_DB_ENV) {
        let path = PathBuf::from(path);
        if !path.is_file() {
            return Err(format!("{TEST_DB_ENV}={} が無い。SQLite のファイルを指すこと。", path.display()));
        }
        return Ok(path.display().to_string());
    }
    let dump = Path::new(env!("CARGO_MANIFEST_DIR")).join("../db/master.sql");
    let sql = std::fs::read_to_string(&dump).map_err(|e| {
        format!(
            "実データの正本 {} を読めない ({e})。\n\
             コアのテストは、これを SQLite に復元して読む。\n\
             別の DB で走らせるなら {TEST_DB_ENV}=<.sqlite のパス> を付ける。\n\
             `bash tools/build_db.sh` は手元で流さないこと (同梱 DB を作り直すかはオーナーが決める)。",
            dump.display()
        )
    })?;
    let dir = cache_dir();
    let db = dir.join(format!("master-{:016x}.sqlite", fingerprint(&sql)));
    if !db.is_file() {
        restore(&sql, &dir, &db)?;
    }
    Ok(db.display().to_string())
}

/// 復元した DB の置き場所 (`<target>/<profile>/test-db`)。target ごと消せば一緒に消える。
fn cache_dir() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.parent()?.join("test-db")))
        .unwrap_or_else(|| std::env::temp_dir().join("imas-core-test-db"))
}

/// dump の内容が変わったら作り直すための指紋。暗号学的である必要は無い。
fn fingerprint(sql: &str) -> u64 {
    let mut hasher = DefaultHasher::new();
    hasher.write(sql.as_bytes());
    hasher.finish()
}

/// dump を `conn` に流し込む。
///
/// 外部キーは先に切る。dump は表を名前順に作って入れるので、最初の INSERT
/// (anniversaries) が、まだ無い brands を参照する。SQLite の既定は OFF だが、
/// Linux の bundled SQLite は ON でビルドされていて、そこで `no such table: main.brands`
/// になる (macOS だけ緑に見える)。トランザクションの中では PRAGMA が効かないので、
/// dump の BEGIN より前に流す。`web_export::restore` も同じ。
pub(super) fn load_dump(conn: &rusqlite::Connection, sql: &str) -> rusqlite::Result<()> {
    conn.pragma_update(None, "foreign_keys", false)?;
    // dump は BEGIN TRANSACTION / COMMIT を含むので execute_batch がそのまま使える。
    conn.execute_batch(sql)
}

/// dump を一時ファイルに流し込み、できあがってから `db` へ rename する。
/// 古い dump から作った DB はそのとき消す (置き場所に溜めない)。
fn restore(sql: &str, dir: &Path, db: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("{} を作れない: {e}", dir.display()))?;
    let tmp = db.with_extension(format!("sqlite.tmp-{}", std::process::id()));
    let _ = std::fs::remove_file(&tmp);
    let conn = rusqlite::Connection::open(&tmp).map_err(|e| format!("{} を作れない: {e}", tmp.display()))?;
    load_dump(&conn, sql).map_err(|e| format!("db/master.sql を復元できない: {e}"))?;
    conn.close().map_err(|(_, e)| format!("{} を閉じられない: {e}", tmp.display()))?;
    std::fs::rename(&tmp, db).map_err(|e| format!("{} を置けない: {e}", db.display()))?;
    for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let stale = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if stale != db && name.starts_with("master-") && name.ends_with(".sqlite") {
            let _ = std::fs::remove_file(stale);
        }
    }
    Ok(())
}

