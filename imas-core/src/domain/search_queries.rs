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
//! - `LIMIT 20` は ORDER BY なしだった (結果は物理的な行順の先頭 20 件で、iOS と Android で
//!   違った)。今は当たり方の強い順 (完全一致 → 前方一致 → 部分一致)・同じ強さは id 順に
//!   並べてから 20 件で切る (Q-07。[`strongest_first`])。
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
//! 変わっていないのは**件数**の契約: `LIMIT 20` 相当の [`GLOBAL_SEARCH_LIMIT`]。

use crate::domain::search_limits::GLOBAL_SEARCH_LIMIT;
use crate::domain::snapshot::Snapshot;
use crate::domain::text_search_index::{FoldedNeedle, MatchTier};

/// 横断検索の結果 (表示順の id 列 3 本)。iOS `SearchResults` に対応する射影
/// (実体化はプラットフォーム側が自国の store で行う。名前を iOS 側と揃えないのは
/// 生成バインディングが同一モジュールに入り既存 Swift struct と衝突するため)。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct GlobalSearchHits {
    pub song_ids: Vec<String>,
    pub idol_ids: Vec<String>,
    pub event_ids: Vec<String>,
}


/// 当たった行を**当たり方の強い順** (完全一致 → 前方一致 → 部分一致) に並べ、同じ強さの
/// 中は id 順にして、先頭 [`GLOBAL_SEARCH_LIMIT`] 件の添字を返す。
///
/// 並べ替えのキーが無いまま上限で切ると、何が切り捨てられるかが行の順で決まってしまう。
/// 物理的な行順は iOS と Android で違い、id 順は id の若いブランドに偏る (「夢」で
/// 765as と cg だけで 20 件が埋まる)。強さの判定は曖昧解決と同じ `FoldedNeedle::tier`。
fn strongest_first<'a>(
    needle: &FoldedNeedle,
    index: &[crate::domain::text_search_index::TextSearchIndex],
    rows: impl Iterator<Item = (&'a str, [Option<&'a str>; 2])>,
) -> Vec<u32> {
    let mut hits: Vec<(MatchTier, &str, u32)> = rows
        .enumerate()
        .filter(|(i, _)| index[*i].matches(needle.as_bytes()))
        .map(|(i, (id, spellings))| (needle.tier(&spellings), id, i as u32))
        .collect();
    hits.sort_unstable();
    hits.into_iter().take(GLOBAL_SEARCH_LIMIT).map(|(_, _, i)| i).collect()
}

/// 曲の横断検索 (title / title_kana の部分一致、先頭 20 件)。
pub fn searched_song_indexes(snap: &Snapshot, query: &str) -> Vec<u32> {
    let rows = snap.songs.iter().map(|s| (s.id.as_str(), [Some(s.title.as_str()), s.title_kana.as_deref()]));
    strongest_first(&FoldedNeedle::new(query), &snap.song_search, rows)
}

/// アイドルの横断検索 (name / name_kana の部分一致、先頭 20 件)。
/// 元 SQL 同様 is_external も対象に含める (絞らないのが現行仕様)。
pub fn searched_idol_indexes(snap: &Snapshot, query: &str) -> Vec<u32> {
    let rows = snap.idols.iter().map(|d| (d.id.as_str(), [Some(d.name.as_str()), d.name_kana.as_deref()]));
    strongest_first(&FoldedNeedle::new(query), &snap.idol_search, rows)
}

/// イベントの横断検索 (name / name_kana の部分一致、先頭 20 件)。
///
/// 漢字のライブ名は読みが無いとかなで引けない。曲・アイドルと同じ扱いに揃える。
pub fn searched_event_indexes(snap: &Snapshot, query: &str) -> Vec<u32> {
    let rows = snap.events.iter().map(|e| (e.id.as_str(), [Some(e.name.as_str()), e.name_kana.as_deref()]));
    strongest_first(&FoldedNeedle::new(query), &snap.event_search, rows)
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
    use crate::test_support::{bundle_conn, bundle_snapshot};

    /// Swift `String.likeEscaped` の写経 (テスト側で元 SQL のバインド値を組むのに使う)。
    fn like_escaped(s: &str) -> String {
        s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    /// カタカナをひらがなに寄せる (読みの列はひらがなで入っている)。並べ方の基準を
    /// SQL で書くためだけのもので、畳み込みの実体 (`FoldedNeedle`) とは独立に書いてある。
    fn hiragana(text: &str) -> String {
        text.chars()
            .map(|c| match c {
                'ァ'..='ヶ' => char::from_u32(c as u32 - 0x60).unwrap_or(c),
                _ => c,
            })
            .collect()
    }

    /// GRDB 生成 SQL の写経に、並べ方 (当たり方の強い順・同じ強さは id 順) を足して
    /// rusqlite で直接実行した id 列 (これが等価性の基準)。順序も含めて比較する。
    /// 強さは LIKE で書く: 完全一致 = `LIKE 'q'`、前方一致 = `LIKE 'q%'` を、検索語そのものと
    /// ひらがなに寄せた語の両方で見る (読みの列はひらがなだが、検索語はカタカナで来うる)。
    fn run_original_sql(table: &str, kana_col: Option<&str>, query: &str) -> Vec<String> {
        let name_col = if table == "songs" { "title" } else { "name" };
        let like = |params: &[&str]| {
            let cols: Vec<&str> = std::iter::once(name_col).chain(kana_col).collect();
            let terms: Vec<String> = cols
                .iter()
                .flat_map(|col| params.iter().map(move |p| format!("{col} LIKE {p} ESCAPE '\\'")))
                .collect();
            format!("({})", terms.join(" OR "))
        };
        let sql = format!(
            "SELECT t.* FROM {table} t WHERE {} \
             ORDER BY CASE WHEN {} THEN 0 WHEN {} THEN 1 ELSE 2 END, t.id LIMIT 20",
            like(&["?1"]),
            like(&["?2", "?3"]),
            like(&["?4", "?5"])
        );
        let escaped = like_escaped(query);
        let folded = like_escaped(&hiragana(query));
        let owned = [
            format!("%{escaped}%"),
            escaped.clone(),
            folded.clone(),
            format!("{escaped}%"),
            format!("{folded}%"),
        ];
        let params: Vec<&str> = owned.iter().map(String::as_str).collect();
        let db = bundle_conn();
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
        searched_song_indexes(bundle_snapshot(), q)
            .into_iter()
            .map(|i| bundle_snapshot().songs[i as usize].id.clone())
            .collect()
    }
    fn idol_ids(q: &str) -> Vec<String> {
        searched_idol_indexes(bundle_snapshot(), q)
            .into_iter()
            .map(|i| bundle_snapshot().idols[i as usize].id.clone())
            .collect()
    }
    fn event_ids(q: &str) -> Vec<String> {
        searched_event_indexes(bundle_snapshot(), q)
            .into_iter()
            .map(|i| bundle_snapshot().events[i as usize].id.clone())
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

    /// LIKE の ASCII 大小無視: "ready" と "READY" は同一結果で、大小混在の題名が当たる。
    #[test]
    fn ascii_case_is_ignored_like_sql() {
        assert_all_kinds_match_sql("ready");
        assert_all_kinds_match_sql("READY");
        let lower = song_ids("ready");
        assert_eq!(lower, song_ids("READY"));
        // 当たった題名が問い合わせと違う大小で書かれていること。
        // (問い合わせと同じ綴りの題名しか当たっていないなら、大小を無視した証明にならない)
        //
        // 「READY と Ready の両方が居ること」を見ていた頃は、`Ready Steady`
        // (配信で歌われたカバー) が消えた日に落ちた。実在する題名の顔ぶれに
        // 依存しない形にしてある。
        let titles: Vec<&str> = lower
            .iter()
            .map(|id| bundle_snapshot().songs[bundle_snapshot().song_index_by_id[id] as usize].title.as_str())
            .collect();
        assert!(!titles.is_empty(), "ready が 1 件も当たらない");
        assert!(titles.iter().all(|t| !t.contains("ready")), "{titles:?}");
    }

    /// LIMIT 20 の頭切り: 全件が 20 を超える検索語で「先頭 20 件 (強い順・id 順)」が一致する。
    /// 空文字クエリ (LIKE '%%') は全行一致 = 各テーブル先頭 20 件になるのも元 SQL と同じ。
    #[test]
    fn limit_caps_at_20_like_sql() {
        let db = bundle_conn();
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
            .map(|id| bundle_snapshot().idols[bundle_snapshot().idol_index_by_id[id] as usize].name.as_str())
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
            let c = search_counts(bundle_snapshot(), q);
            let needle = FoldedNeedle::new(q);
            let songs = bundle_snapshot().song_search.iter().filter(|i| i.matches(needle.as_bytes())).count();
            let idols = bundle_snapshot().idol_search.iter().filter(|i| i.matches(needle.as_bytes())).count();
            let events = bundle_snapshot().event_search.iter().filter(|i| i.matches(needle.as_bytes())).count();
            assert_eq!((c.songs as usize, c.idols as usize, c.events as usize),
                       (songs, idols, events), "query={q:?}");
        }
    }

    /// 打ち切らない。`global_search` は各 20 件で切るが、件数は実数を返す。
    #[test]
    fn counts_are_not_capped_unlike_global_search() {
        // 実データで 20 件を超える語を選ぶ (超えないなら検証として退化する)。
        let c = search_counts(bundle_snapshot(), "の");
        assert!(c.songs > 20, "曲 {} 件", c.songs);
        assert_eq!(global_search(bundle_snapshot(), "の").song_ids.len(), 20, "横断検索は 20 件で切る");
    }

    /// 「今後」と「開催済み」を足すと、ライブの当たり総数に一致する。
    ///
    /// 一致しないなら、どちらにも入らない (= 飛んだ先で見えない) ライブがいる。
    /// 日付不明は今後側にのみ残る規則なので、取りこぼしはここで捕まる。
    #[test]
    fn event_sides_add_up_to_the_total_hits() {
        for q in ["ready", "武道館", "ライブ", "M@STER"] {
            let sides = event_search_sides(bundle_snapshot(), q, "2026-09-01");
            let total = search_counts(bundle_snapshot(), q).events;
            assert_eq!(sides.upcoming + sides.past, total, "query={q:?}");
        }
    }

    /// 境界日ちょうどは「今後」側 (`group_events_by_year` の規則をそのまま使う)。
    /// ここを自前で書き直すと、両 OS で日付の切り方がずれる。
    #[test]
    fn the_boundary_day_counts_as_upcoming() {
        // 実データから公演日を 1 つ取り、その日を「今日」として数える。
        let date = bundle_snapshot()
            .shows
            .iter()
            .map(|s| s.date.clone())
            .find(|d| d.len() == 10)
            .expect("フル日付の公演がある前提");
        let event = bundle_snapshot()
            .events
            .iter()
            .enumerate()
            .find(|(i, _)| first_show_date(bundle_snapshot(), *i as u32).as_deref() == Some(date.as_str()))
            .map(|(_, e)| e.name.clone())
            .expect("その日を初日とするライブがある前提");
        let sides = event_search_sides(bundle_snapshot(), &event, &date);
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
        let snap = bundle_snapshot();
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
            let hits = global_search(bundle_snapshot(), q);
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
