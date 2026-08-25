//! 共有コアが持つ**マスタスキーマの正本**。
//!
//! Phase 7 (スキーマ所有権の移転) の第二段。第一段 ([`crate::domain::schema_registry`]) は
//! 「あるべき表と列」の台帳で、ずれの**検出**だけを担当した。ここはさらに進んで、
//! **スキーマそのもの (DDL)** をコアが持つ。
//!
//! # まだ実行は奪っていない
//!
//! 移行の実行は今も各 OS (GRDB / Room)。ここが持つのは「あるべき最終形」で、
//! テストが「この DDL から作った DB が、同梱 master.sqlite と同じ形になる」ことを保証する。
//! **その保証が取れて初めて**、各 OS の移行をこの DDL の適用へ置き換えられる。
//!
//! いきなり実行まで移すと、`user_marks` (クラウドにもサーバにも無い端末唯一データ) を
//! 壊したときに復旧手段が無い。順序を踏むのはそのため。
//!
//! # ここに載るのはマスタだけ
//!
//! 端末ローカル専用の `user_marks` / `personal_tags` は**含めない**。あれらは
//! 配布物 (同梱 DB) に器すら置かず、各 OS が自分で作る。コアがマスタ側の DDL を
//! 流しても、ローカルデータの表には一切触れない — これが「壊さない」ことの担保になる。

/// マスタスキーマの DDL (CREATE TABLE / CREATE INDEX)。
///
/// 同梱 `master.sqlite` から起こしたもの。**手で書き換えず**、スキーマを変えるときは
/// `db/master.sql` を直してからここへ取り込み直す (テストが差を検出する)。
pub const MASTER_SCHEMA_SQL: &str = include_str!("master_schema.sql");

/// DDL に現れる表名を順に返す。
pub fn table_names() -> Vec<String> {
    MASTER_SCHEMA_SQL
        .lines()
        .filter_map(|l| {
            let l = l.trim_start();
            let rest = l.strip_prefix("CREATE TABLE ")?;
            // 表名は引用符つきで書かれることがある (SQLite が ALTER 後に書き戻す形)。
            let name = rest.split(['(', ' ']).next()?.trim().trim_matches('"');
            (!name.is_empty()).then(|| name.to_string())
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::{Connection, OpenFlags};
    use std::collections::BTreeMap;

    /// 「表名 → (列名, 型, NOT NULL, 既定値) の並び」を読む。
    /// 列の順序も含めて比べたいので Vec のまま持つ。
    fn schema_of(conn: &Connection) -> BTreeMap<String, Vec<String>> {
        let names: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
                .unwrap();
            let rows = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap();
            rows.filter_map(Result::ok).collect()
        };
        let mut out = BTreeMap::new();
        for t in names {
            let mut stmt = conn.prepare(&format!("PRAGMA table_info({t})")).unwrap();
            let cols: Vec<String> = stmt
                .query_map([], |r| {
                    Ok(format!(
                        "{} {} notnull={} default={:?} pk={}",
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, i64>(3)?,
                        r.get::<_, Option<String>>(4)?,
                        r.get::<_, i64>(5)?
                    ))
                })
                .unwrap()
                .filter_map(Result::ok)
                .collect();
            out.insert(t, cols);
        }
        out
    }

    fn bundle() -> Connection {
        let p = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        Connection::open_with_flags(p, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap()
    }

    /// **この DDL から作った DB が、同梱 master.sqlite と同じ形になること。**
    ///
    /// ここが落ちたら、`db/master.sql` を変えたのにコアの DDL を取り込み直していない。
    /// スキーマ所有権をコアへ移す前提が崩れるので、必ず追随させること。
    #[test]
    fn ddl_reproduces_the_bundled_schema() {
        let fresh = Connection::open_in_memory().unwrap();
        fresh.execute_batch(MASTER_SCHEMA_SQL).expect("DDL が流せる");

        let a = schema_of(&fresh);
        let b = schema_of(&bundle());

        let only_ddl: Vec<&String> = a.keys().filter(|k| !b.contains_key(*k)).collect();
        let only_bundle: Vec<&String> = b.keys().filter(|k| !a.contains_key(*k)).collect();
        assert!(only_ddl.is_empty(), "DDL にだけ在る表: {only_ddl:?}");
        assert!(only_bundle.is_empty(), "同梱 DB にだけ在る表: {only_bundle:?}");

        for (table, cols) in &b {
            assert_eq!(a.get(table), Some(cols), "`{table}` の列がずれている");
        }
    }

    /// 索引も再現できること (性能の前提なので形だけでなく索引まで見る)。
    #[test]
    fn ddl_reproduces_the_indexes() {
        let fresh = Connection::open_in_memory().unwrap();
        fresh.execute_batch(MASTER_SCHEMA_SQL).unwrap();
        let read = |c: &Connection| -> Vec<String> {
            let mut stmt = c
                .prepare("SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name")
                .unwrap();
            let rows = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap();
            rows.filter_map(Result::ok).collect()
        };
        assert_eq!(read(&fresh), read(&bundle()), "索引がずれている");
    }

    /// 端末ローカル専用の表が DDL に混ざっていないこと。
    ///
    /// 混ざると、コアがスキーマを流したときにユーザーの担当/お気に入りの器を
    /// 作り直してしまう余地が生まれる。**ここは絶対に空でなければならない**。
    #[test]
    fn local_only_tables_are_not_in_the_master_ddl() {
        let tables = table_names();
        for forbidden in ["user_marks", "personal_tags"] {
            assert!(
                !tables.iter().any(|t| t == forbidden),
                "端末ローカル専用の `{forbidden}` がマスタ DDL に入っている"
            );
        }
    }

    /// 台帳 (schema_registry) が挙げるマスタ表は、DDL にも在ること。
    /// 2 つの定義がすれ違わないようにする。
    #[test]
    fn registry_and_ddl_agree_on_master_tables() {
        use crate::domain::schema_registry::{expected_tables, TableOrigin};
        let ddl = table_names();
        let missing: Vec<String> = expected_tables()
            .into_iter()
            .filter(|t| t.origin == TableOrigin::Master)
            .filter(|t| !ddl.contains(&t.name))
            .map(|t| t.name)
            .collect();
        assert!(missing.is_empty(), "台帳にあって DDL に無いマスタ表: {missing:?}");
    }
}
