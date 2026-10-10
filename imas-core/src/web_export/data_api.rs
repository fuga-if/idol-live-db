//! 公開データ API (`imas-data-api/`、Cloudflare Worker + D1) に流す SQL の書き出し。
//!
//! ## 責務
//!
//! Web 用の JSON ([`super::emit`]) とは別の出力。やることは 3 つだけ:
//!
//! 1. 文書 (`agent::tools::publish`) を JSON にして `docs` 表の行にする (アイドルは `idol` と、項目の束 `facts`)
//! 2. 一覧・検索の索引行 (`idols` / `songs` / `units` / `song_idols` / `terms`) を作る
//! 3. 同期の版 (`meta`) を決める
//!
//! **何を返すか・どう束ねるかの判断はここに書かない。** 文書はツール面 (`get_idol` など) の
//! 出力そのもので、検索語の畳み込みは `imas-text-fold` が唯一の実体
//! (Worker も同じ wasm を通す)。DDL は `imas-data-api/schema.sql` が唯一の定義で、
//! 出力の先頭にそのまま付ける。
//!
//! 出力は表を作り直す SQL なので、何度流しても同じ結果になる (全置き換え)。
//! D1 の 1 文は 100KB まで。文書は 1 行 1 文で書き、超えたら不変条件違反にする。

use super::{Result, WebExportError};
use crate::agent::tools::publish;
use crate::domain::idol_song_queries::{idol_songs, idol_unit_song_ids};
use crate::domain::idol_facets::TagFacetInput;
use crate::domain::snapshot::{split_csv, Snapshot};
use crate::domain::unit_queries;
use crate::web_export::url::fnv1a64;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write;

const SCHEMA_SQL: &str = include_str!("../../../imas-data-api/schema.sql");

/// D1 の 1 文の上限 (100KB) に余裕を見た値。
pub const MAX_STATEMENT_BYTES: usize = 90_000;
/// 索引行を 1 文にまとめる件数。
const BATCH: usize = 100;
/// 前方一致の語として登録する最大の長さ (文字)。長い語は先頭だけで当たれば足りる。
const MAX_TERM_CHARS: usize = 64;

/// 配信する API の版 (URL の `/v1/`)。
pub const API_VERSION: &str = "v1";

/// SQL 文字列リテラル。
fn lit(s: &str) -> String {
    format!("'{}'", s.replace('\'', "''"))
}

fn lit_opt(s: Option<&str>) -> String {
    s.map_or("NULL".to_string(), lit)
}

/// 検索語の集合。畳んだ語を重複なく、空は捨てる。
fn terms<'a>(values: impl IntoIterator<Item = Option<&'a str>>) -> BTreeSet<String> {
    values
        .into_iter()
        .flatten()
        .map(imas_text_fold::fold)
        .map(|t| t.chars().take(MAX_TERM_CHARS).collect::<String>())
        .filter(|t| !t.is_empty())
        .collect()
}

/// タグの票の写し: アイドル id → そのアイドルに付いたタグ。
pub type FacetTags = BTreeMap<String, Vec<TagFacetInput>>;

/// タグの票の写し (JSON) を読む。形は [`TagFacetInput`] の配列をアイドル id で束ねたもの。
pub fn load_facet_tags(path: &std::path::Path) -> Result<FacetTags> {
    let text = std::fs::read_to_string(path)?;
    serde_json::from_str(&text)
        .map_err(|e| WebExportError::Invariant(format!("タグの票の写しが読めない {}: {e}", path.display())))
}

/// 全置き換えの SQL を組む (タグの票なし)。`today` は `YYYY-MM-DD` (JST)。
pub fn render_sql(snap: &Snapshot, today: &str, source_hash: Option<&str>) -> Result<String> {
    render_sql_with_tags(snap, today, source_hash, &FacetTags::new())
}

/// 全置き換えの SQL を組む。`tags` は `/facts` に足すタグの票 (空でよい)。
pub fn render_sql_with_tags(
    snap: &Snapshot,
    today: &str,
    source_hash: Option<&str>,
    tags: &FacetTags,
) -> Result<String> {
    let mut body = String::new();
    let mut term_rows: Vec<(&'static str, String, usize)> = Vec::new();

    // --- 文書 ---
    let mut doc = |kind: &str, id: &str, value: &Value| -> Result<()> {
        let stmt = format!(
            "INSERT INTO docs (kind, id, body) VALUES ({}, {}, {});\n",
            lit(kind),
            lit(id),
            lit(&value.to_string())
        );
        if stmt.len() > MAX_STATEMENT_BYTES {
            return Err(WebExportError::Invariant(format!(
                "文書が D1 の 1 文の上限を超える: {kind}/{id} ({} bytes)",
                stmt.len()
            )));
        }
        body.push_str(&stmt);
        Ok(())
    };
    let tool_err = |id: &str, e: crate::agent::tools::ToolError| {
        WebExportError::Invariant(format!("文書を組めない: {id}: {e}"))
    };

    // --- アイドル ---
    // 通し番号は公式順 (idol_order)。
    let mut idol_ord: BTreeMap<String, usize> = BTreeMap::new();
    let mut idol_lines: Vec<String> = Vec::new();
    for (n, &ii) in snap.idol_order.iter().enumerate() {
        let ord = n + 1;
        let idol = &snap.idols[ii as usize];
        idol_ord.insert(idol.id.clone(), ord);
        let value = publish::idol_document(snap, &idol.id, today).map_err(|e| tool_err(&idol.id, e))?;
        doc("idol", &idol.id, &value)?;
        let no_tags = Vec::new();
        let facts = publish::idol_facts_document(snap, &idol.id, tags.get(&idol.id).unwrap_or(&no_tags))
            .map_err(|e| tool_err(&idol.id, e))?;
        doc("facts", &idol.id, &facts)?;
        idol_lines.push(format!(
            "({ord}, {}, {}, {}, {}, {})",
            lit(&idol.id),
            lit_opt(idol.brand_id.as_deref()),
            lit(&idol.name),
            lit_opt(idol.name_kana.as_deref()),
            idol.is_external as i32
        ));
        let aliases: Vec<&str> = split_csv(idol.aliases.as_deref()).collect();
        let t = terms(
            [
                Some(idol.name.as_str()),
                idol.name_kana.as_deref(),
                idol.name_romaji.as_deref(),
                idol.family_name.as_deref(),
                idol.given_name.as_deref(),
                idol.nickname.as_deref(),
            ]
            .into_iter()
            .chain(aliases.into_iter().map(Some)),
        );
        term_rows.extend(t.into_iter().map(|t| ("idol", t, ord)));
    }

    // --- 曲 ---
    // 通し番号は新しい順 (発売日 DESC・無いものは末尾・同日は id)。
    let mut song_order: Vec<usize> = (0..snap.songs.len()).collect();
    song_order.sort_by(|&a, &b| {
        let (x, y) = (&snap.songs[a], &snap.songs[b]);
        y.release_date.cmp(&x.release_date).then_with(|| x.id.cmp(&y.id))
    });
    // None を末尾に (Option の順序は None < Some なので DESC だと末尾に来る)。
    let mut song_ord: BTreeMap<String, usize> = BTreeMap::new();
    let mut song_lines: Vec<String> = Vec::new();
    for (n, &si) in song_order.iter().enumerate() {
        let ord = n + 1;
        let song = &snap.songs[si];
        song_ord.insert(song.id.clone(), ord);
        let value = publish::song_document(snap, &song.id, today).map_err(|e| tool_err(&song.id, e))?;
        doc("song", &song.id, &value)?;
        song_lines.push(format!(
            "({ord}, {}, {}, {}, {}, {})",
            lit(&song.id),
            lit_opt(song.brand_id.as_deref()),
            lit(&song.title),
            lit_opt(song.title_kana.as_deref()),
            lit_opt(song.release_date.as_deref())
        ));
        let t = terms([Some(song.title.as_str()), song.title_kana.as_deref()]);
        term_rows.extend(t.into_iter().map(|t| ("song", t, ord)));
    }

    // --- アイドルの持ち歌 ---
    let mut link_lines: Vec<String> = Vec::new();
    for idol in &snap.idols {
        let mut ords: BTreeSet<usize> = BTreeSet::new();
        for r in idol_songs(snap, &idol.id, Some("original")) {
            ords.extend(song_ord.get(&r.song_id));
        }
        for id in idol_unit_song_ids(snap, &idol.id) {
            ords.extend(song_ord.get(&id));
        }
        link_lines.extend(ords.into_iter().map(|o| format!("({}, {o})", lit(&idol.id))));
    }

    // --- ユニット ---
    let mut unit_lines: Vec<String> = Vec::new();
    for (n, &ui) in snap.unit_order.iter().enumerate() {
        let ord = n + 1;
        let unit = &snap.units[ui as usize];
        let Some(value) = publish::unit_document(snap, &unit.id) else { continue };
        doc("unit", &unit.id, &value)?;
        unit_lines.push(format!(
            "({ord}, {}, {}, {}, {}, {})",
            lit(&unit.id),
            lit(&unit.brand_id),
            lit(&unit.name),
            lit_opt(unit.name_kana.as_deref()),
            unit.is_permanent as i32
        ));
        let rec = unit_queries::unit_by_id(snap, &unit.id);
        let t = terms([
            Some(unit.name.as_str()),
            unit.name_kana.as_deref(),
            rec.as_ref().and_then(|r| r.name_alt.as_deref()),
        ]);
        term_rows.extend(t.into_iter().map(|t| ("unit", t, ord)));
    }

    doc("brands", "all", &publish::brands_document(snap))?;

    // --- 組み立て ---
    let mut sql = String::new();
    sql.push_str(SCHEMA_SQL);
    sql.push('\n');
    sql.push_str(&body);
    let batched = |sql: &mut String, table: &str, cols: &str, lines: &[String]| {
        for chunk in lines.chunks(BATCH) {
            let _ = writeln!(sql, "INSERT INTO {table} ({cols}) VALUES\n{};", chunk.join(",\n"));
        }
    };
    batched(&mut sql, "idols", "ord, id, brand_id, name, name_kana, is_external", &idol_lines);
    batched(&mut sql, "songs", "ord, id, brand_id, title, title_kana, release_date", &song_lines);
    batched(&mut sql, "units", "ord, id, brand_id, name, name_kana, is_permanent", &unit_lines);
    batched(&mut sql, "song_idols", "idol_id, song_ord", &link_lines);
    let term_lines: Vec<String> =
        term_rows.iter().map(|(k, t, o)| format!("({}, {}, {o})", lit(k), lit(t))).collect();
    batched(&mut sql, "terms", "kind, term, ord", &term_lines);

    // 版 = 日付 + 中身の指紋。中身が変わらない同期ではキャッシュが無駄に捨てられない。
    let version = format!("{today}-{:08x}", (fnv1a64(&sql) >> 32) as u32);
    let mut meta: Vec<(String, String)> = vec![
        ("api_version".into(), API_VERSION.into()),
        ("schema_version".into(), publish::SCHEMA_VERSION.to_string()),
        ("version".into(), version),
        ("generated_at".into(), format!("{today}T00:00:00Z")),
        ("idol_count".into(), idol_lines.len().to_string()),
        ("song_count".into(), song_lines.len().to_string()),
        ("unit_count".into(), unit_lines.len().to_string()),
    ];
    if let Some(h) = source_hash {
        meta.push(("source_hash".into(), h.to_string()));
    }
    meta.push((
        "credits".into(),
        "呼称データ: im@sparql (MIT License, (c) 2017 IM@Study, https://github.com/crssnky/imasparql)".into(),
    ));
    let meta_lines: Vec<String> = meta.iter().map(|(k, v)| format!("({}, {})", lit(k), lit(v))).collect();
    batched(&mut sql, "meta", "key, value", &meta_lines);
    Ok(sql)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;
    use rusqlite::Connection;

    fn load() -> (Connection, String) {
        let snap = bundle_snapshot();
        let sql = render_sql(snap, "2026-10-01", Some("testhash")).unwrap();
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&sql).expect("出力した SQL がそのまま流せる");
        (conn, sql)
    }

    #[test]
    fn 出力は流せて件数が台帳と合う() {
        let snap = bundle_snapshot();
        let (conn, _) = load();
        let count = |t: &str| -> i64 { conn.query_row(&format!("SELECT count(*) FROM {t}"), [], |r| r.get(0)).unwrap() };
        assert_eq!(count("idols") as usize, snap.idols.len());
        assert_eq!(count("songs") as usize, snap.songs.len());
        assert_eq!(count("units") as usize, snap.units.len());
        let docs: i64 = count("docs");
        assert_eq!(docs as usize, snap.idols.len() * 2 + snap.songs.len() + snap.units.len() + 1);
        assert!(count("terms") > 0 && count("song_idols") > 0);
        let version: String =
            conn.query_row("SELECT value FROM meta WHERE key='version'", [], |r| r.get(0)).unwrap();
        assert!(version.starts_with("2026-10-01-"));
    }

    #[test]
    fn 出力が同じ入力で毎回同じ() {
        let snap = bundle_snapshot();
        let a = render_sql(snap, "2026-10-01", None).unwrap();
        let b = render_sql(snap, "2026-10-01", None).unwrap();
        assert!(a == b, "同期の SQL が再現しない");
    }

    /// T12 相当: D1 に置く列にも文書にも、歌詞と試聴の在り処が無い。
    #[test]
    fn d1に歌詞と試聴の_url_を置かない() {
        let snap = bundle_snapshot();
        let (conn, sql) = load();
        assert!(!sql.contains("lyrics_url") && !sql.contains("preview_url"));
        // 列名でも禁止 (将来の列追加で入れても落ちる)。
        let tables: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table'")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(|r| r.unwrap())
            .collect();
        for t in tables {
            let cols: Vec<String> = conn
                .prepare(&format!("SELECT name FROM pragma_table_info('{t}')"))
                .unwrap()
                .query_map([], |r| r.get(0))
                .unwrap()
                .map(|r| r.unwrap())
                .collect();
            for c in cols {
                let c = c.to_lowercase();
                assert!(!c.contains("lyric") && !c.contains("preview"), "{t}.{c}");
            }
        }
        for v in snap
            .songs
            .iter()
            .flat_map(|s| [s.lyrics_url.as_deref(), s.preview_url.as_deref()])
            .flatten()
            .filter(|v| !v.is_empty())
        {
            assert!(!sql.contains(v), "歌詞/試聴の URL が SQL に出ている: {v}");
        }
    }

    #[test]
    fn 文書はツール面の出力と一致し_検索語は畳まれている() {
        let snap = bundle_snapshot();
        let (conn, _) = load();
        let body: String = conn
            .query_row("SELECT body FROM docs WHERE kind='idol' AND id='765as_天海春香'", [], |r| r.get(0))
            .unwrap();
        let want = publish::idol_document(snap, "765as_天海春香", "2026-10-01").unwrap();
        assert_eq!(serde_json::from_str::<Value>(&body).unwrap(), want);
        // 名前の前方一致が畳んだ語の範囲検索で当たる。
        let n: i64 = conn
            .query_row(
                "SELECT count(*) FROM terms WHERE kind='idol' AND term >= ?1 AND term < ?2",
                [imas_text_fold::fold("天海"), format!("{}\u{10FFFF}", imas_text_fold::fold("天海"))],
                |r| r.get(0),
            )
            .unwrap();
        assert!(n >= 1);
    }
}
