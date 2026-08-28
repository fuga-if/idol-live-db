//! ユニット系クエリ (UnitReading ポートの移送)。
//!
//! SQL 時代の対応:
//! - iOS `AppDatabase+StatsQueries.fetchUnitIndexQuery` (セトリのユニット逆引き索引。
//!   メモ化されていた重い索引だが、スナップショット構築時の前計算 (members_by_unit /
//!   songs_by_unit) をそのまま射影するので毎回呼んでも軽い)
//! - iOS `AppDatabase+StatsQueries.fetchAllUnitsQuery` / `fetchUnitQuery` /
//!   `fetchUnitMembersQuery` / `fetchUnitSongsQuery`
//! - iOS `AppDatabase+IdolQueries.fetchPerformedUnitIdsQuery`
//!   (イベント内で「ユニット単独曲」として披露されたユニットの逆引き)
//!
//! `fetchUnitIdsWithSongs` 相当は Phase 2 で idol_song_queries::unit_ids_with_songs が
//! 移送済み (FFI: SnapshotStore::unit_ids_with_songs)。二重 export しない。
//!
//! SQL の暗黙挙動をコードで明示して固定する:
//! - ORDER BY の NULL 位置: SQLite は ASC で NULL 先頭。Rust の `Option` は
//!   `None < Some` なのでそのまま一致する (songs_by_unit の release_date ASC)。
//! - 文字列比較はスキーマに COLLATE 指定がなく BINARY (バイト列比較)。Rust の `str` の
//!   `Ord` と同じ。
//! - SQL で未規定だった同順位・集合出力の並びは、スナップショットの添字を最終キーに
//!   して決定的にする (プラットフォーム間で同一結果を返すのが共有コアの目的)。
//! - songs.unit_id の FK 孤児 (units に実在しない id) は返さない。Phase 2 の
//!   unit_ids_with_songs と同じ意図的差分で、呼び出し側 (UnitIndex の逆引き・
//!   曲あり/なし分割) は units 由来の実在 id としか突き合わせないため観測不能。

use crate::domain::snapshot::Snapshot;
use std::collections::HashSet;

/// units 1 行ぶんの射影 (iOS GRDB `Unit` の全カラム)。
///
/// 名前を iOS 側 (`Unit`) と揃えていないのは意図的: 生成バインディングがアプリと
/// 同一モジュールに入るため、既存 Swift struct と衝突する (Phase 2 の前例と同じ判断)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UnitRecord {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub is_permanent: bool,
    pub name_alt: Option<String>,
}

/// unit_members 1 行ぶんの射影 (`SELECT unit_id, idol_id FROM unit_members` の行)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UnitMemberLinkRecord {
    pub unit_id: String,
    pub idol_id: String,
}

/// `fetchUnitIndexQuery` の 3 クエリぶんをまとめた射影 (FFI 1 呼び出し = 1 ユーザー操作)。
/// プラットフォーム側はこれから UnitIndex (memberIds / byIdol の Map) を組み立てる。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UnitIndexRecord {
    /// 全ユニット。並びはスナップショット順 (= rowid 順 = `Unit.fetchAll` の走査順)。
    /// UnitIndex.exactMatchingUnits は units の並び順で先勝ちするため、順序も忠実に保つ。
    pub units: Vec<UnitRecord>,
    /// unit_members の全行。元 SQL は ORDER BY なし (Swift 側は Set に落とすので
    /// 順序は無観測)。ここでは (unit 添字, メンバー sort_order) 順で決定的にしてある。
    pub member_links: Vec<UnitMemberLinkRecord>,
    /// 曲を持つ unit_id (`SELECT DISTINCT unit_id FROM songs WHERE unit_id IS NOT NULL
    /// AND unit_id != ''`)。FK 孤児は含まない (モジュール docs の意図的差分)。
    /// 並びは unit のスナップショット添字順。
    pub song_unit_ids: Vec<String>,
}

fn record(snap: &Snapshot, unit_index: u32) -> UnitRecord {
    let u = &snap.units[unit_index as usize];
    UnitRecord {
        id: u.id.clone(),
        brand_id: u.brand_id.clone(),
        name: u.name.clone(),
        is_permanent: u.is_permanent,
        name_alt: u.name_alt.clone(),
    }
}

/// ユニット逆引き索引の材料一式 (iOS `fetchUnitIndexQuery` 相当)。
pub fn unit_index_data(snap: &Snapshot) -> UnitIndexRecord {
    let units: Vec<UnitRecord> = (0..snap.units.len() as u32).map(|i| record(snap, i)).collect();
    let member_links = snap
        .members_by_unit
        .iter()
        .enumerate()
        .flat_map(|(ui, members)| {
            members.iter().map(move |&ii| UnitMemberLinkRecord {
                unit_id: snap.units[ui].id.clone(),
                idol_id: snap.idols[ii as usize].id.clone(),
            })
        })
        .collect();
    let song_unit_ids = snap
        .songs_by_unit
        .iter()
        .enumerate()
        .filter(|(_, songs)| !songs.is_empty())
        .map(|(ui, _)| snap.units[ui].id.clone())
        .collect();
    UnitIndexRecord { units, member_links, song_unit_ids }
}

/// 単一ユニット (iOS `fetchUnitQuery` = `Unit.fetchOne(db, key: id)` 相当)。
pub fn unit_by_id(snap: &Snapshot, id: &str) -> Option<UnitRecord> {
    snap.unit_index_by_id.get(id).map(|&ui| record(snap, ui))
}

pub fn all_units(snap: &Snapshot) -> Vec<UnitRecord> {
    snap.unit_order.iter().map(|&ui| record(snap, ui)).collect()
}

/// 所属メンバーの idol_id 列 (iOS `fetchUnitMembersQuery` 相当)。
///
/// 元 SQL:
/// ```sql
/// SELECT i.* FROM idols i JOIN unit_members um ON i.id = um.idol_id
/// WHERE um.unit_id = ? ORDER BY i.sort_order
/// ```
/// 実体化 (Idol Record) はプラットフォーム側の責務。並びは members_by_unit の
/// 前計算 (sort_order ASC, NULL 先頭・同値は添字)。未知 id は空 (SQL の 0 行)。
pub fn unit_member_idol_ids(snap: &Snapshot, unit_id: &str) -> Vec<String> {
    let Some(&ui) = snap.unit_index_by_id.get(unit_id) else { return vec![] };
    snap.members_by_unit[ui as usize]
        .iter()
        .map(|&ii| snap.idols[ii as usize].id.clone())
        .collect()
}

/// ユニット持ち曲の song_id 列 (iOS `fetchUnitSongsQuery` 相当)。
///
/// 元 SQL: `SELECT * FROM songs WHERE unit_id = ? ORDER BY release_date`。
/// 並びは songs_by_unit の前計算 (release_date ASC, NULL 先頭・同日は添字)。
pub fn unit_song_ids(snap: &Snapshot, unit_id: &str) -> Vec<String> {
    let Some(&ui) = snap.unit_index_by_id.get(unit_id) else { return vec![] };
    snap.songs_by_unit[ui as usize]
        .iter()
        .map(|&si| snap.songs[si as usize].id.clone())
        .collect()
}

/// イベント内で「ユニット単独曲」として披露されたユニット id 集合
/// (iOS `fetchPerformedUnitIdsQuery` 相当)。
///
/// 元実装は 2 本の SQL + Swift 集合演算:
/// 1. イベント配下の各 setlist_item の歌唱 idol 集合 (setlist_performers)
/// 2. 曲ありユニット (EXISTS songs.unit_id = u.id) の member 集合 (unit_members)
/// 3. 「歌唱集合 (2 人以上) == member 集合 (2 人以上)」の完全一致ユニットを採用
///
/// 戻りは Swift 側が Set<String> にするため元は順序未規定。ここでは unit の
/// スナップショット添字順で決定的に返す。未知 event_id は空。
pub fn performed_unit_ids(snap: &Snapshot, event_id: &str) -> Vec<String> {
    let Some(&e) = snap.event_index_by_id.get(event_id) else { return vec![] };

    // step 1: 各披露の歌唱メンバー集合。重複行を潰した上で 2 人未満は
    // ユニット成立し得ないので落とす (元実装の `perfSet.count >= 2` と同値)。
    let mut perf_sets: Vec<HashSet<u32>> = Vec::new();
    for &sh in &snap.shows_by_event[e as usize] {
        for &item in &snap.setlist_items_by_show[sh as usize] {
            let set: HashSet<u32> =
                snap.performers_by_item[item as usize].iter().copied().collect();
            if set.len() >= 2 {
                perf_sets.push(set);
            }
        }
    }
    if perf_sets.is_empty() {
        return vec![];
    }

    // step 2-3: 曲ありユニットの member 集合と完全一致するものを採用。
    let mut matched: Vec<String> = Vec::new();
    for (ui, members) in snap.members_by_unit.iter().enumerate() {
        if snap.songs_by_unit[ui].is_empty() || members.len() < 2 {
            continue;
        }
        let member_set: HashSet<u32> = members.iter().copied().collect();
        // unit_members の重複行で見かけの人数が 2 以上でも実質 1 人なら不成立。
        if member_set.len() < 2 {
            continue;
        }
        if perf_sets.contains(&member_set) {
            matched.push(snap.units[ui].id.clone());
        }
    }
    matched
}

#[cfg(test)]
mod tests {

    /// 回帰 (2026-08-28): ユニット検索だけ かなを畳んでいなかった。
    ///
    /// Swift/Kotlin 側が `displayName.localizedCaseInsensitiveContains` を直に
    /// 呼んでいて、曲・アイドル・ライブが「あるすとろめりあ」で当たるのに
    /// ユニットだけ当たらない、という説明の付かない差になっていた。
    /// 一覧の絞り込みは `TextSearchCatalog` (= `text_search_index`) を通す約束で、
    /// ここでは**実データのユニット名がその規則で引ける**ことだけを押さえる
    /// (両プラットフォームとも一覧は「曲ありユニット」に絞ってから畳むので、
    /// 全ユニットを返す絞り込み関数はコアに置かない)。
    #[test]
    fn unit_names_fold_kana_under_the_shared_match_rule() {
        use crate::domain::text_search_index::match_range;
        let snap = snap();
        let katakana = snap
            .units
            .iter()
            .find(|u| {
                u.name.chars().count() >= 4
                    && u.name.chars().all(|c| ('\u{30A0}'..='\u{30FF}').contains(&c))
            })
            .expect("カタカナだけのユニットが 1 つはある");
        let hiragana: String = katakana
            .name
            .chars()
            .map(|c| {
                if ('\u{30A1}'..='\u{30F6}').contains(&c) {
                    char::from_u32(c as u32 - 0x60).unwrap()
                } else {
                    c
                }
            })
            .collect();
        assert!(match_range(&katakana.name, &katakana.name).is_some());
        assert!(
            match_range(&katakana.name, &hiragana).is_some(),
            "「{hiragana}」で「{}」に当たらない",
            katakana.name
        );
    }

    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;
    use rusqlite::{Connection, OpenFlags};
    use std::collections::{HashMap, HashSet};
    use std::sync::OnceLock;

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    /// スナップショットは全テストで共有 (不変なので安全・ロードを 1 回にする)。
    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| load_snapshot(&db_path()).expect("bundle DB はロードできる"))
    }

    fn conn() -> Connection {
        Connection::open_with_flags(
            db_path(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB を開ける")
    }

    fn query_strings(db: &Connection, sql: &str, params: &[&str]) -> Vec<String> {
        let mut stmt = db.prepare(sql).expect("元 SQL は妥当");
        stmt.query_map(rusqlite::params_from_iter(params.iter()), |r| r.get::<_, String>(0))
            .expect("元 SQL を実行できる")
            .collect::<Result<_, _>>()
            .expect("行を読める")
    }

    /// ORDER BY キーが同値の区間を集合として比較する等価判定 (song_list_queries と同旨)。
    /// SQLite のソータは安定でなく同値区間の並びは未規定のため、キー列の一致 +
    /// 同値区間のメンバー一致を等価とみなす。
    fn assert_matches_up_to_ties<K>(
        label: &str,
        actual: &[String],
        expected: &[String],
        key: impl Fn(&String) -> K,
    ) where
        K: PartialEq + std::fmt::Debug,
    {
        assert_eq!(actual.len(), expected.len(), "{label}: 件数");
        let mut start = 0;
        while start < expected.len() {
            let k = key(&expected[start]);
            let mut end = start;
            while end < expected.len() && key(&expected[end]) == k {
                end += 1;
            }
            let expected_group: HashSet<&String> = expected[start..end].iter().collect();
            let actual_group: HashSet<&String> = actual[start..end].iter().collect();
            assert_eq!(actual_group, expected_group, "{label}: キー {k:?} の同順位グループ");
            start = end;
        }
    }

    // ---- 照合テスト (元 SQL との等価性保証) ----

    #[test]
    fn unit_index_matches_sql() {
        let db = conn();
        let data = unit_index_data(snap());

        // units: fetchAll (`SELECT * FROM units`、ORDER BY なし) と並び・全カラム逐語一致。
        // 注意: `SELECT id FROM units` は covering index (PK) 走査で id 順になり
        // 全行スキャンの rowid 順と食い違うため、基準は必ず全カラムの走査で取る。
        let mut stmt = db
            .prepare("SELECT id, brand_id, name, is_permanent, name_alt FROM units")
            .unwrap();
        let expected_rows: Vec<UnitRecord> = stmt
            .query_map([], |r| {
                Ok(UnitRecord {
                    id: r.get(0)?,
                    brand_id: r.get(1)?,
                    name: r.get(2)?,
                    is_permanent: r.get::<_, i64>(3)? != 0,
                    name_alt: r.get(4)?,
                })
            })
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(expected_rows.len() >= 100, "units は 3 桁以上ある前提");
        assert_eq!(data.units, expected_rows, "units の並び (rowid 順) と全カラム");

        // member_links: 元 SQL の全行と集合一致 (Swift 側は Set 構築なので順序無観測)。
        let mut stmt = db.prepare("SELECT unit_id, idol_id FROM unit_members").unwrap();
        let expected_links: Vec<(String, String)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let expected_set: HashSet<(String, String)> = expected_links.iter().cloned().collect();
        let actual_set: HashSet<(String, String)> = data
            .member_links
            .iter()
            .map(|l| (l.unit_id.clone(), l.idol_id.clone()))
            .collect();
        assert_eq!(actual_set, expected_set, "unit_members の (unit_id, idol_id) 集合");
        // 行数も一致 = FK 孤児・重複行による差分が bundle に無いことの確認。
        assert_eq!(data.member_links.len(), expected_links.len(), "unit_members の行数");

        // song_unit_ids: 元 SQL の DISTINCT 集合と一致 (FK 孤児は units 実在分に限る)。
        let raw: HashSet<String> = query_strings(
            &db,
            "SELECT DISTINCT unit_id FROM songs WHERE unit_id IS NOT NULL AND unit_id != ''",
            &[],
        )
        .into_iter()
        .collect();
        let existing: HashSet<String> = query_strings(
            &db,
            "SELECT DISTINCT unit_id FROM songs
             WHERE unit_id IS NOT NULL AND unit_id != ''
               AND unit_id IN (SELECT id FROM units)",
            &[],
        )
        .into_iter()
        .collect();
        let actual: HashSet<String> = data.song_unit_ids.iter().cloned().collect();
        assert!(!actual.is_empty());
        assert_eq!(actual, existing, "曲ありユニット集合 (units 実在分)");
        // 意図的差分の観測不能性: 孤児 id は units のどの id とも一致しないので、
        // UnitIndex 側の突き合わせ (unitsWithSongs.contains(unit.id)) では差が出ない。
        let unit_ids: HashSet<String> = data.units.iter().map(|u| u.id.clone()).collect();
        for orphan in raw.difference(&existing) {
            assert!(!unit_ids.contains(orphan), "孤児 {orphan} は units に居ないはず");
        }
    }

    #[test]
    fn all_units_matches_sql() {
        let db = conn();
        let expected = query_strings(&db, "SELECT id FROM units ORDER BY brand_id, name", &[]);
        assert!(!expected.is_empty());
        let actual: Vec<String> = all_units(snap()).iter().map(|u| u.id.clone()).collect();
        // ORDER BY キー (brand_id, name) ごとの同順位グループで比較。
        let key_of: HashMap<String, (String, String)> = snap()
            .units
            .iter()
            .map(|u| (u.id.clone(), (u.brand_id.clone(), u.name.clone())))
            .collect();
        assert_matches_up_to_ties("all_units", &actual, &expected, |id| key_of[id].clone());
    }

    #[test]
    fn unit_and_members_match_sql() {
        let db = conn();
        // メンバー 2 人以上のユニットを実データから拾う (データ更新に強くする)。
        let sample = query_strings(
            &db,
            "SELECT unit_id FROM unit_members GROUP BY unit_id
             HAVING COUNT(*) >= 2 ORDER BY unit_id LIMIT 5",
            &[],
        );
        assert_eq!(sample.len(), 5);
        for unit_id in &sample {
            // fetchUnitQuery: 全カラム一致。
            let expected = db
                .query_row(
                    "SELECT id, brand_id, name, is_permanent, name_alt FROM units WHERE id = ?1",
                    [unit_id],
                    |r| {
                        Ok(UnitRecord {
                            id: r.get(0)?,
                            brand_id: r.get(1)?,
                            name: r.get(2)?,
                            is_permanent: r.get::<_, i64>(3)? != 0,
                            name_alt: r.get(4)?,
                        })
                    },
                )
                .unwrap();
            assert_eq!(unit_by_id(snap(), unit_id), Some(expected), "unit {unit_id}");

            // fetchUnitMembersQuery: ORDER BY i.sort_order (同値は未規定 → up to ties)。
            let expected_members = query_strings(
                &db,
                "SELECT i.id FROM idols i JOIN unit_members um ON i.id = um.idol_id
                 WHERE um.unit_id = ?1 ORDER BY i.sort_order",
                &[unit_id],
            );
            assert!(expected_members.len() >= 2);
            let actual_members = unit_member_idol_ids(snap(), unit_id);
            let sort_key = |id: &String| {
                snap().idols[snap().idol_index_by_id[id] as usize].sort_order
            };
            assert_matches_up_to_ties(
                &format!("members of {unit_id}"),
                &actual_members,
                &expected_members,
                sort_key,
            );
        }
        assert_eq!(unit_by_id(snap(), "存在しないunit"), None);
    }

    #[test]
    fn unit_songs_match_sql() {
        let db = conn();
        // 曲 3 曲以上のユニット (units 実在) を実データから拾う。
        let sample = query_strings(
            &db,
            "SELECT unit_id FROM songs
             WHERE unit_id IS NOT NULL AND unit_id != ''
               AND unit_id IN (SELECT id FROM units)
             GROUP BY unit_id HAVING COUNT(*) >= 3 ORDER BY unit_id LIMIT 5",
            &[],
        );
        assert_eq!(sample.len(), 5);
        for unit_id in &sample {
            let expected = query_strings(
                &db,
                "SELECT id FROM songs WHERE unit_id = ?1 ORDER BY release_date",
                &[unit_id],
            );
            assert!(expected.len() >= 3);
            let actual = unit_song_ids(snap(), unit_id);
            let release_key = |id: &String| {
                snap().songs[snap().song_index_by_id[id] as usize].release_date.clone()
            };
            assert_matches_up_to_ties(
                &format!("songs of {unit_id}"),
                &actual,
                &expected,
                release_key,
            );
        }
    }

    /// iOS `fetchPerformedUnitIdsQuery` の 2 本の SQL + Swift 集合演算の写経を
    /// rusqlite 上で実行し、その結果 (Set) と一致することを確認する。
    fn run_original_performed_unit_ids(db: &Connection, event_id: &str) -> HashSet<String> {
        // step 1: イベント配下の各 setlist_item の歌唱 idol 集合。
        let mut stmt = db
            .prepare(
                "SELECT si.id AS item_id, sp.idol_id AS idol_id
                 FROM setlist_items si
                 JOIN shows sh ON sh.id = si.show_id
                 JOIN setlist_performers sp ON sp.setlist_item_id = si.id
                 WHERE sh.event_id = ?1",
            )
            .unwrap();
        let mut perf_by_item: HashMap<String, HashSet<String>> = HashMap::new();
        let rows = stmt
            .query_map([event_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .unwrap();
        for row in rows {
            let (item, idol) = row.unwrap();
            perf_by_item.entry(item).or_default().insert(idol);
        }
        if perf_by_item.is_empty() {
            return HashSet::new();
        }
        // step 2: 曲ありユニットの member 集合。
        let mut stmt = db
            .prepare(
                "SELECT um.unit_id AS uid, um.idol_id AS iid
                 FROM unit_members um
                 JOIN units u ON u.id = um.unit_id
                 WHERE EXISTS (SELECT 1 FROM songs s WHERE s.unit_id = u.id)",
            )
            .unwrap();
        let mut members_by_unit: HashMap<String, HashSet<String>> = HashMap::new();
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .unwrap();
        for row in rows {
            let (uid, iid) = row.unwrap();
            members_by_unit.entry(uid).or_default().insert(iid);
        }
        // step 3: 完全一致 (1-unit exact)。
        let mut matched = HashSet::new();
        for perf_set in perf_by_item.values().filter(|s| s.len() >= 2) {
            for (uid, members) in &members_by_unit {
                if members.len() >= 2 && members == perf_set {
                    matched.insert(uid.clone());
                }
            }
        }
        matched
    }

    #[test]
    fn performed_unit_ids_match_sql() {
        let db = conn();
        // ユニット持ち曲が 2 人以上で披露されたイベント = 完全一致が出やすい母集団。
        let events = query_strings(
            &db,
            "SELECT DISTINCT sh.event_id FROM setlist_items si
             JOIN shows sh ON sh.id = si.show_id
             JOIN songs s ON s.id = si.song_id
             WHERE s.unit_id IS NOT NULL AND s.unit_id != ''
               AND (SELECT COUNT(DISTINCT sp.idol_id) FROM setlist_performers sp
                    WHERE sp.setlist_item_id = si.id) >= 2
             ORDER BY sh.event_id LIMIT 8",
            &[],
        );
        assert!(!events.is_empty(), "ユニット曲披露イベントが bundle に存在する前提");
        let mut nonempty = 0usize;
        for event_id in &events {
            let expected = run_original_performed_unit_ids(&db, event_id);
            let actual: HashSet<String> =
                performed_unit_ids(snap(), event_id).into_iter().collect();
            assert_eq!(actual, expected, "event {event_id}");
            if !expected.is_empty() {
                nonempty += 1;
            }
        }
        // 全件空だと照合が退化する — 少なくとも 1 件は実際にユニットが立っていること。
        assert!(nonempty >= 1, "検証対象の {} イベント全てが空集合", events.len());

        // 戻り順の決定性: unit のスナップショット添字順。
        for event_id in &events {
            let ids = performed_unit_ids(snap(), event_id);
            let indexes: Vec<u32> =
                ids.iter().map(|id| snap().unit_index_by_id[id]).collect();
            let mut sorted = indexes.clone();
            sorted.sort_unstable();
            assert_eq!(indexes, sorted, "event {event_id} の戻り順");
        }
    }

    // ---- 単体 (SQL 非依存の境界ケース) ----

    #[test]
    fn unknown_ids_are_harmless() {
        assert!(unit_member_idol_ids(snap(), "存在しないunit").is_empty());
        assert!(unit_song_ids(snap(), "存在しないunit").is_empty());
        assert!(performed_unit_ids(snap(), "存在しないevent").is_empty());
        assert_eq!(unit_by_id(snap(), ""), None);
    }

    #[test]
    fn unit_index_projections_are_consistent() {
        let data = unit_index_data(snap());
        // member_links の unit_id / idol_id は必ず units / idols に実在する
        // (ローダが FK 孤児を読み飛ばす契約の再確認)。
        let unit_ids: HashSet<&str> = data.units.iter().map(|u| u.id.as_str()).collect();
        for link in &data.member_links {
            assert!(unit_ids.contains(link.unit_id.as_str()));
            assert!(snap().idol_index_by_id.contains_key(&link.idol_id));
        }
        // song_unit_ids ⊆ units、かつ各ユニットの unit_song_ids は非空。
        for uid in &data.song_unit_ids {
            assert!(unit_ids.contains(uid.as_str()));
            assert!(!unit_song_ids(snap(), uid).is_empty());
        }
        // unitsWithSongs 由来の分割 (曲あり/なし) が Phase 2 の
        // unit_ids_with_songs と同じ答えになる (二重実装の等価性)。
        let all_ids: Vec<String> = data.units.iter().map(|u| u.id.clone()).collect();
        let via_phase2 =
            crate::domain::idol_song_queries::unit_ids_with_songs(snap(), &all_ids);
        let expected: HashSet<String> = data.song_unit_ids.iter().cloned().collect();
        let actual: HashSet<String> = via_phase2.into_iter().collect();
        assert_eq!(actual, expected);
    }
}
