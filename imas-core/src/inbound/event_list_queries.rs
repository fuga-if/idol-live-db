//! イベント一覧まわりのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `AppDatabase+EventQueries` / `AppDatabase+StatsQueries` の一覧系
//! (`EventReading` ポートの一覧メソッド群)。ここは domain::event_list_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_list_queries.rs と同じ):
//! - 一覧は射影 Record 列で返す (1 ユーザー操作 = 1 呼び出し。EventWithDateRecord は
//!   Event 全カラム + 開催日を内包するので、呼び出し側の再引きは不要)。
//! - **user_marks はスナップショットに無い**。参加系はプラットフォーム側が
//!   「attended マーク済み (bool_value=1) の entity_id (＋種別)」まで解決して渡す。
//!   show 単位マーク → 所属イベントへの展開はマスタデータの仕事なのでこちらで行う。
//! - kind は生文字列で受ける (Swift `EventKind` の rawValue。enum の二重定義を避ける)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::event_list_queries::{
    self as queries, AttendanceMarkRecord, AttendedEventTypeSetsRecord, EventListRecord,
    EventWithDateRecord,
};

#[uniffi::export]
impl SnapshotStore {
    /// ブランド絞り込み (None で全件) のイベント一覧。SQL 時代の fetchEvents(brandId:) 相当
    /// (ORDER BY なし = rowid 順)。
    pub fn event_records(&self, brand_id: Option<String>) -> Result<Vec<EventListRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_records_by_brand(&snap, brand_id.as_deref()))
    }

    /// イベント一覧 (最初/最後の公演日付き、最初の公演日の降順)。
    /// SQL 時代の fetchEventsWithFirstDate 相当。kind フィルタは
    /// `kinds` 明示指定 > `live_only` > 既定 (live+festival)。
    pub fn events_with_first_date(
        &self,
        brand_id: Option<String>,
        include_empty: bool,
        live_only: bool,
        kinds: Option<Vec<String>>,
    ) -> Result<Vec<EventWithDateRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::events_with_first_date(
            &snap,
            brand_id.as_deref(),
            include_empty,
            live_only,
            kinds.as_deref(),
        ))
    }

    /// 開催年で絞ったイベント一覧 (EventFilterCriterion.year)。
    /// SQL 時代の eventsWithDateByYearQuery 相当 (last_date は返らない — 元 SQL の挙動)。
    pub fn events_with_date_by_year(
        &self,
        year: i32,
        include_empty: bool,
    ) -> Result<Vec<EventWithDateRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::events_with_date_by_year(&snap, year, include_empty))
    }

    /// 指定 event_id 集合の日付つきイベント (お気に入り一覧用)。
    /// SQL 時代の fetchEventsByIds 相当 (未知 id 無視・重複 1 回・最初の公演日の降順)。
    pub fn events_with_date_by_ids(
        &self,
        ids: Vec<String>,
    ) -> Result<Vec<EventWithDateRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::events_with_date_by_ids(&snap, &ids))
    }

    /// 参加したイベントの日付つき一覧。SQL 時代の fetchAttendedEventsWithDate 相当。
    /// 引数は attended マークの解決済み entity_id 列 (event 単位 / show 単位)。
    pub fn attended_events_with_date(
        &self,
        attended_event_ids: Vec<String>,
        attended_show_ids: Vec<String>,
    ) -> Result<Vec<EventWithDateRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::attended_events_with_date(
            &snap,
            &attended_event_ids,
            &attended_show_ids,
        ))
    }

    /// 参加イベントの現地/配信/LV 分類。SQL 時代の fetchAttendedEventTypeSets 相当。
    /// 引数は attended マークの解決済み (entity_id, text_value) 射影。
    pub fn attended_event_type_sets(
        &self,
        event_marks: Vec<AttendanceMarkRecord>,
        show_marks: Vec<AttendanceMarkRecord>,
    ) -> Result<AttendedEventTypeSetsRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::attended_event_type_sets(&snap, &event_marks, &show_marks))
    }

    /// イベント名一覧 (フィルタ補完用)。SQL 時代の fetchEventNames 相当 (name 昇順)。
    /// ライブ名 または 公演会場 の部分一致検索 (検索スコープ「ライブ」)。
    /// searchEventsByNameOrVenue(query:limit:) 相当。
    ///
    /// 結果は id 昇順 (元 SQL が DISTINCT のために PK 索引で走査する順) で、
    /// `limit` はその並びの先頭を取る。詳細は
    /// domain::event_list_queries::search_events_by_name_or_venue のコメント。
    pub fn search_events_by_name_or_venue(
        &self,
        query: String,
        limit: u32,
    ) -> Result<Vec<EventListRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::search_events_by_name_or_venue(&snap, &query, limit))
    }

    pub fn event_names(&self) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_names(&snap))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loaded_store() -> std::sync::Arc<SnapshotStore> {
        let store = SnapshotStore::new();
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        store.load(db).expect("bundle DB はロードできる");
        store
    }

    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(store.event_records(None), Err(SnapshotError::NotLoaded)));
        assert!(matches!(
            store.events_with_first_date(None, true, false, None),
            Err(SnapshotError::NotLoaded)
        ));
        assert!(matches!(store.event_names(), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();

        let all = store.event_records(None).unwrap();
        assert!(all.len() > 500, "イベントは数百件返る (len={})", all.len());

        let listed = store.events_with_first_date(None, true, false, None).unwrap();
        assert!(!listed.is_empty());
        assert!(listed.iter().all(|r| {
            let kind = r.event.kind.as_str();
            kind == "live" || kind == "festival"
        }));

        let by_year = store.events_with_date_by_year(2015, true).unwrap();
        assert!(by_year.iter().all(|r| r.last_date.is_none()));

        let some_id = all[0].id.clone();
        let by_ids = store.events_with_date_by_ids(vec![some_id.clone(), "無い".into()]).unwrap();
        assert_eq!(by_ids.len(), 1);

        let attended = store
            .attended_events_with_date(vec![some_id.clone()], vec![])
            .unwrap();
        assert_eq!(attended.len(), 1);

        let sets = store
            .attended_event_type_sets(
                vec![AttendanceMarkRecord { entity_id: some_id.clone(), attendance_type: None }],
                vec![],
            )
            .unwrap();
        assert_eq!(sets.live, vec![some_id]);
        assert!(sets.stream.is_empty() && sets.live_viewing.is_empty());

        let names = store.event_names().unwrap();
        assert_eq!(names.len(), all.len());
    }
}
