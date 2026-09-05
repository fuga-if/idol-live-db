//! `db/community.sql` を読んで [`CommunitySnapshot`] を組む。
//!
//! ファイルは `tools/export_community_snapshot.py` が作る自己完結な SQL
//! (CREATE TABLE + INSERT)。空の SQLite に流し込んでから読む。
//!
//! **ここは読むだけ。** 何を出してよいか (「誰が」を含む列を出さない) の判断は
//! 抽出ツール側にあり、このファイルにはもう入っていない。

use crate::domain::community::{
    CommunityRows, CommunitySnapshot, PenlightVoteRow, PollEntryRow, PollRow, TagRow, TaggedRow,
};
use rusqlite::Connection;

/// SQL ファイルから読み込む。ファイルが無ければ「集計なし」を返す
/// (コミュニティ抜きでも出面は組めるようにしておく)。
///
/// **無ければ stderr に出す。** 黙って空を返すと、パスを間違えたときに
/// 「タグが 1 つも出ない出面」が正常に見えてしまう (実際にそれで一度落とし穴に落ちた)。
pub fn load_community(sql_path: &str) -> Result<CommunitySnapshot, String> {
    if !std::path::Path::new(sql_path).exists() {
        eprintln!("community: {sql_path} が無いので集計抜きで書き出す");
        return Ok(CommunitySnapshot::default());
    }
    let sql = std::fs::read_to_string(sql_path).map_err(|e| format!("{sql_path}: {e}"))?;
    // メモリ上の DB に流す (中間ファイルを残さない)。
    let conn = Connection::open_in_memory().map_err(|e| e.to_string())?;
    conn.execute_batch(&sql).map_err(|e| format!("{sql_path} を読み込めない: {e}"))?;
    Ok(CommunitySnapshot::build(read_rows(&conn)?))
}

fn read_rows(conn: &Connection) -> Result<CommunityRows, String> {
    Ok(CommunityRows {
        song_tag_vocab: tags(conn, "tags")?,
        idol_tag_vocab: tags(conn, "idol_tag_master")?,
        unit_tag_vocab: tags(conn, "unit_tag_master")?,
        song_tags: tagged(conn, "song_tags", "song_id")?,
        idol_tags: tagged(conn, "idol_tags", "idol_id")?,
        unit_tags: tagged(conn, "unit_tags", "unit_id")?,
        favorites: query(conn, "SELECT song_id, count FROM song_favorites", |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        })?,
        penlight: query(
            conn,
            "SELECT song_id, color_set_key, count FROM penlight_color_set_votes",
            |r| {
                Ok(PenlightVoteRow {
                    song_id: r.get(0)?,
                    color_set_key: r.get(1)?,
                    count: r.get(2)?,
                })
            },
        )?,
        polls: query(
            conn,
            "SELECT id, title, description, target_type, created_at, ends_at, status FROM polls",
            |r| {
                Ok(PollRow {
                    id: r.get(0)?,
                    title: r.get(1)?,
                    description: r.get(2)?,
                    target_type: r.get(3)?,
                    created_at: r.get(4)?,
                    ends_at: r.get(5)?,
                    status: r.get(6)?,
                })
            },
        )?,
        poll_entries: query(
            conn,
            "SELECT poll_id, entity_id, vote_count FROM poll_entries",
            |r| {
                Ok(PollEntryRow {
                    poll_id: r.get(0)?,
                    entity_id: r.get(1)?,
                    vote_count: r.get(2)?,
                })
            },
        )?,
    })
}

fn tags(conn: &Connection, table: &str) -> Result<Vec<TagRow>, String> {
    let sql = format!(
        "SELECT id, name, description, category, color, is_official FROM {table} ORDER BY id"
    );
    query(conn, &sql, |r| {
        Ok(TagRow {
            id: r.get(0)?,
            name: r.get(1)?,
            description: r.get(2)?,
            category: r.get(3)?,
            color: r.get(4)?,
            // 型を書かない CREATE TABLE なので 0/1 が INTEGER で入っている。
            is_official: r.get::<_, i64>(5).unwrap_or(0) != 0,
        })
    })
}

fn tagged(conn: &Connection, table: &str, id_col: &str) -> Result<Vec<TaggedRow>, String> {
    let sql = format!("SELECT {id_col}, tag_id, vote_count FROM {table}");
    query(conn, &sql, |r| {
        Ok(TaggedRow { entity_id: r.get(0)?, tag_id: r.get(1)?, vote_count: r.get(2)? })
    })
}

fn query<T>(
    conn: &Connection,
    sql: &str,
    row: impl Fn(&rusqlite::Row) -> rusqlite::Result<T>,
) -> Result<Vec<T>, String> {
    let mut stmt = conn.prepare(sql).map_err(|e| format!("{sql}: {e}"))?;
    let rows = stmt.query_map([], |r| row(r)).map_err(|e| format!("{sql}: {e}"))?;
    rows.collect::<rusqlite::Result<Vec<T>>>().map_err(|e| format!("{sql}: {e}"))
}
