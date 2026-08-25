//! 「いまの DB を、あるべきスキーマへ近づけるには何をすればよいか」の**計画**。
//!
//! Phase 7 の最終段。ここまでで台帳 ([`crate::domain::schema_registry`]) と
//! 正本の DDL ([`crate::domain::schema_ddl`]) をコアが持った。ここはその DDL へ
//! 寄せるための手順を組み立てる。実際に流すのは [`crate::outbound::schema_apply`]。
//!
//! # 追加しかしない
//!
//! 出す手は `CREATE TABLE` と `ALTER TABLE ADD COLUMN` の 2 つだけ。
//! **DROP も、作り直しも、データの書き換えも計画しない。**
//!
//! これは実装の都合ではなく安全の設計。`user_marks` (担当・お気に入り・メモ・参加) は
//! クラウドにもサーバにも無い端末唯一データで、壊すと復旧手段が無い。
//! 「消す手を持たない」ようにしておけば、どんな順序で走っても消えようがない。
//!
//! 型変更や列の削除が要る場面は将来あり得るが、そのときは**人が移行を書く**。
//! 自動で作り直す仕組みを持たせない方が、事故の上限が低い。
//!
//! # 余分な表・列は放置する
//!
//! DB 側にあって DDL に無いものは、**報告するが触らない**。
//! 端末ローカル専用の表 (`user_marks` / `personal_tags`)、コミュニティ投稿の表、
//! 各 OS が自分の都合で持つ表がそこに含まれるため。

use std::collections::HashMap;

/// 実行すべき 1 手。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SchemaChange {
    /// 流す SQL。
    pub sql: String,
    /// 対象の表。
    pub table: String,
    /// 何のための手かの説明 (ログと診断用)。
    pub reason: String,
}

/// 計画の結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SchemaPlan {
    /// 流すべき SQL の並び (この順で実行する)。
    pub changes: Vec<SchemaChange>,
    /// DB 側にあって正本に無いもの。**触らない**が、気づけるように返す。
    pub extra_tables: Vec<String>,
}

/// DDL 文字列から「表名 → (CREATE 文, 列名の並び)」を取り出す。
///
/// SQLite の DDL は表名を引用符で囲むことがある (ALTER 後に書き戻される形)。
fn parse_ddl(ddl: &str) -> (Vec<(String, String)>, HashMap<String, Vec<(String, String)>>) {
    let mut creates = Vec::new();
    let mut columns: HashMap<String, Vec<(String, String)>> = HashMap::new();

    for stmt in ddl.split(';') {
        let trimmed = stmt.trim();
        if trimmed.is_empty() {
            continue;
        }
        let upper = trimmed.to_uppercase();
        if !upper.starts_with("CREATE TABLE") {
            // 索引はそのまま流す手として後段で扱う
            if upper.starts_with("CREATE INDEX") || upper.starts_with("CREATE UNIQUE INDEX") {
                creates.push((String::new(), format!("{trimmed};")));
            }
            continue;
        }
        let after = &trimmed["CREATE TABLE".len()..];
        let name_end = after.find('(').unwrap_or(after.len());
        let name = after[..name_end].trim().trim_matches('"').to_string();
        creates.push((name.clone(), format!("{trimmed};")));

        // 列名と定義を拾う (括弧の入れ子と、テーブル制約の行は除く)
        let body = &after[name_end..];
        let inner = body.trim().trim_start_matches('(').trim_end_matches(')');
        let mut depth = 0i32;
        let mut current = String::new();
        let mut defs = Vec::new();
        for ch in inner.chars() {
            match ch {
                '(' => { depth += 1; current.push(ch) }
                ')' => { depth -= 1; current.push(ch) }
                ',' if depth == 0 => { defs.push(current.trim().to_string()); current.clear() }
                _ => current.push(ch),
            }
        }
        if !current.trim().is_empty() {
            defs.push(current.trim().to_string());
        }
        let cols: Vec<(String, String)> = defs
            .into_iter()
            .filter(|d| {
                let u = d.to_uppercase();
                // 表制約の行は列ではない
                !(u.starts_with("PRIMARY KEY")
                    || u.starts_with("UNIQUE")
                    || u.starts_with("FOREIGN KEY")
                    || u.starts_with("CHECK")
                    || u.starts_with("CONSTRAINT"))
            })
            .filter_map(|d| {
                let col = d.split_whitespace().next()?.trim_matches('"').to_string();
                (!col.is_empty()).then_some((col, d))
            })
            .collect();
        columns.insert(name, cols);
    }
    (creates, columns)
}

/// 正本 DDL といまの DB の状態から、実行すべき手を組み立てる。
///
/// `current` は「表名 → 列名の並び」の実測。
pub fn plan_schema(ddl: &str, current: &HashMap<String, Vec<String>>) -> SchemaPlan {
    let (creates, columns) = parse_ddl(ddl);
    let mut changes = Vec::new();

    for (table, sql) in &creates {
        if table.is_empty() {
            // 索引。CREATE INDEX は IF NOT EXISTS を挟んで冪等にする
            let idempotent = sql.replacen("CREATE INDEX ", "CREATE INDEX IF NOT EXISTS ", 1)
                .replacen("CREATE UNIQUE INDEX ", "CREATE UNIQUE INDEX IF NOT EXISTS ", 1);
            changes.push(SchemaChange {
                sql: idempotent,
                table: String::new(),
                reason: "索引を用意する".to_string(),
            });
            continue;
        }
        if !current.contains_key(table) {
            changes.push(SchemaChange {
                sql: sql.replacen("CREATE TABLE", "CREATE TABLE IF NOT EXISTS", 1),
                table: table.clone(),
                reason: format!("表 `{table}` が無いので作る"),
            });
            continue;
        }
        // 表はある。足りない列だけ足す (消しも作り直しもしない)
        let have = &current[table];
        for (col, def) in columns.get(table).into_iter().flatten() {
            if have.iter().any(|c| c == col) {
                continue;
            }
            // ALTER TABLE ADD COLUMN は NOT NULL に既定値が要る。
            // 既定値が無い NOT NULL は足せないので、そのときは人の移行に委ねる。
            let upper = def.to_uppercase();
            if upper.contains("NOT NULL") && !upper.contains("DEFAULT") {
                changes.push(SchemaChange {
                    sql: String::new(),
                    table: table.clone(),
                    reason: format!(
                        "列 `{table}.{col}` が足りないが、既定値の無い NOT NULL なので自動では足せない\
                         (人が移行を書くこと)"
                    ),
                });
                continue;
            }
            changes.push(SchemaChange {
                sql: format!("ALTER TABLE \"{table}\" ADD COLUMN {def};"),
                table: table.clone(),
                reason: format!("列 `{table}.{col}` を足す"),
            });
        }
    }

    // 正本に無い表は触らない (端末ローカル専用・コミュニティ投稿・OS 固有)
    let known: Vec<&String> = creates.iter().map(|(t, _)| t).filter(|t| !t.is_empty()).collect();
    let mut extra_tables: Vec<String> = current
        .keys()
        .filter(|t| !known.iter().any(|k| *k == *t))
        .filter(|t| {
            !t.starts_with("sqlite_") && !t.starts_with("grdb_") && !t.starts_with("room_")
                && t.as_str() != "android_metadata"
        })
        .cloned()
        .collect();
    extra_tables.sort();

    SchemaPlan { changes, extra_tables }
}

/// 計画に**破壊的な手が混ざっていないこと**を確かめる。
///
/// 呼び出し側が実行前に必ず通す門。ここを通らない SQL は流さない。
/// 「消す手を持たない」ことをコードで担保するための関数。
pub fn is_additive_only(plan: &SchemaPlan) -> bool {
    plan.changes.iter().all(|c| {
        if c.sql.is_empty() {
            return true; // 実行しない (人に委ねる) 印
        }
        let u = c.sql.to_uppercase();
        let starts_ok = u.starts_with("CREATE TABLE IF NOT EXISTS")
            || u.starts_with("CREATE INDEX IF NOT EXISTS")
            || u.starts_with("CREATE UNIQUE INDEX IF NOT EXISTS")
            || u.starts_with("ALTER TABLE");
        // ⚠️ 単純な部分文字列判定にしてはいけない。CREATE TABLE の中の
        // `ON DELETE CASCADE` / `ON UPDATE` は外部キー**制約**の書き方であって、
        // 行を消す命令ではない。ここを取り違えると正常な計画まで弾いてしまう。
        // 見るべきは「文の頭がどの命令か」で、それは starts_ok が既に判定している。
        // 加えて、文中に別の命令が続いていないか (`;` 区切りの追記) だけを見る。
        let statements = u.split(';').filter(|s| !s.trim().is_empty()).count();
        let single_statement = statements <= 1;
        starts_ok && single_statement
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cur(pairs: &[(&str, &[&str])]) -> HashMap<String, Vec<String>> {
        pairs.iter()
            .map(|(t, cs)| (t.to_string(), cs.iter().map(|c| c.to_string()).collect()))
            .collect()
    }

    #[test]
    fn empty_database_gets_every_table() {
        let ddl = "CREATE TABLE a (id TEXT PRIMARY KEY); CREATE TABLE b (id TEXT);";
        let plan = plan_schema(ddl, &HashMap::new());
        assert_eq!(plan.changes.len(), 2);
        assert!(plan.changes.iter().all(|c| c.sql.contains("IF NOT EXISTS")));
        assert!(is_additive_only(&plan));
    }

    #[test]
    fn existing_table_only_gets_missing_columns() {
        let ddl = "CREATE TABLE a (id TEXT PRIMARY KEY, name TEXT, color TEXT);";
        let plan = plan_schema(ddl, &cur(&[("a", &["id", "name"])]));
        assert_eq!(plan.changes.len(), 1, "{:?}", plan.changes);
        assert!(plan.changes[0].sql.starts_with("ALTER TABLE"));
        assert!(plan.changes[0].sql.contains("color"));
    }

    #[test]
    fn nothing_to_do_when_already_current() {
        let ddl = "CREATE TABLE a (id TEXT PRIMARY KEY, name TEXT);";
        let plan = plan_schema(ddl, &cur(&[("a", &["id", "name"])]));
        assert!(plan.changes.is_empty(), "{:?}", plan.changes);
    }

    /// 正本に無い表は触らない。端末ローカル専用データがここに入る。
    #[test]
    fn tables_outside_the_master_ddl_are_left_alone() {
        let ddl = "CREATE TABLE a (id TEXT);";
        let plan = plan_schema(ddl, &cur(&[("a", &["id"]), ("user_marks", &["entity_id"])]));
        assert!(plan.changes.is_empty());
        assert_eq!(plan.extra_tables, vec!["user_marks".to_string()]);
    }

    /// 既定値の無い NOT NULL 列は自動で足さず、人に委ねる。
    #[test]
    fn not_null_without_default_is_deferred_not_forced() {
        let ddl = "CREATE TABLE a (id TEXT, must TEXT NOT NULL);";
        let plan = plan_schema(ddl, &cur(&[("a", &["id"])]));
        assert_eq!(plan.changes.len(), 1);
        assert!(plan.changes[0].sql.is_empty(), "SQL を出してはいけない");
        assert!(plan.changes[0].reason.contains("人が移行を書く"));
        assert!(is_additive_only(&plan), "実行しない印は門を通ってよい");
    }

    /// 既定値つきの NOT NULL は足せる。
    #[test]
    fn not_null_with_default_can_be_added() {
        let ddl = "CREATE TABLE a (id TEXT, n INTEGER NOT NULL DEFAULT 0);";
        let plan = plan_schema(ddl, &cur(&[("a", &["id"])]));
        assert!(plan.changes[0].sql.starts_with("ALTER TABLE"));
    }

    /// 表制約の行を列と間違えない。
    #[test]
    fn table_constraints_are_not_mistaken_for_columns() {
        let ddl = "CREATE TABLE a (x TEXT, y TEXT, PRIMARY KEY (x, y), UNIQUE(y));";
        let plan = plan_schema(ddl, &cur(&[("a", &["x", "y"])]));
        assert!(plan.changes.is_empty(), "制約を列として足そうとしている: {:?}", plan.changes);
    }

    /// **`ON DELETE CASCADE` は外部キー制約であって破壊命令ではない。**
    ///
    /// 単純な部分文字列判定で門を書くと、正常な CREATE TABLE まで弾いてしまう
    /// (実際に一度そうなった)。制約と命令を取り違えないことを固定する。
    #[test]
    fn foreign_key_actions_are_not_destructive() {
        let ddl = "CREATE TABLE a (id TEXT, b_id TEXT REFERENCES b(id) ON DELETE CASCADE ON UPDATE CASCADE);";
        let plan = plan_schema(ddl, &HashMap::new());
        assert!(is_additive_only(&plan), "外部キー制約を破壊的と誤判定している");
    }

    /// 追記された 2 文目は通さない (`CREATE TABLE ...; DROP TABLE ...` 対策)。
    #[test]
    fn appended_second_statement_is_refused() {
        let bad = SchemaPlan {
            changes: vec![SchemaChange {
                sql: "CREATE TABLE IF NOT EXISTS a (id TEXT); DROP TABLE user_marks;".to_string(),
                table: "a".to_string(),
                reason: "追記".to_string(),
            }],
            extra_tables: vec![],
        };
        assert!(!is_additive_only(&bad));
    }

    #[test]
    fn drop_and_delete_are_refused() {
        for sql in ["DROP TABLE user_marks;", "DELETE FROM user_marks;", "UPDATE user_marks SET kind='x';"] {
            let bad = SchemaPlan {
                changes: vec![SchemaChange { sql: sql.to_string(), table: "user_marks".into(), reason: "x".into() }],
                extra_tables: vec![],
            };
            assert!(!is_additive_only(&bad), "{sql} を通してはいけない");
        }
    }

    /// 索引は IF NOT EXISTS を挟んで冪等になる。
    #[test]
    fn indexes_are_made_idempotent() {
        let ddl = "CREATE TABLE a (id TEXT); CREATE INDEX idx_a ON a(id);";
        let plan = plan_schema(ddl, &HashMap::new());
        let idx = plan.changes.iter().find(|c| c.sql.contains("INDEX")).unwrap();
        assert!(idx.sql.contains("IF NOT EXISTS"), "{}", idx.sql);
    }
}
