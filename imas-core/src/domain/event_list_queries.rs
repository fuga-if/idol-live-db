//! イベント一覧のクエリ群 (SQL 時代の一覧系を Snapshot 上の純粋関数へ移送)。
//!
//! SQL 時代の対応 (iOS AppDatabase+EventQueries.swift / +StatsQueries.swift):
//! - [`event_records_by_brand`]     ← fetchEvents(brandId:) (GRDB `Event.all()` + brand 絞り)
//! - [`events_with_first_date`]     ← fetchEventsWithFirstDateQuery (一覧・年度グルーピングの元データ)
//! - [`events_with_date_by_year`]   ← eventsWithDateByYearQuery (EventFilterCriterion.year)
//! - [`events_with_date_by_ids`]    ← fetchEventsByIdsQuery (お気に入り一覧など)
//! - [`attended_events_with_date`]  ← fetchAttendedEventsWithDateQuery (参加ライブ一覧)
//! - [`attended_event_type_sets`]   ← fetchAttendedEventTypeSetsQuery (現地/配信/LV フィルタ)
//! - [`event_names`]                ← fetchEventNamesQuery (フィルタ補完用の名前一覧)
//! - [`search_events_by_name_or_venue`] ← searchEventsByNameOrVenueQuery (検索スコープ「ライブ」)
//!
//! SQL の暗黙挙動をコードで明示して固定する (等価性はテストの照合で保証):
//! - `ORDER BY COALESCE(MIN(s.date), '') DESC`: 公演なしイベントは '' 扱いで末尾。
//!   date は非 NULL の 'YYYY-MM-DD' なので &str 比較 (バイト列 = BINARY 照合) で一致する。
//! - `MIN(s.date)` / `MAX(s.date)` は shows_by_event が (date ASC, sort_order ASC) で
//!   前計算済みなので先頭/末尾要素の date。LEFT JOIN で公演 0 件でも行は残る (= None)。
//! - `strftime('%Y', d)` は妥当な日付形式でなければ NULL (= 年フィルタ不一致)。
//!   [`strftime_year`] に判定を固定した。
//! - `IN (...)` は重複 id 1 回・未知 id 無視。結果順は SQL では未規定 → ORDER BY キーの
//!   同値区間は添字 (= rowid 読み込み順) で決定化 (プラットフォーム間で同一結果を返す)。
//!
//! **user_marks はスナップショットに無い** (書き込みが頻繁でプラットフォームが正)。
//! 参加系は「attended マーク済みの event/show id (bool_value=1 で解決済み)」を引数で
//! 受け取る。show 単位マーク → 所属イベントへの展開は shows がマスタデータなので
//! こちらの仕事 (Phase 2 collected_counts_by_song と同じ分担)。
//!
//! 注意: スナップショットは FK 孤児の show をロード時に読み飛ばす。孤児 show への
//! マークは SQL では「存在しないイベント id」を返し得たが、ここでは無視される
//! (孤児は UI に出ないのでマークされ得ない。スナップショット全体の既定挙動)。

use crate::domain::snapshot::{Event, Snapshot};
use std::collections::HashSet;
use crate::domain::text_search_index::FoldedNeedle;

// =============================================================================
// FFI 射影 Record (uniffi は型 derive のみ / ロジックはこのファイルの関数側)
// =============================================================================

/// events 1 行の射影。一覧・詳細とも行の全カラムを使い得るため全域射影
/// (GRDB `Event` / Room Entity と同じ「Record = Entity 兼用」の現実的判断)。
///
/// SQL 時代の一覧クエリは 7 カラムだけ SELECT し残りを nil にしていたが、それは
/// 射影の省略であって仕様ではない (チケット情報等が nil でも一覧 UI は参照しない)。
/// スナップショットは全カラムを持っているので、欠損のない行を返す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventListRecord {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub event_type: String,
    /// 互換のため残置 (iOS Event と同じ注記)。新コードからは参照しない。
    pub is_streaming: bool,
    /// 互換のため残置。新コードからは参照しない。
    pub is_solo: bool,
    pub kind: String,
    pub ticket_open_date: Option<String>,
    pub ticket_deadline: Option<String>,
    pub ticket_lottery_date: Option<String>,
    pub ticket_url: Option<String>,
    pub joint_brand_ids: Option<String>,
    /// Documents 専用列。ローダが列の有無を動的検出済み (無い DB では None)。
    pub has_streaming: Option<bool>,
    /// Documents 専用列。同上。
    pub has_live_viewing: Option<bool>,
}

impl From<&Event> for EventListRecord {
    fn from(e: &Event) -> Self {
        Self {
            id: e.id.clone(),
            brand_id: e.brand_id.clone(),
            name: e.name.clone(),
            event_type: e.event_type.clone(),
            is_streaming: e.is_streaming,
            is_solo: e.is_solo,
            kind: e.kind.clone(),
            ticket_open_date: e.ticket_open_date.clone(),
            ticket_deadline: e.ticket_deadline.clone(),
            ticket_lottery_date: e.ticket_lottery_date.clone(),
            ticket_url: e.ticket_url.clone(),
            joint_brand_ids: e.joint_brand_ids.clone(),
            has_streaming: e.has_streaming,
            has_live_viewing: e.has_live_viewing,
        }
    }
}

/// 開催日付きイベント 1 行 (iOS `EventWithDate`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventWithDateRecord {
    pub event: EventListRecord,
    /// 最初の公演日 (MIN(shows.date))。公演なしイベントは None。
    pub first_date: Option<String>,
    /// 最後の公演日 (MAX(shows.date))。年フィルタ経路 (SQL が SELECT していなかった)
    /// では None のまま — 表示の "first〜last" レンジが出ない現行挙動を維持する。
    pub last_date: Option<String>,
}

/// 参加マーク 1 件の射影 (プラットフォームが user_marks から解決して渡す)。
/// `attendance_type` は user_marks.text_value ("live"/"stream"/"live_viewing"/NULL)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct AttendanceMarkRecord {
    pub entity_id: String,
    pub attendance_type: Option<String>,
}

/// 参加イベントの現地/配信/LV 分類 (iOS fetchAttendedEventTypeSets のタプル対応)。
/// FFI に Set は無いので Vec で返す。中身は重複なし・id 昇順 (決定性のため)。
///
/// Android 側 `AttendedEventTypeSets` (UserMarkRepository.kt) と名前衝突しないよう
/// Record 接尾辞を付けている (生成バインディングがアプリと同居するため)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct AttendedEventTypeSetsRecord {
    pub live: Vec<String>,
    pub stream: Vec<String>,
    pub live_viewing: Vec<String>,
}

// =============================================================================
// 共通ヘルパ
// =============================================================================

/// イベントの最初/最後の公演日。shows_by_event は (date ASC, sort_order ASC) で
/// 前計算済みなので、先頭 = MIN(date) / 末尾 = MAX(date) (date は非 NULL)。
fn first_last_dates(snap: &Snapshot, event: u32) -> (Option<&str>, Option<&str>) {
    let shows = &snap.shows_by_event[event as usize];
    let date = |&s: &u32| snap.shows[s as usize].date.as_str();
    (shows.first().map(date), shows.last().map(date))
}

/// `ORDER BY COALESCE(MIN(s.date), '') DESC` の明示実装。
/// '' は全日付より小さいので、公演なしイベントは降順の末尾に落ちる。
/// SQL が未規定だった同日 (同値キー) の並びは添字 (= rowid 順) で決定化。
fn sort_by_first_date_desc(snap: &Snapshot, mut indexes: Vec<u32>) -> Vec<u32> {
    indexes.sort_by(|&l, &r| {
        let key = |e: u32| first_last_dates(snap, e).0.unwrap_or("");
        key(r).cmp(key(l)).then(l.cmp(&r))
    });
    indexes
}

/// 添字列 → EventWithDateRecord 列。`include_last_date` は年フィルタ経路の
/// 「last_date を SELECT しない」挙動を落とさないためのスイッチ。
fn with_date_records(snap: &Snapshot, indexes: &[u32], include_last_date: bool) -> Vec<EventWithDateRecord> {
    indexes
        .iter()
        .map(|&e| {
            let (first, last) = first_last_dates(snap, e);
            EventWithDateRecord {
                event: EventListRecord::from(&snap.events[e as usize]),
                first_date: first.map(str::to_owned),
                last_date: if include_last_date { last.map(str::to_owned) } else { None },
            }
        })
        .collect()
}

/// SQLite `strftime('%Y', d)` の年抽出の明示実装。
///
/// - 受理するのは 'YYYY-MM-DD' (月 01-12・日 01-31)。範囲内なら日超過
///   ('2015-04-31' 等) も月内正規化で年は変わらないため先頭 4 桁を返す。
/// - 月/日が範囲外・桁違い ('2015-4-1')・空文字は SQLite が NULL を返すので None。
/// - shows.date はローダが String で読む非 NULL 'YYYY-MM-DD' なので、時刻付き等の
///   長い形式は考慮しない (10 文字固定)。等価性は実 DB 照合テストで保証。
fn strftime_year(date: &str) -> Option<&str> {
    let b = date.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let digits = |r: std::ops::Range<usize>| b[r].iter().all(u8::is_ascii_digit);
    if !digits(0..4) || !digits(5..7) || !digits(8..10) {
        return None;
    }
    let two = |i: usize| (b[i] - b'0') * 10 + (b[i + 1] - b'0');
    let (month, day) = (two(5), two(8));
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    Some(&date[..4])
}

/// 「中身がある」イベント判定 (iOS `hasSetlistCondition` = EXISTS shows)。
/// 未来公演 (shows 登録済み・setlist 未入力) も中身ありとして残す既存仕様。
fn has_shows(snap: &Snapshot, event: u32) -> bool {
    !snap.shows_by_event[event as usize].is_empty()
}

// =============================================================================
// クエリ本体
// =============================================================================

/// ブランド絞り込み (None で全件) のイベント一覧 (iOS fetchEvents(brandId:))。
/// 元 SQL は ORDER BY なし → スナップショット順 (= rowid 読み込み順) をそのまま返す。
/// `brand_id = ?` は NULL ブランドと一致しない (SQL の = と同じ)。
pub fn event_records_by_brand(snap: &Snapshot, brand_id: Option<&str>) -> Vec<EventListRecord> {
    snap.events
        .iter()
        .filter(|e| brand_id.is_none_or(|b| e.brand_id.as_deref() == Some(b)))
        .map(EventListRecord::from)
        .collect()
}

/// ライブ名 または 公演会場 の部分一致検索 (検索画面のスコープ「ライブ」)。
/// iOS `AppDatabase.searchEventsByNameOrVenueQuery` 相当:
///
/// ```sql
/// SELECT DISTINCT e.* FROM events e
/// LEFT JOIN shows sh ON sh.event_id = e.id
///  WHERE LOWER(e.name) LIKE ? ESCAPE '\'
///     OR LOWER(IFNULL(sh.venue, '')) LIKE ? ESCAPE '\'
///  LIMIT ?
/// ```
/// バインド値は `%<likeEscaped(query.lowercased())>%`。
///
/// 写すべき非自明な点:
/// - **結果は id 昇順 (BINARY)**。ORDER BY は無いが、DISTINCT を満たすために
///   SQLite が events を PK 索引 (`sqlite_autoindex_events_1`) で走査するため
///   (EXPLAIN QUERY PLAN と実測で確認)。rowid 順ではない。`LIMIT` はこの並びの
///   先頭を取るので、順序を間違えると**返るイベントの集合そのものが変わる**。
/// - 検索語の小文字化は **Swift の `lowercased()`** (Unicode 全域)、列側の `LOWER()` は
///   **SQLite の ASCII 限定**。この非対称は出荷済みの挙動で、非 ASCII の大文字を
///   打つと当たらなくなる。両側を Unicode 小文字化に「揃える」と当たり方が広がるので
///   等価移送の範囲では直さない。`char::to_lowercase` を使うのは Swift と同じ
///   無条件写像にするため (`str::to_lowercase` は語末 Σ→ς の文脈規則を持ち込む。
///   `text_search_index::fold_lowercase` の注記と同じ理由)。
/// - 列側は ASCII 小文字化 + LIKE の ASCII 大小無視なので、`LOWER(e.name) LIKE p` は
///   「name を ASCII 小文字化した文字列が p を含む」と等価。
/// - `IFNULL(sh.venue,'')` と LEFT JOIN の未一致行 (公演なしイベント) は空文字扱い。
///   空文字が LIKE に当たるのは検索語が空のときだけで、そのときは `LOWER(e.name)` 側が
///   全件に当たっているので、実質的な差は出ない。挙動としてはそのまま写す。
/// - 会場は同一イベントの複数公演にまたがるので、どれか 1 公演でも当たれば採用
///   (元 SQL の JOIN + DISTINCT がそうなっている)。
pub fn search_events_by_name_or_venue(
    snap: &Snapshot,
    query: &str,
    limit: u32,
) -> Vec<EventListRecord> {
    // 検索語はここで 1 回だけ畳む。当たり方は一覧の索引 (`TextSearchCatalog`) と
    // 同じ規則 — 大文字小文字に加えて ひらがな↔カタカナも畳む。
    let needle = FoldedNeedle::new(query);

    let mut indexes: Vec<u32> = (0..snap.events.len() as u32)
        .filter(|&i| {
            // 全行を舐めるので、読み込み時に畳んだ索引と突き合わせる。
            if snap.event_search[i as usize].matches(needle.as_bytes()) {
                return true;
            }
            let shows = &snap.shows_by_event[i as usize];
            if shows.is_empty() {
                // LEFT JOIN の未一致行: sh.venue が NULL → IFNULL で '' になる。
                return needle.matches("");
            }
            shows.iter().any(|&s| {
                let show = &snap.shows[s as usize];
                if snap.show_venue_search[s as usize].matches(needle.as_bytes()) {
                    return true;
                }
                // `shows.venue` は表示用の生文字列で、読みも改名前の名前も入っていない。
                // ここだけ見ていると「よこはまありーな」でも「横浜アリーナ」の旧名でも
                // 引けない (漢字の会場は 175 件ある)。会場マスタ側の読み・別名も当てる。
                venue_spellings_hit(snap, show.venue_id.as_deref(), &needle)
            })
        })
        .collect();
    // DISTINCT を満たす PK 索引走査の順 = id 昇順 (id は一意なのでタイは無い)。
    indexes.sort_by(|&a, &b| snap.events[a as usize].id.cmp(&snap.events[b as usize].id));
    indexes.truncate(limit as usize);
    indexes.into_iter().map(|i| EventListRecord::from(&snap.events[i as usize])).collect()
}

/// 会場マスタ側の綴り (現行名・読み・別名) に当たるか。
///
/// 公演に `venue_id` が無い (会場を特定できていない古い公演) 場合は false。
/// そこは `shows.venue` の生文字列でしか引けないが、それが仕様どおり
/// (会場マスタに無いものの読みは持ちようがない)。
fn venue_spellings_hit(snap: &Snapshot, venue_id: Option<&str>, needle: &FoldedNeedle) -> bool {
    // 綴り (現行名・読み・別名の各行) は読み込み時に畳んである。
    let Some(index) = venue_id.and_then(|id| snap.venue_index_by_id.get(id)) else { return false };
    snap.venue_search[*index as usize].matches(needle.as_bytes())
}

/// イベント一覧 (最初/最後の公演日付き、最初の公演日の降順)。
/// iOS fetchEventsWithFirstDateQuery の移送。
///
/// - kind フィルタ: `kinds` 明示指定 > `live_only` > 既定 (live+festival)。
///   Swift 側は nil / 非空しか渡さない (空配列は SQL の `IN ()` が構文エラーになるため
///   存在しない入力) — ここでは空集合 = 全滅として安全側に倒す。
/// - `include_empty`: false なら公演なしイベントを落とす (EXISTS shows)。
pub fn events_with_first_date(
    snap: &Snapshot,
    brand_id: Option<&str>,
    include_empty: bool,
    live_only: bool,
    kinds: Option<&[String]>,
) -> Vec<EventWithDateRecord> {
    let target_kinds: HashSet<&str> = match kinds {
        Some(ks) => ks.iter().map(String::as_str).collect(),
        None if live_only => HashSet::from(["live"]),
        None => HashSet::from(["live", "festival"]),
    };
    let indexes = (0..snap.events.len() as u32)
        .filter(|&i| {
            let e = &snap.events[i as usize];
            target_kinds.contains(e.kind.as_str())
                && brand_id.is_none_or(|b| e.brand_id.as_deref() == Some(b))
                && (include_empty || has_shows(snap, i))
        })
        .collect();
    with_date_records(snap, &sort_by_first_date_desc(snap, indexes), true)
}

/// 開催年で絞ったイベント一覧 (iOS eventsWithDateByYearQuery / EventFilterCriterion.year)。
///
/// kind は live+festival 固定。`HAVING strftime('%Y', first_date) = ?` の移送なので
/// 公演なし (first_date NULL) は年不一致で常に落ちる (include_empty=false の EXISTS は
/// 元 SQL 同様に冗長だが挙動は同じ)。last_date は元 SQL が SELECT していないため None。
pub fn events_with_date_by_year(snap: &Snapshot, year: i32, include_empty: bool) -> Vec<EventWithDateRecord> {
    let year_str = year.to_string();
    let indexes = (0..snap.events.len() as u32)
        .filter(|&i| {
            let e = &snap.events[i as usize];
            if e.kind != "live" && e.kind != "festival" {
                return false;
            }
            if !include_empty && !has_shows(snap, i) {
                return false;
            }
            first_last_dates(snap, i)
                .0
                .and_then(strftime_year)
                .is_some_and(|y| y == year_str)
        })
        .collect();
    with_date_records(snap, &sort_by_first_date_desc(snap, indexes), false)
}

/// id 集合の重複排除 → イベント添字集合 (未知 id は無視 = SQL の `IN` と同じ)。
fn event_indexes_of_ids(snap: &Snapshot, ids: &[String]) -> HashSet<u32> {
    ids.iter()
        .filter_map(|id| snap.event_index_by_id.get(id).copied())
        .collect()
}

/// 指定 event_id 集合の日付つきイベント (iOS fetchEventsByIdsQuery。お気に入り一覧用)。
/// 最初の公演日の降順。空入力は空を返す (SQL 実行前の guard と同じ)。
pub fn events_with_date_by_ids(snap: &Snapshot, ids: &[String]) -> Vec<EventWithDateRecord> {
    let indexes = event_indexes_of_ids(snap, ids).into_iter().collect();
    with_date_records(snap, &sort_by_first_date_desc(snap, indexes), true)
}

/// 参加したイベントの日付つき一覧 (iOS fetchAttendedEventsWithDateQuery)。
///
/// 引数は attended マーク (bool_value=1, kind='attended') を**解決済み**の entity_id 列:
/// - `attended_event_ids`: event 単位マーク。マスタに無い id は落ちる
///   (元 SQL も外側の `WHERE e.id IN` で存在イベントに絞られる)。
/// - `attended_show_ids`: show 単位マーク。所属イベントへの展開 (元 SQL の
///   `JOIN shows` 相当) はマスタデータの仕事なのでここで行う。
///
/// event マークだけ見ると show 単位で付けるユーザーの参加を取りこぼすため
/// UNION する、という元クエリの意図をそのまま保つ。
pub fn attended_events_with_date(
    snap: &Snapshot,
    attended_event_ids: &[String],
    attended_show_ids: &[String],
) -> Vec<EventWithDateRecord> {
    let mut events = event_indexes_of_ids(snap, attended_event_ids);
    events.extend(
        attended_show_ids
            .iter()
            .filter_map(|id| snap.show_index_by_id.get(id))
            .map(|&s| snap.shows[s as usize].event),
    );
    let indexes = events.into_iter().collect();
    with_date_records(snap, &sort_by_first_date_desc(snap, indexes), true)
}

/// 参加イベントを現地/配信/LV の 3 集合に分類 (iOS fetchAttendedEventTypeSetsQuery)。
/// 1 イベント内で種別が混在すれば複数集合に入る。
///
/// 引数は attended マーク (bool_value=1, kind='attended') の解決済み射影:
/// - `event_marks`: event 単位。元 SQL は events と JOIN しないので、マスタに無い
///   id もそのまま集合に入る (忠実に再現)。
/// - `show_marks`: show 単位。所属イベント id へ展開する (未知 show は JOIN 不成立で無視)。
///
/// 種別は "stream" → 配信、"live_viewing" → LV、それ以外 ("live"・NULL の旧データ・
/// 未知値) → 現地 (元実装の default 分岐と同じ)。
pub fn attended_event_type_sets(
    snap: &Snapshot,
    event_marks: &[AttendanceMarkRecord],
    show_marks: &[AttendanceMarkRecord],
) -> AttendedEventTypeSetsRecord {
    let mut live: HashSet<String> = HashSet::new();
    let mut stream: HashSet<String> = HashSet::new();
    let mut live_viewing: HashSet<String> = HashSet::new();

    let mut classify = |event_id: &str, attendance_type: Option<&str>| {
        let set = match attendance_type {
            Some("stream") => &mut stream,
            Some("live_viewing") => &mut live_viewing,
            _ => &mut live,
        };
        set.insert(event_id.to_owned());
    };

    for mark in event_marks {
        classify(&mark.entity_id, mark.attendance_type.as_deref());
    }
    for mark in show_marks {
        if let Some(&s) = snap.show_index_by_id.get(&mark.entity_id) {
            let event_id = &snap.events[snap.shows[s as usize].event as usize].id;
            classify(event_id, mark.attendance_type.as_deref());
        }
    }

    // Set 相当だが FFI は Vec で返すため、id 昇順で決定化する (Swift/Kotlin 側は
    // Set に戻すので順序は意味を持たない — 持たないからこそ固定しておく)。
    let sorted = |set: HashSet<String>| {
        let mut v: Vec<String> = set.into_iter().collect();
        v.sort();
        v
    };
    AttendedEventTypeSetsRecord {
        live: sorted(live),
        stream: sorted(stream),
        live_viewing: sorted(live_viewing),
    }
}

/// イベント名一覧 (iOS fetchEventNamesQuery: `SELECT name FROM events ORDER BY name`)。
/// events_by_name_order が (name ASC, 添字) で前計算済みなのでそれを流すだけ。
pub fn event_names(snap: &Snapshot) -> Vec<String> {
    snap.events_by_name_order
        .iter()
        .map(|&e| snap.events[e as usize].name.clone())
        .collect()
}

// =============================================================================
// テスト (Bundle DB との SQL 照合)
// =============================================================================

#[cfg(test)]
mod tests {

    /// 回帰 (2026-08-28): 会場の読みでライブを引けなかった。
    ///
    /// `venues.name_kana` は全 234 件入っているのに、検索は公演の生文字列
    /// `shows.venue` しか見ていなかった。漢字の会場は 175 件あり、
    /// 「よこはまありーな」では 0 件になっていた。
    /// **ここは元 SQL と意図的に振る舞いが違う** (SQL は会場マスタを引かない)。
    #[test]
    fn event_search_matches_the_venue_reading() {
        let by = |q: &str| search_events_by_name_or_venue(snap(), q, 500).len();
        // 会場マスタに読みが入っている会場を 1 つ選ぶ。
        let venue = snap()
            .venues
            .iter()
            .find(|v| {
                v.name_kana.as_deref().is_some_and(|k| !k.is_empty())
                    && v.name.chars().any(|c| ('\u{4E00}'..='\u{9FFF}').contains(&c))
                    && snap().shows.iter().any(|s| s.venue_id.as_deref() == Some(&v.id))
            })
            .expect("読みつきで漢字の会場が 1 つはある");
        let kana = venue.name_kana.as_deref().unwrap();
        let by_kanji = by(&venue.name);
        let by_kana = by(kana);
        assert!(by_kanji > 0, "表記で引けない時点でこのテストは無意味");
        // 直前まで 0 件だったのがここの回帰。
        assert!(by_kana > 0, "会場「{}」の読み「{}」で 1 件も出ない", venue.name, kana);
        // 読みで引ける集合は表記で引ける集合の**部分集合**になる。会場マスタに
        // 紐付いていない公演 (`venue_id` が空で、生文字列にだけ会場名がある) は
        // 読みを持ちようがないため。実データで 幕張メッセ は 130 公演中 6 件がそれ。
        assert!(
            by_kana <= by_kanji,
            "読みの方が多いのはおかしい ({} > {})",
            by_kana,
            by_kanji
        );
    }
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

    /// Swift `String.likeEscaped` の写経。
    fn like_escaped(s: &str) -> String {
        s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    /// 原本 `searchEventsByNameOrVenueQuery` の写経を rusqlite で直接実行し、
    /// 返った id 列を**順序込み**で基準にする (ORDER BY は無いが DISTINCT の
    /// 走査順が LIMIT の効き方を決めるので、順序を落として比べては意味がない)。
    fn run_original_event_search_sql(query: &str, limit: u32) -> Vec<String> {
        // Swift 側は lowercased() してから likeEscaped する。
        let lowered: String = query.chars().flat_map(char::to_lowercase).collect();
        let pattern = format!("%{}%", like_escaped(&lowered));
        let db = conn();
        let mut stmt = db
            .prepare(
                "SELECT DISTINCT e.* FROM events e
                 LEFT JOIN shows sh ON sh.event_id = e.id
                  WHERE LOWER(e.name) LIKE ?1 ESCAPE '\\'
                     OR LOWER(IFNULL(sh.venue, '')) LIKE ?1 ESCAPE '\\'
                  LIMIT ?2",
            )
            .unwrap();
        let rows: Vec<String> = stmt
            .query_map(rusqlite::params![&pattern, limit], |r| r.get::<_, String>("id"))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        rows
    }

    fn searched_event_ids(query: &str, limit: u32) -> Vec<String> {
        search_events_by_name_or_venue(snap(), query, limit)
            .into_iter()
            .map(|e| e.id)
            .collect()
    }

    /// 照合: searchEventsByNameOrVenue。名前だけ当たる語・会場だけ当たる語・
    /// 打ち切りが効く語・空振り・ワイルドカードを元 SQL と突き合わせる。
    ///
    /// **等価ではなく上位集合**。判定を `FoldedNeedle` (一覧の索引と同じ規則) に
    /// 寄せてあり、SQL の LIKE より広く当たる:
    /// - ひらがな↔カタカナを畳む
    /// - 会場マスタの読み・別名 (旧名) にも当てる — 生の `shows.venue` には無い情報
    ///
    /// 消える方向には動かない (打ち切りに達している場合を除く)。並びは元 SQL と同じ
    /// id 昇順であること。
    #[test]
    fn search_events_by_name_or_venue_is_a_superset_of_sql() {
        let queries = [
            "武道館", "ライブ", "M@STER", "SSA", "さいたま", "横浜", "ready", "READY",
            "", "%", "_", "\\", "zzz存在しない検索語",
        ];
        let mut with_hits = 0usize;
        let mut capped = 0usize;
        let mut widened = 0usize;
        for q in queries {
            for limit in [5u32, 100, 200] {
                let want = run_original_event_search_sql(q, limit);
                let got = searched_event_ids(q, limit);
                assert!(
                    got.windows(2).all(|w| w[0] < w[1]),
                    "並びが id 昇順でない: query={q:?} limit={limit}"
                );
                if got.len() < limit as usize {
                    let got_set: HashSet<&String> = got.iter().collect();
                    let missing: Vec<&String> =
                        want.iter().filter(|id| !got_set.contains(id)).collect();
                    assert!(
                        missing.is_empty(),
                        "SQL のヒットが消えている: query={q:?} limit={limit} → {missing:?}"
                    );
                    widened += usize::from(got.len() > want.len());
                }
            }
            let hits = searched_event_ids(q, 200);
            with_hits += usize::from(!hits.is_empty());
            capped += usize::from(searched_event_ids(q, 5).len() == 5);
        }
        assert!(with_hits > 5, "ヒットする検索語のサンプル数 ({with_hits})");
        assert!(capped > 3, "打ち切りが効くサンプル数 ({capped})");
        assert!(widened > 0, "広がった実例が 1 つも無いなら、寄せた意味の検証として退化する");
    }

    /// 会場だけで当たる経路が実在すること (名前には無い語が shows.venue で拾える)。
    /// ここが死ぬと「会場名でライブを探す」用途が黙って消える。
    #[test]
    fn search_events_reaches_the_venue_column() {
        // 名前に含まれないが会場に含まれる語を実データから探す。
        let venue_word = snap()
            .shows
            .iter()
            .filter_map(|s| s.venue.as_deref())
            .find(|v| {
                v.chars().count() >= 3 && !snap().events.iter().any(|e| e.name.contains(*v))
            })
            .expect("名前に出てこない会場名がある前提")
            .to_string();
        let hits = search_events_by_name_or_venue(snap(), &venue_word, 200);
        assert!(!hits.is_empty(), "venue={venue_word:?}");
        assert!(
            hits.iter().all(|e| !e.name.contains(&venue_word)),
            "会場経由でしか当たらない語のはず: {venue_word:?}"
        );
        assert_eq!(
            searched_event_ids(&venue_word, 200),
            run_original_event_search_sql(&venue_word, 200)
        );
    }

    /// 結果は id 昇順 (DISTINCT を満たす PK 索引走査の順)。rowid 順ではない。
    /// LIMIT がこの並びの先頭を取るので、順序を間違えると返る集合ごと変わる。
    #[test]
    fn search_events_are_ordered_by_id_not_by_snapshot_order() {
        let hits = searched_event_ids("ライブ", 200);
        assert!(hits.len() > 20, "検証に足る件数がある前提: {}", hits.len());
        assert!(hits.windows(2).all(|w| w[0] < w[1]), "id 昇順");

        // 添字順 (rowid 順) とは実際に違うこと。
        let in_snapshot_order: Vec<String> = {
            let mut v: Vec<String> = hits.clone();
            v.sort_by_key(|id| snap().event_index_by_id[id]);
            v
        };
        assert_ne!(hits, in_snapshot_order, "id 順と添字順が同じ DB では検証にならない");
    }

    /// (id, first_date, last_date) — with-date 系の照合対象射影。
    type WithDateRow = (String, Option<String>, Option<String>);

    fn with_date_rows(records: &[EventWithDateRecord]) -> Vec<WithDateRow> {
        records
            .iter()
            .map(|r| (r.event.id.clone(), r.first_date.clone(), r.last_date.clone()))
            .collect()
    }

    /// ORDER BY キーが同値の区間を集合として比較する等価判定 (song_list_queries と同じ理由:
    /// SQLite のソータは同値キーの並びが実行計画依存で未規定のため)。
    fn assert_matches_up_to_ties(label: &str, actual: &[WithDateRow], expected: &[WithDateRow]) {
        assert_eq!(actual.len(), expected.len(), "{label}: 件数");
        // ORDER BY キーは COALESCE(first_date, '')。
        let key = |row: &WithDateRow| row.1.clone().unwrap_or_default();
        let mut start = 0;
        while start < expected.len() {
            let k = key(&expected[start]);
            let mut end = start;
            while end < expected.len() && key(&expected[end]) == k {
                end += 1;
            }
            let expected_group: HashSet<&WithDateRow> = expected[start..end].iter().collect();
            let actual_group: HashSet<&WithDateRow> = actual[start..end].iter().collect();
            assert_eq!(actual_group, expected_group, "{label}: キー {k:?} の同順位グループ");
            start = end;
        }
    }

    /// iOS fetchEventsWithFirstDateQuery の SQL 構築の写経 (これが等価性の基準)。
    fn run_original_first_date_sql(
        brand_id: Option<&str>,
        include_empty: bool,
        live_only: bool,
        kinds: Option<&[&str]>,
    ) -> Vec<WithDateRow> {
        let target_kinds: Vec<&str> = match kinds {
            Some(ks) => ks.to_vec(),
            None if live_only => vec!["live"],
            None => vec!["live", "festival"],
        };
        let mut conditions = vec![format!(
            "e.kind IN ({})",
            vec!["?"; target_kinds.len()].join(", ")
        )];
        let mut args: Vec<String> = target_kinds.iter().map(|k| k.to_string()).collect();
        if let Some(b) = brand_id {
            conditions.push("e.brand_id = ?".into());
            args.push(b.into());
        }
        if !include_empty {
            conditions.push(
                "EXISTS (\n    SELECT 1 FROM shows sh\n    WHERE sh.event_id = e.id\n)".into(),
            );
        }
        let sql = format!(
            "SELECT e.id, MIN(s.date) AS first_date, MAX(s.date) AS last_date
             FROM events e
             LEFT JOIN shows s ON s.event_id = e.id
             WHERE {}
             GROUP BY e.id ORDER BY COALESCE(MIN(s.date), '') DESC",
            conditions.join("\nAND ")
        );
        query_with_date_rows(&conn(), &sql, &args)
    }

    fn query_with_date_rows(db: &Connection, sql: &str, args: &[String]) -> Vec<WithDateRow> {
        let mut stmt = db.prepare(sql).expect("元 SQL は妥当");
        let rows = stmt
            .query_map(rusqlite::params_from_iter(args.iter()), |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, Option<String>>(1)?,
                    // 年フィルタ経路は last_date を SELECT しない (2 列だけ返る)。
                    r.get::<_, Option<String>>(2).unwrap_or(None),
                ))
            })
            .expect("元 SQL を実行できる");
        rows.collect::<Result<Vec<_>, _>>().expect("行を読める")
    }

    // ---- 照合テスト (元 SQL との等価性保証) ----

    /// (brand_id, include_empty, live_only, kinds) — first_date 照合のパラメタ組。
    type FirstDateCase = (Option<&'static str>, bool, bool, Option<Vec<&'static str>>);

    #[test]
    fn events_with_first_date_matches_sql() {
        // 既定 (live+festival)・liveOnly・kinds 明示 (Swift enum に無い 'other' を含む
        // 生値も DB には存在する)・ブランド絞り・includeEmpty=false の 5 系統。
        let cases: Vec<FirstDateCase> = vec![
            (None, true, false, None),
            (None, true, true, None),
            (None, true, false, Some(vec!["release_event", "radio", "other"])),
            (Some("ml"), true, false, None),
            (Some("cg"), false, false, None),
        ];
        for (brand, include_empty, live_only, kinds) in cases {
            let label = format!("brand={brand:?} empty={include_empty} liveOnly={live_only} kinds={kinds:?}");
            let expected = run_original_first_date_sql(brand, include_empty, live_only, kinds.as_deref());
            assert!(!expected.is_empty(), "{label}: 基準が空ではテストにならない");
            let owned_kinds: Option<Vec<String>> =
                kinds.map(|ks| ks.iter().map(|k| k.to_string()).collect());
            let actual = events_with_first_date(snap(), brand, include_empty, live_only, owned_kinds.as_deref());
            assert_matches_up_to_ties(&label, &with_date_rows(&actual), &expected);
        }
    }

    #[test]
    fn events_with_date_by_year_matches_sql() {
        for year in [2015, 2023, 2026, 1999] {
            // iOS eventsWithDateByYearQuery の写経 (includeEmpty=false の HAVING 追記込み)。
            for include_empty in [true, false] {
                let mut having = vec!["strftime('%Y', first_date) = ?".to_string()];
                if !include_empty {
                    having.push(
                        "EXISTS (\n    SELECT 1 FROM shows sh\n    WHERE sh.event_id = e.id\n)".into(),
                    );
                }
                let sql = format!(
                    "SELECT e.id, MIN(s.date) AS first_date
                     FROM events e
                     LEFT JOIN shows s ON s.event_id = e.id
                     WHERE e.kind IN ('live', 'festival')
                     GROUP BY e.id
                     HAVING {}
                     ORDER BY COALESCE(MIN(s.date), '') DESC",
                    having.join(" AND ")
                );
                let expected = query_with_date_rows(&conn(), &sql, &[year.to_string()]);
                let actual = events_with_date_by_year(snap(), year, include_empty);
                // last_date は SELECT されないので必ず None (現行挙動の固定)。
                assert!(actual.iter().all(|r| r.last_date.is_none()));
                assert_matches_up_to_ties(
                    &format!("year={year} empty={include_empty}"),
                    &with_date_rows(&actual),
                    &expected,
                );
                if year == 1999 {
                    assert!(expected.is_empty(), "1999 年のライブは無い前提のケース");
                }
            }
        }
    }

    #[test]
    fn events_with_date_by_ids_matches_sql() {
        // 実在 id (先頭/中間/末尾から) + 未知 id + 重複 id。
        let events = &snap().events;
        let mut ids: Vec<String> = [0, events.len() / 2, events.len() - 1, 7, 42]
            .iter()
            .map(|&i| events[i].id.clone())
            .collect();
        ids.push("no_such_event".into());
        ids.push(ids[0].clone()); // 重複は 1 回になる

        let placeholders = vec!["?"; ids.len()].join(", ");
        let sql = format!(
            "SELECT e.id, MIN(s.date) AS first_date, MAX(s.date) AS last_date
             FROM events e
             LEFT JOIN shows s ON s.event_id = e.id
             WHERE e.id IN ({placeholders})
             GROUP BY e.id
             ORDER BY COALESCE(MIN(s.date), '') DESC"
        );
        let expected = query_with_date_rows(&conn(), &sql, &ids);
        assert_eq!(expected.len(), 5, "実在 5 件・未知と重複は増えない");
        let actual = events_with_date_by_ids(snap(), &ids);
        assert_matches_up_to_ties("by_ids", &with_date_rows(&actual), &expected);

        assert!(events_with_date_by_ids(snap(), &[]).is_empty());
    }

    /// 実在の event/show id を使った合成 user_marks を TEMP テーブルに立てる。
    /// TEMP スキーマが main より先に解決されるので、元 SQL を一字一句そのまま実行できる。
    fn setup_marks(db: &Connection) -> (Vec<AttendanceMarkRecord>, Vec<AttendanceMarkRecord>) {
        db.execute_batch(
            "CREATE TEMP TABLE user_marks (
                entity_type TEXT, entity_id TEXT, kind TEXT, bool_value INTEGER, text_value TEXT
             )",
        )
        .expect("TEMP user_marks を作れる");

        let events = &snap().events;
        let shows = &snap().shows;
        // event 単位: 種別なし (旧データ) / stream / bool_value=0 (無効) / マスタに無い id。
        let event_rows: Vec<(String, Option<&str>, i64)> = vec![
            (events[3].id.clone(), None, 1),
            (events[10].id.clone(), Some("stream"), 1),
            (events[20].id.clone(), Some("live"), 0),
            ("ghost_event".into(), Some("live"), 1),
        ];
        // show 単位: live_viewing / live / 未知 show / bool_value=0 (無効マーク)。
        let show_rows: Vec<(String, Option<&str>, i64)> = vec![
            (shows[5].id.clone(), Some("live_viewing"), 1),
            (shows[100].id.clone(), Some("live"), 1),
            ("ghost_show".into(), Some("live"), 1),
            (shows[7].id.clone(), None, 0),
        ];
        let mut insert = db
            .prepare("INSERT INTO user_marks VALUES (?, ?, ?, ?, ?)")
            .expect("INSERT を準備できる");
        for (id, t, b) in &event_rows {
            insert.execute(rusqlite::params!["event", id, "attended", b, t]).unwrap();
        }
        for (id, t, b) in &show_rows {
            insert.execute(rusqlite::params!["show", id, "attended", b, t]).unwrap();
        }
        // 別 kind の行はどのクエリにも拾われないことの検証用。
        insert
            .execute(rusqlite::params!["event", events[30].id, "favorite", 1, Option::<&str>::None])
            .unwrap();

        // プラットフォーム側の解決を模す: bool_value=1 かつ kind='attended' だけを渡す。
        let resolve = |entity: &str| -> Vec<AttendanceMarkRecord> {
            let mut stmt = db
                .prepare("SELECT entity_id, text_value FROM user_marks WHERE entity_type=?1 AND kind='attended' AND bool_value=1")
                .unwrap();
            let rows = stmt
                .query_map([entity], |r| {
                    Ok(AttendanceMarkRecord {
                        entity_id: r.get(0)?,
                        attendance_type: r.get(1)?,
                    })
                })
                .unwrap();
            rows.collect::<Result<Vec<_>, _>>().unwrap()
        };
        (resolve("event"), resolve("show"))
    }

    #[test]
    fn attended_events_with_date_matches_sql() {
        let db = conn();
        let (event_marks, show_marks) = setup_marks(&db);
        // iOS fetchAttendedEventsWithDateQuery の写経 (一字一句)。
        let sql = "SELECT e.id, MIN(s.date) AS first_date, MAX(s.date) AS last_date
            FROM events e
            LEFT JOIN shows s ON s.event_id = e.id
            WHERE e.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
                UNION
                SELECT sh.event_id FROM user_marks um
                JOIN shows sh ON sh.id = um.entity_id
                WHERE um.entity_type = 'show' AND um.kind = 'attended' AND um.bool_value = 1
            )
            GROUP BY e.id
            ORDER BY COALESCE(MIN(s.date), '') DESC";
        let expected = query_with_date_rows(&db, sql, &[]);
        // event 2 件は必ず実在。show 由来の親イベントが偶々重なっても 2 件は下回らない。
        assert!(expected.len() >= 2, "基準が空ではテストにならない (len={})", expected.len());

        let event_ids: Vec<String> = event_marks.iter().map(|m| m.entity_id.clone()).collect();
        let show_ids: Vec<String> = show_marks.iter().map(|m| m.entity_id.clone()).collect();
        let actual = attended_events_with_date(snap(), &event_ids, &show_ids);
        assert_matches_up_to_ties("attended", &with_date_rows(&actual), &expected);
    }

    #[test]
    fn attended_event_type_sets_matches_sql() {
        let db = conn();
        let (event_marks, show_marks) = setup_marks(&db);
        // iOS fetchAttendedEventTypeSetsQuery の写経 (一字一句) + Swift 側分岐の再現。
        let sql = "SELECT event_id, text_value AS atype FROM (
                SELECT entity_id AS event_id, text_value
                FROM user_marks
                WHERE entity_type='event' AND kind='attended' AND bool_value=1
                UNION ALL
                SELECT sh.event_id AS event_id, um.text_value
                FROM user_marks um
                JOIN shows sh ON sh.id = um.entity_id
                WHERE um.entity_type='show' AND um.kind='attended' AND um.bool_value=1
            )";
        let mut stmt = db.prepare(sql).unwrap();
        let rows: Vec<(String, Option<String>)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let (mut live, mut stream, mut lv) = (HashSet::new(), HashSet::new(), HashSet::new());
        for (event_id, atype) in rows {
            match atype.as_deref() {
                Some("stream") => stream.insert(event_id),
                Some("live_viewing") => lv.insert(event_id),
                _ => live.insert(event_id),
            };
        }

        let actual = attended_event_type_sets(snap(), &event_marks, &show_marks);
        let as_set = |v: &[String]| v.iter().cloned().collect::<HashSet<String>>();
        assert_eq!(as_set(&actual.live), live, "現地集合");
        assert_eq!(as_set(&actual.stream), stream, "配信集合");
        assert_eq!(as_set(&actual.live_viewing), lv, "LV 集合");
        // マスタに無い event id も集合に入る (元 SQL は events と JOIN しない)。
        assert!(actual.live.iter().any(|id| id == "ghost_event"));
        // Vec 表現は id 昇順で決定的。
        let mut sorted = actual.live.clone();
        sorted.sort();
        assert_eq!(actual.live, sorted);
    }

    #[test]
    fn event_records_by_brand_matches_sql() {
        let db = conn();
        // GRDB `Event.all()` は SELECT * (ORDER BY なし) = rowid 順の全表走査。
        // covering index に化けないよう e.* を読む。
        let run = |brand: Option<&str>| -> Vec<String> {
            let (sql, args) = match brand {
                Some(b) => ("SELECT e.* FROM events e WHERE e.brand_id = ?".to_string(), vec![b.to_string()]),
                None => ("SELECT e.* FROM events e".to_string(), vec![]),
            };
            let mut stmt = db.prepare(&sql).unwrap();
            let rows = stmt
                .query_map(rusqlite::params_from_iter(args.iter()), |r| r.get::<_, String>("id"))
                .unwrap();
            rows.collect::<Result<_, _>>().unwrap()
        };
        for brand in [None, Some("ml"), Some("sc"), Some("存在しないブランド")] {
            let expected = run(brand);
            let actual: Vec<String> = event_records_by_brand(snap(), brand)
                .into_iter()
                .map(|r| r.id)
                .collect();
            assert_eq!(actual, expected, "brand={brand:?}");
        }
    }

    #[test]
    fn event_names_matches_sql() {
        let db = conn();
        let mut stmt = db.prepare("SELECT name FROM events ORDER BY name").unwrap();
        let expected: Vec<String> = stmt
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        // 同名イベントがあっても値が同じなので列そのものが一致する。
        assert_eq!(event_names(snap()), expected);
        assert!(!expected.is_empty());
    }

    // ---- 純粋ロジックの単体テスト ----

    #[test]
    fn strftime_year_mirrors_sqlite() {
        // SQLite 実測: 04-31 は月内正規化で受理 / 月 00・13、桁違い、空は NULL。
        assert_eq!(strftime_year("2015-04-30"), Some("2015"));
        assert_eq!(strftime_year("2015-04-31"), Some("2015"));
        assert_eq!(strftime_year("2015-00-15"), None);
        assert_eq!(strftime_year("2015-13-01"), None);
        assert_eq!(strftime_year("2015-4-1"), None);
        assert_eq!(strftime_year(""), None);
        assert_eq!(strftime_year("2015"), None);
    }

    #[test]
    fn explicit_empty_kinds_matches_nothing() {
        // Swift からは来ない入力 (SQL では IN () が構文エラー)。空集合として安全側に。
        let empty: Vec<String> = vec![];
        assert!(events_with_first_date(snap(), None, true, false, Some(&empty)).is_empty());
    }
}
