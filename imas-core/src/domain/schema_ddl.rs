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

/// Room (Android) が吐いた確定スキーマとの突き合わせ。
///
/// Room は `exportSchema = true` で `app/schemas/<db>/<version>.json` を吐く。
/// そこに載る表・列と、コアが持つマスタ DDL を比べれば、
/// **片方だけスキーマを変えた事故**が機械的に captured できる。
///
/// 完全一致は求めない。意図的に片方にしか無いものがあるため
/// (端末ローカル専用表・コミュニティ投稿表・未追随と分かっている列)。
/// **「知らないズレが増えていないか」**を見るのが目的。
#[cfg(test)]
mod room_parity {
    use super::*;
    use rusqlite::Connection;
    use std::collections::{BTreeMap, BTreeSet};

    /// 現時点で分かっているズレ。**増えたらテストが落ちる**。
    /// 直したらここから消すこと。
    const KNOWN_GAPS: &[(&str, &str, &str)] = &[
        ("idols", "voice_actors", "廃止列。iOS は書き戻すと落ちるので読まない。Android だけが今も持っている"),
        ("songs", "jasrac_code", "JASRAC 許諾が認可待ちのため Android 未追加"),
        ("idol_voice_actors", "*", "Android は entity を持たず、SeedImporter が『両方にある表』しか移さないため実機に無い。CV 名検索が Android で効かない原因"),
        ("song_units", "*", "非同期テーブル。Android は持たない"),
    ];

    fn core_schema() -> BTreeMap<String, BTreeSet<String>> {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch(MASTER_SCHEMA_SQL).unwrap();
        let names: Vec<String> = {
            let mut s = c.prepare("SELECT name FROM sqlite_master WHERE type='table'").unwrap();
            let r = s.query_map([], |r| r.get::<_, String>(0)).unwrap();
            r.filter_map(Result::ok).collect()
        };
        let mut out = BTreeMap::new();
        for t in names {
            let mut s = c.prepare(&format!("PRAGMA table_info({t})")).unwrap();
            let cols = s.query_map([], |r| r.get::<_, String>(1)).unwrap();
            out.insert(t, cols.filter_map(Result::ok).collect());
        }
        out
    }

    /// Room の schema JSON を読む。無ければ `None` (Android 側を触らない環境でも落とさない)。
    fn room_schema() -> Option<BTreeMap<String, BTreeSet<String>>> {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../ImasLiveDB-Android/app/schemas");
        let entry = std::fs::read_dir(dir).ok()?.filter_map(Result::ok).next()?;
        // 版番号が一番大きい JSON を採る
        let mut files: Vec<_> = std::fs::read_dir(entry.path()).ok()?
            .filter_map(Result::ok)
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "json"))
            .collect();
        files.sort();
        let text = std::fs::read_to_string(files.last()?).ok()?;
        // serde_json は依存に入っている
        let v: serde_json::Value = serde_json::from_str(&text).ok()?;
        let mut out = BTreeMap::new();
        for e in v["database"]["entities"].as_array()? {
            let name = e["tableName"].as_str()?.to_string();
            let cols = e["fields"].as_array()?
                .iter()
                .filter_map(|f| f["columnName"].as_str().map(str::to_string))
                .collect();
            out.insert(name, cols);
        }
        Some(out)
    }

    /// **知らないズレが増えていないこと。**
    ///
    /// 落ちたら、iOS/コア側だけスキーマを変えて Android に対で書いていない可能性が高い。
    /// 意図的な差なら KNOWN_GAPS に理由つきで足すこと。
    #[test]
    fn no_unknown_schema_gaps_against_room() {
        let Some(room) = room_schema() else {
            eprintln!("Room の schema JSON が無いので検査を飛ばす (Android を触らない環境)");
            return;
        };
        let core = core_schema();
        let known_table: BTreeSet<&str> =
            KNOWN_GAPS.iter().filter(|(_, c, _)| *c == "*").map(|(t, _, _)| *t).collect();
        let known_col: BTreeSet<(&str, &str)> =
            KNOWN_GAPS.iter().filter(|(_, c, _)| *c != "*").map(|(t, c, _)| (*t, *c)).collect();

        let mut unknown = Vec::new();
        for (table, core_cols) in &core {
            let Some(room_cols) = room.get(table) else {
                if !known_table.contains(table.as_str()) {
                    unknown.push(format!("表 `{table}` が Room に無い"));
                }
                continue;
            };
            for c in core_cols.difference(room_cols) {
                if !known_col.contains(&(table.as_str(), c.as_str())) {
                    unknown.push(format!("`{table}.{c}` がコアにあって Room に無い"));
                }
            }
            for c in room_cols.difference(core_cols) {
                if !known_col.contains(&(table.as_str(), c.as_str())) {
                    unknown.push(format!("`{table}.{c}` が Room にあってコアに無い"));
                }
            }
        }
        assert!(
            unknown.is_empty(),
            "iOS/コアと Android のスキーマに知らないズレがある:\n{}\n\
             意図した差なら KNOWN_GAPS に理由つきで足すこと。",
            unknown.join("\n")
        );
    }

    /// KNOWN_GAPS が実態と合っていること (直したのに消し忘れた項目を捕まえる)。
    #[test]
    fn known_gaps_are_still_real() {
        let Some(room) = room_schema() else { return };
        let core = core_schema();
        let mut stale = Vec::new();
        for (table, col, _) in KNOWN_GAPS {
            let in_core = core.get(*table);
            let in_room = room.get(*table);
            let still_differs = if *col == "*" {
                in_core.is_some() != in_room.is_some()
            } else {
                let c = in_core.is_some_and(|s| s.contains(*col));
                let r = in_room.is_some_and(|s| s.contains(*col));
                c != r
            };
            if !still_differs {
                stale.push(format!("`{table}.{col}` はもうズレていない"));
            }
        }
        assert!(stale.is_empty(), "KNOWN_GAPS から消すこと:\n{}", stale.join("\n"));
    }
}
