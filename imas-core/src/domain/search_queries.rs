//! 横断検索 (グローバル検索) のクエリ群 (SQL 時代の検索を Snapshot 上の純粋関数へ移送)。
//!
//! SQL 時代の対応:
//! - iOS `AppDatabase+StatsQueries.searchQuery` (`GlobalSearchReading.search` の実体。
//!   アダプタは `GRDBGlobalSearchRepository`)。GRDB が生成していた SQL は 3 本:
//!   - `SELECT * FROM songs  WHERE title LIKE ? ESCAPE '\' OR title_kana LIKE ? ESCAPE '\' LIMIT 20`
//!   - `SELECT * FROM idols  WHERE name  LIKE ? ESCAPE '\' OR name_kana  LIKE ? ESCAPE '\' LIMIT 20`
//!   - `SELECT * FROM events WHERE name  LIKE ? ESCAPE '\' OR name_kana  LIKE ? ESCAPE '\' LIMIT 20`
//!   - バインド値はどれも `%<likeEscaped(query)>%` (Swift `String.likeEscaped` が `\` `%` `_` を
//!     エスケープするので、検索語は**リテラルの部分一致**として当たる)。
//!
//! SQL の暗黙挙動をコードで明示して固定する:
//! - `LIKE '%q%'` は ASCII だけ大文字小文字を無視する部分一致 (SQLite 既定の LIKE)。
//!   UTF-8 の多バイト文字は継続バイトが 0x80 以上で ASCII と衝突しないため、
//!   バイト列上の大小無視探索で等価になる。
//! - NULL 列 (title_kana / name_kana) への LIKE は NULL = 不一致。
//! - `LIMIT 20` は ORDER BY なし: 結果はテーブル走査順 (= rowid 昇順) の先頭 20 件。
//!   3 本とも EXPLAIN QUERY PLAN が `SCAN` (LIKE の先頭 `%` で索引を使えない) なので
//!   走査順は rowid 昇順で決定的。Snapshot の各 Vec は同じ全表走査で読み込まれるため、
//!   添字順の走査 + 先頭 20 件がそのまま元 SQL の結果順になる。
//!
//! **畳み込みは `text_search_index::FoldedNeedle` に寄せてある** (この節はかつて
//! 「`text_search_index` を使わないのは意図的」と書いていたが、実装が変わっている)。
//!
//! もとは SQLite `LIKE` の「ASCII の大文字小文字だけ」を忠実に写していた。だが同じ
//! 検索欄に同じ語を打っても、iOS (一覧を `TextSearchCatalog` で絞る) では当たるのに
//! Android (このクエリ関数を通る) では当たらない、という形で使う人に見えていた。
//! `FoldedNeedle` が畳む範囲は `LIKE` の真の上位集合なので、寄せても従来出ていた行が
//! 消えることはなく、当たり方だけが 3 プラットフォームで揃う。
//!
//! 変わっていないのは**件数と順序**の契約: `LIMIT 20` 相当の [`GLOBAL_SEARCH_LIMIT`] と、
//! rowid 昇順 (= Snapshot の添字順) の走査順は元 SQL のまま。

use crate::domain::snapshot::Snapshot;
use crate::domain::text_search_index::FoldedNeedle;

/// iOS `searchQuery` の `.limit(20)` の写し。各エンティティ種別ごとの上限。
pub const GLOBAL_SEARCH_LIMIT: usize = 20;

/// 横断検索の結果 (表示順の id 列 3 本)。iOS `SearchResults` に対応する射影
/// (実体化はプラットフォーム側が自国の store で行う。名前を iOS 側と揃えないのは
/// 生成バインディングが同一モジュールに入り既存 Swift struct と衝突するため)。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct GlobalSearchHits {
    pub song_ids: Vec<String>,
    pub idol_ids: Vec<String>,
    pub event_ids: Vec<String>,
}


/// 曲の横断検索 (title / title_kana の部分一致、先頭 20 件)。添字はスナップショット順。
pub fn searched_song_indexes(snap: &Snapshot, query: &str) -> Vec<u32> {
    let needle = FoldedNeedle::new(query);
    snap.songs
        .iter()
        .enumerate()
        .filter(|(i, _)| snap.song_search[*i].matches(needle.as_bytes()))
        .map(|(i, _)| i as u32)
        .take(GLOBAL_SEARCH_LIMIT)
        .collect()
}

/// アイドルの横断検索 (name / name_kana の部分一致、先頭 20 件)。
/// 元 SQL 同様 is_external も対象に含める (絞らないのが現行仕様)。
pub fn searched_idol_indexes(snap: &Snapshot, query: &str) -> Vec<u32> {
    let needle = FoldedNeedle::new(query);
    snap.idols
        .iter()
        .enumerate()
        .filter(|(i, _)| snap.idol_search[*i].matches(needle.as_bytes()))
        .map(|(i, _)| i as u32)
        .take(GLOBAL_SEARCH_LIMIT)
        .collect()
}

/// イベントの横断検索 (name / name_kana の部分一致、先頭 20 件)。
///
/// 漢字のライブ名は読みが無いとかなで引けない。曲・アイドルと同じ扱いに揃える。
pub fn searched_event_indexes(snap: &Snapshot, query: &str) -> Vec<u32> {
    let needle = FoldedNeedle::new(query);
    snap.events
        .iter()
        .enumerate()
        .filter(|(i, _)| snap.event_search[*i].matches(needle.as_bytes()))
        .map(|(i, _)| i as u32)
        .take(GLOBAL_SEARCH_LIMIT)
        .collect()
}

/// 種別ごとの一致件数 (打ち切りなし)。
///
/// 各一覧の検索欄が「いま見ているタブ以外に何件あるか」を出すために使う。
/// `global_search` と違って**上限で切らない**。「ライブに 20 件」と出したのに
/// 実は 137 件ある、では切り替える判断の根拠にならないため。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SearchCounts {
    pub songs: u32,
    pub idols: u32,
    pub events: u32,
}

/// 打った語が種別ごとに何件当たるかを数える。
///
/// 当たり方は各一覧の検索と同じ索引を通るので、「N 件」と出しておいて
/// 切り替えたら違う数だった、が起きない。
///
/// 実体は返さない。件数だけなら id の複製も並べ替えも要らず、
/// 打鍵ごとに呼んでも 3 種類あわせて数 ms で終わる。
pub fn search_counts(snap: &Snapshot, query: &str) -> SearchCounts {
    let needle = FoldedNeedle::new(query);
    let count = |indexes: &[crate::domain::text_search_index::TextSearchIndex]| {
        indexes.iter().filter(|ix| ix.matches(needle.as_bytes())).count() as u32
    };
    SearchCounts {
        songs: count(&snap.song_search),
        idols: count(&snap.idol_search),
        events: count(&snap.event_search),
    }
}

/// 打った語がライブの「今後の予定」「開催済み」それぞれに何件あるか。
///
/// ライブ一覧は 2 つに分かれていて、既定は「今後の予定」。そこへ
/// 「ライブに 1 件」から飛ぶと、当たりが過去のライブだった場合に **0 件の画面へ
/// 着地する**。件数を見せて誘っておいて空を出すのは、この導線の趣旨に反する。
///
/// 境界の規則 (境界日ちょうどは今後側 / 日付不明は今後にのみ残す) は
/// [`crate::domain::event_grouping::group_events_by_year`] が正本で、ここも同じ
/// 関数に通す。両 OS で日付の切り方を書き直すと必ずずれる。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventSearchSides {
    pub upcoming: u32,
    pub past: u32,
}

pub fn event_search_sides(snap: &Snapshot, query: &str, today_key: &str) -> EventSearchSides {
    let needle = FoldedNeedle::new(query);
    let first_dates: Vec<Option<String>> = snap
        .events
        .iter()
        .enumerate()
        .filter(|(i, _)| snap.event_search[*i].matches(needle.as_bytes()))
        .map(|(i, _)| first_show_date(snap, i as u32))
        .collect();

    let count = |upcoming: bool| {
        crate::domain::event_grouping::group_events_by_year(&first_dates, upcoming, today_key)
            .iter()
            .map(|g| g.indices.len() as u32)
            .sum()
    };
    EventSearchSides { upcoming: count(true), past: count(false) }
}

/// 初回公演日 (公演が無ければ None)。`group_events_by_year` に渡す射影。
fn first_show_date(snap: &Snapshot, event_index: u32) -> Option<String> {
    snap.shows_by_event[event_index as usize]
        .iter()
        .map(|&s| snap.shows[s as usize].date.clone())
        .min()
}

/// 横断検索 1 回分 (曲/アイドル/イベントまとめて)。SQL 時代の `searchQuery` と同じく
/// 1 ユーザー操作 = この 1 関数で、FFI もこれを 1 呼び出しで渡す。
pub fn global_search(snap: &Snapshot, query: &str) -> GlobalSearchHits {
    GlobalSearchHits {
        song_ids: searched_song_indexes(snap, query)
            .into_iter()
            .map(|i| snap.songs[i as usize].id.clone())
            .collect(),
        idol_ids: searched_idol_indexes(snap, query)
            .into_iter()
            .map(|i| snap.idols[i as usize].id.clone())
            .collect(),
        event_ids: searched_event_indexes(snap, query)
            .into_iter()
            .map(|i| snap.events[i as usize].id.clone())
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;
    use rusqlite::{Connection, OpenFlags};
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

    /// Swift `String.likeEscaped` の写経 (テスト側で元 SQL のバインド値を組むのに使う)。
    fn like_escaped(s: &str) -> String {
        s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    /// GRDB 生成 SQL の写経を rusqlite で直接実行した id 列 (これが等価性の基準)。
    /// ORDER BY なしの LIMIT なので順序も含めて比較する (走査は 3 本とも SCAN =
    /// rowid 昇順で決定的。実行計画が変わればこの照合が落ちて教えてくれる)。
    fn run_original_sql(table: &str, kana_col: Option<&str>, query: &str) -> Vec<String> {
        let name_col = if table == "songs" { "title" } else { "name" };
        let cond = match kana_col {
            Some(kana) => {
                format!("({name_col} LIKE ? ESCAPE '\\' OR {kana} LIKE ? ESCAPE '\\')")
            }
            None => format!("{name_col} LIKE ? ESCAPE '\\'"),
        };
        let sql = format!("SELECT t.* FROM {table} t WHERE {cond} LIMIT 20");
        let pattern = format!("%{}%", like_escaped(query));
        let params: Vec<&str> = if kana_col.is_some() {
            vec![&pattern, &pattern]
        } else {
            vec![&pattern]
        };
        let db = conn();
        let mut stmt = db.prepare(&sql).expect("元 SQL は妥当");
        stmt.query_map(rusqlite::params_from_iter(params), |r| r.get::<_, String>("id"))
            .expect("元 SQL を実行できる")
            .collect::<Result<Vec<_>, _>>()
            .expect("行を読める")
    }

    fn sql_songs(q: &str) -> Vec<String> {
        run_original_sql("songs", Some("title_kana"), q)
    }
    fn sql_idols(q: &str) -> Vec<String> {
        run_original_sql("idols", Some("name_kana"), q)
    }
    fn sql_events(q: &str) -> Vec<String> {
        run_original_sql("events", Some("name_kana"), q)
    }

    fn song_ids(q: &str) -> Vec<String> {
        searched_song_indexes(snap(), q)
            .into_iter()
            .map(|i| snap().songs[i as usize].id.clone())
            .collect()
    }
    fn idol_ids(q: &str) -> Vec<String> {
        searched_idol_indexes(snap(), q)
            .into_iter()
            .map(|i| snap().idols[i as usize].id.clone())
            .collect()
    }
    fn event_ids(q: &str) -> Vec<String> {
        searched_event_indexes(snap(), q)
            .into_iter()
            .map(|i| snap().events[i as usize].id.clone())
            .collect()
    }

    /// 3 種別まとめて元 SQL と順序込みで一致することを確かめる共通アサーション。
    fn assert_all_kinds_match_sql(q: &str) -> (usize, usize, usize) {
        let (s, i, e) = (sql_songs(q), sql_idols(q), sql_events(q));
        assert_eq!(song_ids(q), s, "songs: query={q:?}");
        assert_eq!(idol_ids(q), i, "idols: query={q:?}");
        assert_eq!(event_ids(q), e, "events: query={q:?}");
        (s.len(), i.len(), e.len())
    }

    // ---- 照合テスト (元 SQL との等価性保証) ----
    //
    // **ここでの「一致」は無条件ではない。** 判定は `FoldedNeedle` (大文字小文字 +
    // ひらがな↔カタカナを畳む) に寄せてあり、SQL の `LIKE` の真の上位集合になっている。
    // 下に並ぶ検索語は「両者が同じ集合になるもの」を選んである — 表記違いでしか
    // 増えないので、かな表記の揺れを跨がない語なら一致する。
    // 増える側の実例は `kana_folding_finds_more_than_sql_like` に置いた。
    // 語を足すときは、増分が出ないことを確かめてからここへ入れること。

    /// 実データで当たり方の異なる検索語 5 系統。各種別が元 SQL と順序込みで一致する。
    #[test]
    fn search_terms_match_sql() {
        // (検索語, 1 件以上ヒットするはずの種別があるか) — 全滅の検索語はここに置かない
        for q in ["夢", "ready", "M@STER", "はるか", "ミリオン"] {
            let (s, i, e) = assert_all_kinds_match_sql(q);
            assert!(s + i + e > 0, "query={q:?} は 1 件以上ヒットする前提");
        }
    }

    /// LIKE の ASCII 大小無視: "ready" と "READY" は同一結果で、大小混在の題名が当たる。
    #[test]
    fn ascii_case_is_ignored_like_sql() {
        assert_all_kinds_match_sql("ready");
        assert_all_kinds_match_sql("READY");
        let lower = song_ids("ready");
        assert_eq!(lower, song_ids("READY"));
        // 大小混在ヒットが実在すること (全部同ケースなら大小無視の検証として退化)
        let titles: Vec<&str> = lower
            .iter()
            .map(|id| snap().songs[snap().song_index_by_id[id] as usize].title.as_str())
            .collect();
        assert!(titles.iter().any(|t| t.contains("READY")), "{titles:?}");
        assert!(titles.iter().any(|t| t.contains("Ready")), "{titles:?}");
    }

    /// LIMIT 20 の頭切り: 全件が 20 を超える検索語で「先頭 20 件 (rowid 順)」が一致する。
    /// 空文字クエリ (LIKE '%%') は全行一致 = 各テーブル先頭 20 件になるのも元 SQL と同じ。
    #[test]
    fn limit_caps_at_20_like_sql() {
        let db = conn();
        let total: i64 = db
            .query_row(
                "SELECT COUNT(*) FROM songs WHERE title LIKE '%夢%' OR title_kana LIKE '%夢%'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert!(total > 20, "「夢」は LIMIT を超えてヒットする前提 (total={total})");
        let (s, _, _) = assert_all_kinds_match_sql("夢");
        assert_eq!(s, 20);

        let (_, _, e) = assert_all_kinds_match_sql("M@STER");
        assert_eq!(e, 20);

        let (s, i, e) = assert_all_kinds_match_sql("");
        assert_eq!((s, i, e), (20, 20, 20));
    }

    /// likeEscaped の再現: `%` `_` はワイルドカードではなくリテラルとして当たる。
    /// 素通しなら "%" は全行一致になるので、空振り (SQL も空) が最強の検証になる。
    #[test]
    fn wildcards_are_escaped_like_sql() {
        let (s, i, e) = assert_all_kinds_match_sql("%");
        assert_eq!((s, i, e), (0, 0, 0), "リテラル % を含む行は現データに無い前提");

        // "_" はリテラル一致の実ヒットあり (fu_mou Remix / #cg_ootd 等)
        let (s, _, e) = assert_all_kinds_match_sql("_");
        assert!(s > 0 && e > 0, "リテラル _ のヒットが songs/events にある前提");

        assert_all_kinds_match_sql("\\"); // エスケープ文字そのもの (現データでは空振り)
    }

    /// kana 列の OR 到達: 「はるか」は name には無く name_kana だけで天海春香に当たる。
    #[test]
    fn kana_column_reaches_like_sql() {
        assert_all_kinds_match_sql("はるか");
        let ids = idol_ids("はるか");
        let harukas: Vec<&str> = ids
            .iter()
            .map(|id| snap().idols[snap().idol_index_by_id[id] as usize].name.as_str())
            .filter(|name| !name.contains("はるか"))
            .collect();
        assert!(harukas.contains(&"天海春香"), "kana 側だけで当たるヒットが要る: {ids:?}");
    }

    /// 件数は各一覧の検索と**同じ当たり方**であること。
    ///
    /// 「ライブに 8 件」と出しておいて、切り替えたら 3 件だった、では
    /// 切り替える判断の根拠にならない。数える側と絞る側で索引がずれたら落ちる。
    #[test]
    fn counts_agree_with_what_each_list_actually_shows() {
        for q in ["夢", "はるか", "ready", "武道館", "アルストロメリア", "zzz存在しない"] {
            let c = search_counts(snap(), q);
            let needle = FoldedNeedle::new(q);
            let songs = snap().song_search.iter().filter(|i| i.matches(needle.as_bytes())).count();
            let idols = snap().idol_search.iter().filter(|i| i.matches(needle.as_bytes())).count();
            let events = snap().event_search.iter().filter(|i| i.matches(needle.as_bytes())).count();
            assert_eq!((c.songs as usize, c.idols as usize, c.events as usize),
                       (songs, idols, events), "query={q:?}");
        }
    }

    /// 打ち切らない。`global_search` は各 20 件で切るが、件数は実数を返す。
    #[test]
    fn counts_are_not_capped_unlike_global_search() {
        // 実データで 20 件を超える語を選ぶ (超えないなら検証として退化する)。
        let c = search_counts(snap(), "の");
        assert!(c.songs > 20, "曲 {} 件", c.songs);
        assert_eq!(global_search(snap(), "の").song_ids.len(), 20, "横断検索は 20 件で切る");
    }

    /// 空の語は「絞り込んでいない」= 全件。一覧の挙動と同じ。
    #[test]
    fn empty_query_counts_everything() {
        let c = search_counts(snap(), "");
        assert_eq!(c.songs as usize, snap().songs.len());
        assert_eq!(c.idols as usize, snap().idols.len());
        assert_eq!(c.events as usize, snap().events.len());
    }

    /// 「今後」と「開催済み」を足すと、ライブの当たり総数に一致する。
    ///
    /// 一致しないなら、どちらにも入らない (= 飛んだ先で見えない) ライブがいる。
    /// 日付不明は今後側にのみ残る規則なので、取りこぼしはここで捕まる。
    #[test]
    fn event_sides_add_up_to_the_total_hits() {
        for q in ["ready", "武道館", "ライブ", "M@STER"] {
            let sides = event_search_sides(snap(), q, "2026-09-01");
            let total = search_counts(snap(), q).events;
            assert_eq!(sides.upcoming + sides.past, total, "query={q:?}");
        }
    }

    /// 境界日ちょうどは「今後」側 (`group_events_by_year` の規則をそのまま使う)。
    /// ここを自前で書き直すと、両 OS で日付の切り方がずれる。
    #[test]
    fn the_boundary_day_counts_as_upcoming() {
        // 実データから公演日を 1 つ取り、その日を「今日」として数える。
        let date = snap()
            .shows
            .iter()
            .map(|s| s.date.clone())
            .find(|d| d.len() == 10)
            .expect("フル日付の公演がある前提");
        let event = snap()
            .events
            .iter()
            .enumerate()
            .find(|(i, _)| first_show_date(snap(), *i as u32).as_deref() == Some(date.as_str()))
            .map(|(_, e)| e.name.clone())
            .expect("その日を初日とするライブがある前提");
        let sides = event_search_sides(snap(), &event, &date);
        assert!(sides.upcoming > 0, "境界日は今後側に入る: {event} / {date}");
    }

    /// `LIKE` から意図的に逸脱している側。**かなの表記違いでも当たる**。
    ///
    /// 長らくコアのクエリ関数だけが SQL 忠実 (ASCII の大小のみ) で、同じ語を同じ
    /// 検索欄に打っても iOS の一覧 (TextSearchCatalog) では当たり Android では
    /// 当たらなかった。増える方向にしか変わらないので、従来出ていた行は消えない。
    #[test]
    fn kana_folding_finds_more_than_sql_like() {
        // 実データから「カタカナ表記の題を持ち、読みがひらがな」の曲を 1 つ拾い、
        // 題のカタカナ部分をひらがなに開いた語で引く (SQL の LIKE では当たらない語)。
        let snap = snap();
        let (kana_query, sql_hits, ours) = snap
            .songs
            .iter()
            .find_map(|s| {
                let katakana: String = s
                    .title
                    .chars()
                    .filter(|c| ('\u{30A1}'..='\u{30F6}').contains(c))
                    .collect();
                if katakana.chars().count() < 4 {
                    return None;
                }
                let hiragana: String = katakana
                    .chars()
                    .map(|c| char::from_u32(c as u32 - 0x60).unwrap())
                    .collect();
                let sql = sql_songs(&hiragana);
                let ours = song_ids(&hiragana);
                (!ours.is_empty() && ours.len() > sql.len()).then_some((hiragana, sql, ours))
            })
            .expect("カタカナ題 + ひらがな読みの曲が実データにある前提");

        assert!(
            sql_hits.iter().all(|id| ours.contains(id)),
            "従来 SQL のヒットは全部残る: {kana_query}"
        );
        assert!(ours.len() > sql_hits.len(), "かなを畳んだぶん増える: {kana_query}");
    }

    #[test]
    fn no_hit_query_is_empty_like_sql() {
        let (s, i, e) = assert_all_kinds_match_sql("zzz存在しない検索語");
        assert_eq!((s, i, e), (0, 0, 0));
    }

    // ---- 純粋関数の性質 ----

    #[test]
    fn needle_matching_edge_cases() {
        let hit = |h: &str, n: &str| FoldedNeedle::new(n).matches(h);
        assert!(hit("READY!!", "ready"));
        assert!(hit("Ready Steady", "STEADY"));
        assert!(hit("夢色ハーモニー", "ハーモ"));
        assert!(hit("anything", "")); // LIKE '%%' と同じく全行に一致
        assert!(!hit("短", "短い方より長い検索語"));
        // 多バイト文字の途中バイトから始まる誤一致は起きない (「亜」E4BA9C vs「介」E4BB8B)
        assert!(!hit("亜", "介"));
        // ここが `LIKE` からの意図的な逸脱。SQL 忠実だった頃は当たらず、
        // 同じ語が iOS の一覧 (TextSearchCatalog) では当たっていた。
        assert!(hit("ツバサ", "つばさ"), "ひらがな↔カタカナを畳む");
    }

    #[test]
    fn null_kana_is_no_match() {
        let none: Option<&str> = None;
        assert!(!FoldedNeedle::new("夢").matches_opt(none));
        // `NULL LIKE '%%'` も結果は NULL = 不一致 (空パターンでも NULL 列は落ちる)
        assert!(!FoldedNeedle::new("").matches_opt(none));
    }

    /// global_search は 3 本の添字関数を id 化して束ねただけであること (二重実装の防止)。
    #[test]
    fn global_search_assembles_the_three_scans() {
        for q in ["夢", "M@STER", ""] {
            let hits = global_search(snap(), q);
            assert_eq!(hits.song_ids, song_ids(q), "query={q:?}");
            assert_eq!(hits.idol_ids, idol_ids(q), "query={q:?}");
            assert_eq!(hits.event_ids, event_ids(q), "query={q:?}");
        }
    }

    // ---- 検証環境の回帰ガード ----

    /// 共有 CARGO_TARGET_DIR の成果物混入の回帰ガード。別サンドボックス由来の陳腐化した
    /// テストバイナリが再利用されると「どのツリーを検証したか」が不定になり、QA の合否が
    /// 偽陽性/偽陰性になる事故が起きた (calendar 担当の作業中コードのテストが本ツリーの
    /// 検証で実行された)。コンパイル時に焼き込んだ自分自身のソースと、実行時にビルド元
    /// ツリーから読み直したソースをバイト照合することで、陳腐化バイナリは「ビルド元
    /// サンドボックスが削除済みで読めない」か「中身が違う」かのどちらかで音を立てて落ち、
    /// 静かな偽合格にならない。
    #[test]
    fn test_binary_was_built_from_this_tree() {
        let baked = include_str!("search_queries.rs");
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/src/domain/search_queries.rs");
        let on_disk = std::fs::read_to_string(path).unwrap_or_else(|e| {
            panic!("ビルド元ツリーの {path} を読めない = 陳腐化した成果物で検証している: {e}")
        });
        // assert_eq! だと不一致時にファイル全文をダンプするので使わない
        assert!(baked == on_disk, "ビルド元とディスク上の {path} が不一致 = 陳腐化した成果物で検証している");
    }
}
