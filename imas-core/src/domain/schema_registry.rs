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
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
    /// iOS の Documents DB にだけある表 (GRDB の移行が作る)。同梱 DB・コアの DDL・
    /// Android の Room には無い。列の単位のものは [`DOCUMENTS_ONLY_COLUMNS`]。
    DocumentsOnly,
}

/// 台帳の 1 行。
#[derive(Clone, Debug, PartialEq, Eq)]
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
        spec("costumes", Master, &["id", "name"],
             "ライブ衣装の目録。unit_id / idol_id が入っていればその編成・その人の専用衣装、\n\
              どちらも NULL なら公演の共通衣装。**画像は持たない** (版権物を載せない方針)"),
        spec("costume_wears", Master, &["id", "costume_id", "show_id"],
             "その公演で衣装を着た記録。setlist_item_id を持てば「この曲で着た」まで分かり、\n\
              NULL なら公演で使われたことだけが分かっている。idol_id が NULL なら\n\
              その場の全員 (共通衣装)、入っていればその人だけ (着替えの分岐)"),
        spec("show_tickets", Master, &["id", "show_id", "kind", "name", "price"],
             "公演のチケット価格。席種は自由文字列 (S席 / 立見 / 配信 (アーカイブ付き) …)、\
              kind は live / stream / live_viewing。価格は**税込・手数料抜きの定価**で、\
              is_estimate は公式に出ていない推定値の札。規則は domain/ticket_prices.rs"),
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
        spec("expenses", LocalOnly, &["id", "date", "category", "amount"],
             "アイマス関連の収支 (家計簿)。**クラウドにもサーバにも無い端末唯一データ**。\
              show_id が入っていればその公演の遠征費、NULL なら単独の支出 (課金・通販)。\
              費目キーと集計は domain/ledger.rs"),
        spec("song_videos", Community, &["song_id"], "動画リンク。同期で後から入る"),
        spec("idol_voice_actors", Auxiliary, &["idol_id", "name"],
             "声優履歴。**iOS にしか無い**。Android は Room の entity を持たず、SeedImporter が\
              「両方にある表」しか移さないため実機に存在しない。そのため Android では CV 名検索が\
              効かず、コア側は table_exists で無ければ空として続行する"),
        spec("song_units", Auxiliary, &["song_id"], "曲とユニットの対応。非同期テーブル"),
        spec("event_releases", DocumentsOnly, &["id", "event_id"],
             "イベントの映像円盤 (BD/DVD)。iOS の移行 v24 が作る。所有の印は user_marks (kind=owned)。\
              予定している機能の器で、今はどの経路 (同梱 DB・CloudKit の同期) からも行が入らない。\
              コアのローダは表が無ければ空として読む"),
    ]
}

/// 列 1 本の覚え書き。表の単位の台帳 ([`expected_tables`]) とは別に、列の単位で持つもの。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ColumnNote {
    pub table: &'static str,
    pub column: &'static str,
    /// なぜこの扱いなのか。ずれた時に読む人向け。
    pub note: &'static str,
}

/// iOS の Documents DB にしか無い列。GRDB の移行 (`DatabaseMigrations.swift`) が足し、
/// コアの DDL・同梱 DB・Android の Room には無い。
///
/// - コアのローダは、列が無ければ NULL として読む (`outbound::sqlite_loader`)。
/// - reseed は同梱 DB と共通の列しか入れ直さないので、reseed の後はどれも NULL に戻る。
/// - **コアの DDL に移すときは、Android の Room にも entity と移行を足すこと。** iOS は
///   ensureMasterSchema の ALTER で揃うが、Android はコアの DDL を流さない (Room が列まで
///   照合する) ので、Room 側を足し忘れると Android だけ列が無いまま進む。
pub const DOCUMENTS_ONLY_COLUMNS: &[ColumnNote] = &[
    ColumnNote {
        table: "brands",
        column: "icon_url",
        note: "ブランドのアイコン。CloudKit の Brand.iconUrl を同期で書く (CkBrandRow.icon_url)。\
               書き先の列があるのは iOS だけ",
    },
    ColumnNote {
        table: "idols",
        column: "voice_actors",
        note: "廃止した列。移行 v19 が、cast / idol_cast を持っていた古い端末にだけ足した。\
               声優は idol_voice_actors が正で、iOS はこの列を読まない",
    },
    ColumnNote {
        table: "events",
        column: "has_streaming",
        note: "開催形態 (配信の有無)。移行 v23 が足し、is_streaming から初期値を写す。同期では配らない",
    },
    ColumnNote {
        table: "events",
        column: "has_live_viewing",
        note: "開催形態 (ライブビューイングの有無)。移行 v23 が足す。同期では配らない",
    },
    ColumnNote {
        table: "shows",
        column: "has_streaming",
        note: "公演の単位の開催形態 (配信の有無)。移行 v23 が足す。同期では配らない",
    },
    ColumnNote {
        table: "shows",
        column: "has_live_viewing",
        note: "公演の単位の開催形態 (ライブビューイングの有無)。移行 v23 が足す。同期では配らない",
    },
];

/// コアの DDL にあるのに、CloudKit の同期では**意図して配らない**列。同期の行型
/// (`ck_record_mapping` の Ck*Row) に載せていないので、端末には同梱 DB の reseed でだけ届く。
pub const COLUMNS_NOT_SYNCED: &[ColumnNote] = &[ColumnNote {
    table: "songs",
    column: "jasrac_code",
    note: "JASRAC の作品コード。読むのは同梱 DB を読む MCP (get_song) だけで、アプリの画面には\
           出さない (JASRAC への利用報告は tools/jasrac/works.tsv を正にしている)。CloudKit の Song に\
           ある jasracCode の欄は読まない (CkSongRow に無い)。Android の Room には列が無い\
           (schema_ddl の KNOWN_GAPS)",
}];

/// 突き合わせの結果 1 件。
#[derive(Clone, Debug, PartialEq, Eq)]
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
                TableOrigin::LocalOnly
                    | TableOrigin::Community
                    | TableOrigin::Auxiliary
                    | TableOrigin::DocumentsOnly
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
    use crate::test_support::bundle_path;
    use rusqlite::{Connection, OpenFlags};
    use std::collections::HashMap;

    /// 実際の DB から「表名 → 列名」を読む。
    fn actual_schema(path: &str) -> HashMap<String, Vec<String>> {
        schema_of(&Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap())
    }

    /// コアの DDL から「表名 → 列名」を読む。
    fn ddl_schema() -> HashMap<String, Vec<String>> {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(crate::domain::schema_ddl::MASTER_SCHEMA_SQL).unwrap();
        schema_of(&conn)
    }

    fn schema_of(conn: &Connection) -> HashMap<String, Vec<String>> {
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

    /// 同梱 master.sqlite が台帳どおりか。
    ///
    /// **ここが落ちたら「スキーマを変えたのに台帳を直していない」**。
    /// 台帳 (`expected_tables`) を実態に合わせて更新すること。
    #[test]
    fn bundle_database_matches_the_registry() {
        let actual = actual_schema(bundle_path());
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
        let actual = actual_schema(bundle_path());
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
        let actual = actual_schema(bundle_path());
        let expected = expected_tables();
        let missing: Vec<&str> = expected
            .iter()
            .filter(|t| t.origin == TableOrigin::Master)
            .filter(|t| !actual.contains_key(&t.name))
            .map(|t| t.name.as_str())
            .collect();
        assert!(missing.is_empty(), "マスタ表が同梱 DB に無い: {missing:?}");
    }

    /// Documents 専用の列は、コアの DDL (= 同梱 DB) に無い。DDL に移したら台帳から外すこと
    /// (外すときに、Android の Room にも足したかを確かめる機会になる)。
    #[test]
    fn documents_only_columns_are_outside_the_master_ddl() {
        let ddl = ddl_schema();
        for c in DOCUMENTS_ONLY_COLUMNS {
            let cols = ddl.get(c.table).unwrap_or_else(|| panic!("{} はマスタの表のはず", c.table));
            assert!(
                !cols.iter().any(|x| x == c.column),
                "{}.{} は DDL にある。台帳の DOCUMENTS_ONLY_COLUMNS から外すこと",
                c.table,
                c.column
            );
        }
    }

    /// iOS の移行が足す列のうち DDL に無いものは、台帳の Documents 専用の列とちょうど一致する。
    /// iOS にだけ列を足して台帳に書き忘れると、ここが落ちる。
    #[test]
    fn ios_only_columns_are_all_in_the_ledger() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../ImasLiveDB/Database/DatabaseMigrations.swift");
        let Ok(swift) = std::fs::read_to_string(&path) else {
            eprintln!("iOS の移行が無いので検査を飛ばす ({})", path.display());
            return;
        };
        let ddl = ddl_schema();
        let mut ios_only: Vec<(String, String)> = swift
            .split("ALTER TABLE ")
            .skip(1)
            .filter_map(|rest| {
                let mut words = rest.split_whitespace();
                let table = words.next()?;
                (words.next()? == "ADD" && words.next()? == "COLUMN").then_some(())?;
                Some((table.to_string(), words.next()?.to_string()))
            })
            .filter(|(table, column)| ddl.get(table).is_some_and(|cols| !cols.contains(column)))
            .collect();
        ios_only.sort();
        ios_only.dedup();
        let mut ledger: Vec<(String, String)> = DOCUMENTS_ONLY_COLUMNS
            .iter()
            .map(|c| (c.table.to_string(), c.column.to_string()))
            .collect();
        ledger.sort();
        assert_eq!(ios_only, ledger, "iOS の移行が足す列 (左) と、台帳の DOCUMENTS_ONLY_COLUMNS (右) が違う");
    }

    /// CloudKit で配らない列は、DDL にあって、同期の行型には無い (台帳の記述が今も正しい)。
    #[test]
    fn columns_not_synced_are_absent_from_the_sync_rows() {
        let ddl = ddl_schema();
        let mapping = include_str!("ck_record_mapping.rs");
        for c in COLUMNS_NOT_SYNCED {
            assert!(
                ddl.get(c.table).is_some_and(|cols| cols.iter().any(|x| x == c.column)),
                "{}.{} が DDL に無い",
                c.table,
                c.column
            );
            let row = match c.table {
                "songs" => "CkSongRow",
                other => panic!("{other} の同期の行型をこのテストに足すこと"),
            };
            let body = mapping
                .split(&format!("pub struct {row} {{"))
                .nth(1)
                .and_then(|rest| rest.split("\n}").next())
                .unwrap_or_else(|| panic!("{row} が見つからない"));
            assert!(
                !body.contains(&format!("pub {}:", c.column)),
                "{row} が {} を持っている。配るなら台帳の COLUMNS_NOT_SYNCED から外すこと",
                c.column
            );
        }
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
