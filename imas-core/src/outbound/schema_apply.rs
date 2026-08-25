//! 計画 ([`crate::domain::schema_plan`]) を実際の DB へ流す。
//!
//! ここだけが SQLite を触る。判断は domain 側で済ませてあり、ここは実行に徹する。
//!
//! # 流す前に必ず門を通す
//!
//! [`crate::domain::schema_plan::is_additive_only`] を通らない計画は実行しない。
//! 「消す手を持たない」ことをコードで担保する。ユーザーの担当・お気に入りは
//! クラウドにもサーバにも無いので、消えたら戻せない。

use crate::domain::schema_ddl::MASTER_SCHEMA_SQL;
use crate::domain::schema_plan::{is_additive_only, plan_schema, SchemaPlan};
use rusqlite::Connection;
use std::collections::HashMap;

/// スキーマ適用の結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SchemaApplyResult {
    /// 実際に流した SQL の本数。
    pub applied: u32,
    /// 自動では足せず人の移行に委ねた項目の説明。
    pub deferred: Vec<String>,
    /// 正本に無いので触らなかった表。
    pub untouched_tables: Vec<String>,
}

/// いまの DB から「表名 → 列名の並び」を読む。
fn read_current(conn: &Connection) -> Result<HashMap<String, Vec<String>>, String> {
    let names: Vec<String> = {
        let mut stmt = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table'")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?;
        rows.filter_map(Result::ok).collect()
    };
    let mut out = HashMap::new();
    for t in names {
        let mut stmt = conn
            .prepare(&format!("PRAGMA table_info(\"{t}\")"))
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| r.get::<_, String>(1))
            .map_err(|e| e.to_string())?;
        out.insert(t, rows.filter_map(Result::ok).collect());
    }
    Ok(out)
}

/// マスタスキーマをあるべき形へ寄せる。**追加しかしない**。
///
/// - 無い表を作る / 足りない列を足す
/// - 既にあるものには触らない。消さない。作り直さない
/// - 正本に無い表 (`user_marks` 等の端末ローカル専用) には一切触れない
pub fn ensure_master_schema(db_path: &str) -> Result<SchemaApplyResult, String> {
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    apply_to(&conn)
}

/// 開いた接続に対して適用する (テストと、既に接続を持つ呼び出し側のため)。
pub fn apply_to(conn: &Connection) -> Result<SchemaApplyResult, String> {
    let current = read_current(conn)?;
    let plan = plan_schema(MASTER_SCHEMA_SQL, &current);
    apply_plan(conn, &plan)
}

fn apply_plan(conn: &Connection, plan: &SchemaPlan) -> Result<SchemaApplyResult, String> {
    // 門: 破壊的な手が 1 つでも混ざっていたら何も流さない。
    if !is_additive_only(plan) {
        return Err(
            "破壊的な手が計画に混ざっている。追加以外はコアから流さない (人が移行を書くこと)"
                .to_string(),
        );
    }

    let mut applied = 0u32;
    let mut deferred = Vec::new();
    for change in &plan.changes {
        if change.sql.is_empty() {
            deferred.push(change.reason.clone());
            continue;
        }
        conn.execute_batch(&change.sql)
            .map_err(|e| format!("{} で失敗: {e}", change.reason))?;
        applied += 1;
    }
    Ok(SchemaApplyResult {
        applied,
        deferred,
        untouched_tables: plan.extra_tables.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cols(conn: &Connection, table: &str) -> Vec<String> {
        let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})")).unwrap();
        let rows = stmt.query_map([], |r| r.get::<_, String>(1)).unwrap();
        rows.filter_map(Result::ok).collect()
    }

    /// まっさらな DB に流すと、正本どおりの形になる。
    #[test]
    fn builds_the_whole_schema_from_scratch() {
        let conn = Connection::open_in_memory().unwrap();
        let r = apply_to(&conn).unwrap();
        assert!(r.applied > 20, "流した本数={}", r.applied);

        let reference = Connection::open_in_memory().unwrap();
        reference.execute_batch(MASTER_SCHEMA_SQL).unwrap();
        let names = |c: &Connection| -> Vec<String> {
            let mut s = c
                .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
                .unwrap();
            let rows = s.query_map([], |r| r.get::<_, String>(0)).unwrap();
            rows.filter_map(Result::ok).collect()
        };
        assert_eq!(names(&conn), names(&reference));
        for t in names(&reference) {
            assert_eq!(cols(&conn, &t), cols(&reference, &t), "`{t}` の列が違う");
        }
    }

    /// 既に正しい DB に流しても何も起きない (冪等)。
    #[test]
    fn is_idempotent() {
        let conn = Connection::open_in_memory().unwrap();
        apply_to(&conn).unwrap();
        let second = apply_to(&conn).unwrap();
        // 表・列は全部あるので、流すのは索引の IF NOT EXISTS だけ
        assert!(second.deferred.is_empty(), "{:?}", second.deferred);
        let mut s = conn.prepare("SELECT COUNT(*) FROM sqlite_master WHERE type='table'").unwrap();
        let n: i64 = s.query_row([], |r| r.get(0)).unwrap();
        assert!(n > 15, "表が消えている: {n}");
    }

    /// 足りない列だけが足される。
    #[test]
    fn adds_only_the_missing_column() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE brands (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL);",
        )
        .unwrap();
        conn.execute("INSERT INTO brands (id, name) VALUES ('cg','シンデレラ')", []).unwrap();
        apply_to(&conn).unwrap();

        let after = cols(&conn, "brands");
        assert!(after.contains(&"color".to_string()), "{after:?}");
        // 既存の行は残っている
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM brands", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1, "既存データが消えた");
    }

    /// **端末ローカル専用の表とデータに一切触れない。**
    ///
    /// `user_marks` はクラウドにもサーバにも無く、消えたら戻せない。
    /// ここが落ちたら、コアからスキーマを流す仕組み自体を止めること。
    #[test]
    fn never_touches_local_only_data() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE user_marks (entity_type TEXT, entity_id TEXT, kind TEXT, bool_value INTEGER);
             CREATE TABLE personal_tags (entity_type TEXT, entity_id TEXT, tag_name TEXT);",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO user_marks VALUES ('idol','cg_shimamura','myPick',1)", []).unwrap();
        conn.execute(
            "INSERT INTO personal_tags VALUES ('song','s1','好き')", []).unwrap();

        let r = apply_to(&conn).unwrap();
        assert!(r.untouched_tables.contains(&"user_marks".to_string()), "{:?}", r.untouched_tables);

        let marks: i64 = conn.query_row("SELECT COUNT(*) FROM user_marks", [], |r| r.get(0)).unwrap();
        let tags: i64 = conn.query_row("SELECT COUNT(*) FROM personal_tags", [], |r| r.get(0)).unwrap();
        assert_eq!(marks, 1, "担当マークが消えた");
        assert_eq!(tags, 1, "マイタグが消えた");
        // 列も増やされていない
        assert_eq!(cols(&conn, "user_marks").len(), 4);
    }

    /// 破壊的な計画は門で止まる。
    #[test]
    fn destructive_plan_is_refused() {
        use crate::domain::schema_plan::SchemaChange;
        let conn = Connection::open_in_memory().unwrap();
        let bad = SchemaPlan {
            changes: vec![SchemaChange {
                sql: "DROP TABLE user_marks;".to_string(),
                table: "user_marks".to_string(),
                reason: "悪意ある手".to_string(),
            }],
            extra_tables: vec![],
        };
        assert!(apply_plan(&conn, &bad).is_err(), "破壊的な手を通してはいけない");
    }

    /// 実際の同梱 DB に流しても、データが減らない。
    #[test]
    fn applying_to_the_real_database_changes_nothing() {
        let src = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        let dir = std::env::temp_dir().join(format!("imas_schema_apply_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let dst = dir.join("copy.sqlite");
        let _ = std::fs::remove_file(&dst);
        std::fs::copy(&src, &dst).unwrap();

        let conn = Connection::open(&dst).unwrap();
        let before: i64 = conn.query_row("SELECT COUNT(*) FROM songs", [], |r| r.get(0)).unwrap();
        let r = apply_to(&conn).unwrap();
        let after: i64 = conn.query_row("SELECT COUNT(*) FROM songs", [], |r| r.get(0)).unwrap();

        assert_eq!(before, after, "曲が増減した");
        assert!(r.deferred.is_empty(), "人に委ねた項目がある: {:?}", r.deferred);
        let _ = std::fs::remove_file(&dst);
    }
}
