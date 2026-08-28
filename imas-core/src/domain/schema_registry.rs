//! 共有コアが持つ**スキーマの台帳**と、実 DB との突き合わせ。
//!
//! # なぜこれが要るか
//!
//! いまは「スキーマを変えたら iOS (GRDB migration) と Android (Room Migration) に
//! **対で書く**」という規律で保っている (docs/ARCHITECTURE.md)。人が守る規律なので、
//! 片方だけ足して気づかない事故が起きうる。実際 `idol_voice_actors` は iOS にだけ
//! あり、Android には無い状態が続いていた (CV 名検索が Android で常に 0 件になっていた)。
//!
//! ここは**あるべき表と列を 1 か所に書き**、実際の DB と突き合わせる。
//! ずれたらテストが落ちるので、「対で書き忘れた」が CI で捕まる。
//!
//! # まだ「所有」はしていない
//!
//! 移行の実行そのものは各 OS のまま (GRDB / Room)。ここが持つのは**期待値**だけ。
//! いきなり実行まで奪うと、`user_marks` (クラウドにもサーバにも無い端末唯一データ)
//! を壊したときに復旧手段が無い。まず「ずれを検出できる」状態を作り、
//! 実行の移管はその後に段階を踏む。

/// 表の出どころ。突き合わせでどちらに在るべきかを決める。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum TableOrigin {
    /// CloudKit から配られるマスタ。同梱 DB にも実機にも在る。
    Master,
    /// 端末ローカル専用 (担当・お気に入り・メモ・参加、マイタグ)。
    /// **同梱 master.sqlite に入れてはいけない**。入れると配布物に個人データの器が混ざる。
    LocalOnly,
    /// コミュニティ投稿由来。同梱 DB には無く、同期で後から入る。
    Community,
    /// スナップショットが読まない補助表。片方にしか無くてもよい。
    Auxiliary,
}

/// 台帳の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TableSpec {
    pub name: String,
    pub origin: TableOrigin,
    /// 欠けていたら異常とみなす列 (全列ではなく、コードが依存している列だけ)。
    pub required_columns: Vec<String>,
    /// なぜこの扱いなのかの覚え書き。ずれた時に読む人向け。
    pub note: String,
}

fn spec(name: &str, origin: TableOrigin, cols: &[&str], note: &str) -> TableSpec {
    TableSpec {
        name: name.to_string(),
        origin,
        required_columns: cols.iter().map(|c| c.to_string()).collect(),
        note: note.to_string(),
    }
}

/// あるべき表の一覧。
///
/// 列は**コアが実際に読むもの**だけを挙げる。全列を書くと、表示にしか使わない列を
/// 足すたびにここも直す羽目になり、台帳が形骸化する。
pub fn expected_tables() -> Vec<TableSpec> {
    use TableOrigin::*;
    vec![
        spec("brands", Master, &["id", "name", "color", "sort_order"], "ブランド"),
        spec("idols", Master, &["id", "name", "color", "birthday", "sort_order"],
             "アイドル。voice_actors 列は廃止済 (書き戻すと落ちるので iOS は読まない)"),
        spec("idol_brands", Master, &["idol_id", "brand_id"], "複数ブランド所属の橋渡し (複合 PK)"),
        spec("songs", Master, &["id", "title", "brand_id", "apple_music_id", "artwork_url"],
             "曲。title_kana は現在全曲空 (読み仮名の出典が無い)"),
        spec("song_artists", Master, &["song_id", "idol_id", "role"],
             "原唱者。role='original' は一覧のアイコン表示の根拠 (複合 PK)"),
        spec("units", Master, &["id", "name", "name_kana"], "ユニット"),
        spec("unit_members", Master, &["unit_id", "idol_id"], "ユニット所属 (複合 PK)"),
        spec("events", Master, &["id", "name", "brand_id", "kind"],
             "ライブ。joint_brand_ids を持つと合同ライブ扱い"),
        spec("shows", Master, &["id", "event_id", "date", "venue"], "公演"),
        spec("setlist_items", Master, &["id", "show_id", "song_id", "position"], "セトリ"),
        spec("setlist_performers", Master, &["setlist_item_id", "idol_id"],
             "その披露の歌唱メンバー (複合 PK)"),
        spec("show_cast", Master, &["show_id", "idol_id"], "公演の出演者 (複合 PK)"),
        spec("creators", Master, &["id", "name", "name_kana"],
             "作詞・作曲・編曲の作家とその読み (人単位・所属つきの表記)。\n\
              曲側に持たせない: 読みは人の属性で、同じ人が数十曲に出るため。\n\
              連名の欄を人ごとに割る規則は domain/credit_names.rs"),
        spec("unit_versions", Master, &["id", "unit_id", "name"],
             "ユニットのバージョン (Project“ReLight”AXE8 等)。\n\
              ユニット自体は 1 行のまま。版で分けるのは曲側 (songs.unit_version_id)。\n\
              版の判定は code で行う (name の文字列一致に頼らない)"),
        spec("venues", Master, &["id", "name"], "会場"),
        spec("venue_names", Master, &["venue_id", "name"], "会場の別名・改称"),
        spec("venue_halls", Master, &["venue_id", "name"], "会場内のホール"),
        spec("staff", Master, &["id", "name"], "スタッフ"),
        spec("anniversaries", Master, &["id", "label", "date"],
             "記念日 (カレンダーに出す)。表示名の列は name ではなく label"),
        spec("meta", Master, &["key", "value"], "data_version 等"),
        spec("user_marks", LocalOnly, &["entity_type", "entity_id", "kind"],
             "担当/お気に入り/メモ/参加。**クラウドにもサーバにも無い端末唯一データ**。\
              同梱 DB には入れない。壊すと復旧手段が無いので破壊的移行は禁止"),
        spec("personal_tags", LocalOnly, &["entity_type", "entity_id", "tag_name"],
             "マイタグ。端末ローカル専用"),
        spec("song_calls", Community, &["song_id"], "コールガイド。同期で後から入る"),
        spec("song_videos", Community, &["song_id"], "動画リンク。同期で後から入る"),
        spec("idol_voice_actors", Auxiliary, &["idol_id", "name"],
             "声優履歴。**iOS にしか無い**。Android は Room の entity を持たず、SeedImporter が\
              「両方にある表」しか移さないため実機に存在しない。そのため Android では CV 名検索が\
              効かず、コア側は table_exists で無ければ空として続行する"),
        spec("song_units", Auxiliary, &["song_id"], "曲とユニットの対応。非同期テーブル"),
    ]
}

/// 突き合わせの結果 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SchemaDrift {
    pub table: String,
    /// 何がずれているか (人が読む文)。
    pub detail: String,
    /// 想定内のずれか (Auxiliary / 出どころ違いなど)。false なら直すべき。
    pub expected: bool,
}

/// 台帳と、実際に在る表・列を突き合わせる。
///
/// `actual` は「表名 → 列名」の実測。呼び出し側 (outbound / テスト) が
/// `sqlite_master` と `PRAGMA table_info` から作って渡す。
pub fn find_drift(
    expected: &[TableSpec],
    actual: &std::collections::HashMap<String, Vec<String>>,
) -> Vec<SchemaDrift> {
    let mut out = Vec::new();
    for t in expected {
        let Some(cols) = actual.get(&t.name) else {
            // 出どころによって「無くて当たり前」かが変わる
            let expected_missing = matches!(
                t.origin,
                TableOrigin::LocalOnly | TableOrigin::Community | TableOrigin::Auxiliary
            );
            out.push(SchemaDrift {
                table: t.name.clone(),
                detail: format!("表が無い ({})", t.note),
                expected: expected_missing,
            });
            continue;
        };
        for need in &t.required_columns {
            if !cols.iter().any(|c| c == need) {
                out.push(SchemaDrift {
                    table: t.name.clone(),
                    detail: format!("列 `{need}` が無い"),
                    expected: false,
                });
            }
        }
    }
    // 台帳に無い表 (誰かが足して台帳を更新し忘れた)
    for name in actual.keys() {
        if name.starts_with("sqlite_") || name.starts_with("grdb_") || name.starts_with("room_")
            || name == "android_metadata"
        {
            continue;
        }
        if !expected.iter().any(|t| &t.name == name) {
            out.push(SchemaDrift {
                table: name.clone(),
                detail: "台帳に無い表 (足したなら schema_registry にも書くこと)".to_string(),
                expected: false,
            });
        }
    }
    out.sort_by(|a, b| a.table.cmp(&b.table).then(a.detail.cmp(&b.detail)));
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    /// 実際の DB から「表名 → 列名」を読む。
    fn actual_schema(path: &str) -> HashMap<String, Vec<String>> {
        use rusqlite::{Connection, OpenFlags};
        let conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let names: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
                .unwrap();
            let rows = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap();
            rows.filter_map(Result::ok).collect()
        };
        let mut out = HashMap::new();
        for t in names {
            let mut stmt = conn.prepare(&format!("PRAGMA table_info({t})")).unwrap();
            let rows = stmt.query_map([], |r| r.get::<_, String>(1)).unwrap();
            out.insert(t, rows.filter_map(Result::ok).collect());
        }
        out
    }

    fn bundle_db() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    /// 同梱 master.sqlite が台帳どおりか。
    ///
    /// **ここが落ちたら「スキーマを変えたのに台帳を直していない」**。
    /// 台帳 (`expected_tables`) を実態に合わせて更新すること。
    #[test]
    fn bundle_database_matches_the_registry() {
        let actual = actual_schema(&bundle_db());
        // 想定内のずれ (端末ローカル専用表が同梱 DB に無い等) は無視する
        let drift: Vec<SchemaDrift> = find_drift(&expected_tables(), &actual)
            .into_iter()
            .filter(|d| !d.expected)
            .collect();
        assert!(
            drift.is_empty(),
            "同梱 DB と台帳がずれている:\n{}",
            drift.iter().map(|d| format!("  {} — {}", d.table, d.detail)).collect::<Vec<_>>().join("\n")
        );
    }

    /// 端末ローカル専用の表が同梱 DB に混ざっていないか。
    ///
    /// 混ざると、配布物に個人データの器が入る (中身が空でも設計として誤り)。
    #[test]
    fn local_only_tables_are_absent_from_the_bundle() {
        let actual = actual_schema(&bundle_db());
        for t in expected_tables().iter().filter(|t| t.origin == TableOrigin::LocalOnly) {
            assert!(
                !actual.contains_key(&t.name),
                "端末ローカル専用の `{}` が同梱 DB に入っている",
                t.name
            );
        }
    }

    /// マスタ表は同梱 DB に必ず在ること。
    #[test]
    fn master_tables_are_all_present() {
        let actual = actual_schema(&bundle_db());
        let expected = expected_tables();
        let missing: Vec<&str> = expected
            .iter()
            .filter(|t| t.origin == TableOrigin::Master)
            .filter(|t| !actual.contains_key(&t.name))
            .map(|t| t.name.as_str())
            .collect();
        assert!(missing.is_empty(), "マスタ表が同梱 DB に無い: {missing:?}");
    }

    #[test]
    fn missing_column_is_reported() {
        let mut actual = HashMap::new();
        actual.insert("brands".to_string(), vec!["id".to_string()]); // name/color/sort_order 欠け
        let drift = find_drift(&expected_tables(), &actual);
        let brands: Vec<&SchemaDrift> = drift.iter().filter(|d| d.table == "brands").collect();
        assert!(brands.iter().any(|d| d.detail.contains("`name`")), "{drift:?}");
        assert!(brands.iter().all(|d| !d.expected), "列欠けを想定内にしてはいけない");
    }

    #[test]
    fn unknown_table_is_reported() {
        let mut actual = HashMap::new();
        actual.insert("誰かが足した表".to_string(), vec!["id".to_string()]);
        let drift = find_drift(&expected_tables(), &actual);
        assert!(drift.iter().any(|d| d.table == "誰かが足した表" && !d.expected), "{drift:?}");
    }

    #[test]
    fn internal_tables_are_ignored() {
        let mut actual = HashMap::new();
        for t in ["grdb_migrations", "room_master_table", "android_metadata", "sqlite_sequence"] {
            actual.insert(t.to_string(), vec![]);
        }
        let drift = find_drift(&expected_tables(), &actual);
        assert!(
            !drift.iter().any(|d| d.table.starts_with("grdb_") || d.table.starts_with("room_")
                || d.table == "android_metadata" || d.table.starts_with("sqlite_")),
            "内部表を報告してはいけない: {drift:?}"
        );
    }
}
