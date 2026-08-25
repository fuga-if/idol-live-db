//! イベント詳細まわりのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `GRDBShowRepository` (ShowReading 全メソッド) と
//! `GRDBEventRepository` のイベント詳細系 (event / eventStats / eventAttendance /
//! eventReleases)。ここは domain::event_detail_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_list_queries.rs と同じ):
//! - 1 ユーザー操作 = 1 呼び出し。行は射影 Record で返し、iOS/Android は自国の型へ
//!   詰め替えるだけにする (SQL もソートも持ち込まない)。
//! - SQL 時代に Set (並び未規定) だった集合は決定的な並びの列で返す。受け側で集合化する。
//! - イベント一覧系 (eventsWithFirstDate / eventNames / eventsByIds / attended 系) は
//!   event_list_queries.rs、ライブ名検索は search_queries.rs が担う (二重 export しない)。
//! - user_marks 依存はここに無い (参加分類はプラットフォーム側の責務のまま)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::event_detail_queries::{
    self as queries, EventAttendanceRecord, EventDetailRecord, EventReleaseRecord,
    EventStatsRecord, SetlistEntryRecord, SetlistPerformerRecord, ShowRecord,
    ShowWithEventNameRecord, VenueDirectoryRecord,
};
use std::collections::HashMap;

#[uniffi::export]
impl SnapshotStore {
    /// イベント配下の公演一覧 (date, sort_order 順)。SQL 時代の fetchShows(eventId:) 相当。
    pub fn shows_by_event(&self, event_id: String) -> Result<Vec<ShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::shows_by_event(&snap, &event_id))
    }

    /// 単一公演。SQL 時代の fetchShow(id:) 相当。
    pub fn show_record(&self, id: String) -> Result<Option<ShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::show_record(&snap, &id))
    }

    /// 直近公演 (日付最大)。SQL 時代の fetchLatestShow 相当。
    pub fn latest_show(&self) -> Result<Option<ShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::latest_show(&snap))
    }

    /// 会場 (venue_id または生の会場文字列) の公演一覧 (新しい順)。
    /// SQL 時代の fetchShows(criterion: .venue) 相当。
    pub fn shows_at_venue(&self, venue: String) -> Result<Vec<ShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::shows_at_venue(&snap, &venue))
    }

    /// 指定日 (YYYY-MM-DD) の公演一覧 (sort_order 順)。
    /// SQL 時代の fetchShows(criterion: .date) 相当。
    pub fn shows_on_date(&self, date: String) -> Result<Vec<ShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::shows_on_date(&snap, &date))
    }

    /// ピッカー初期表示の公演一覧 (イベント名つき・新しい順)。SQL 時代の fetchAllShows 相当。
    pub fn all_shows_with_event_name(
        &self,
        limit: u32,
    ) -> Result<Vec<ShowWithEventNameRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::all_shows_with_event_name(&snap, limit))
    }

    /// ピッカー用の公演検索 (公演名 or イベント名の部分一致・新しい順)。
    /// SQL 時代の searchShows(query:limit:) 相当。
    pub fn search_shows_with_event_name(
        &self,
        query: String,
        limit: u32,
    ) -> Result<Vec<ShowWithEventNameRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::search_shows_with_event_name(&snap, &query, limit))
    }

    /// 公演のセットリスト (position 順・曲情報つき)。SQL 時代の fetchSetlist 相当。
    pub fn show_setlist(&self, show_id: String) -> Result<Vec<SetlistEntryRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::setlist(&snap, &show_id))
    }

    /// セトリ項目 id → 歌唱メンバー行 (N+1 防止の一括取得)。
    /// SQL 時代の fetchAllPerformers(showId:) 相当。
    pub fn show_setlist_performers(
        &self,
        show_id: String,
    ) -> Result<HashMap<String, Vec<SetlistPerformerRecord>>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::setlist_performers_by_item(&snap, &show_id))
    }

    /// 公演の出演キャスト idol_id 列 (sort_order 順)。
    /// SQL 時代の fetchShowIdolIds (Set が欲しい側は受けてから集合化) と
    /// fetchShowCastIdols (実体化はプラットフォーム側の idol 取得 API で) の両方を担う。
    pub fn show_cast_idol_ids(&self, show_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::show_cast_idol_ids(&snap, &show_id))
    }

    /// song_id → 原曲アーティスト (role='original') idol_id 列。
    /// SQL 時代の fetchOriginalArtistIds(songIds:) 相当 (original 無しの曲はキーごと無い)。
    pub fn original_artist_ids_map(
        &self,
        song_ids: Vec<String>,
    ) -> Result<HashMap<String, Vec<String>>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::original_artist_ids_map(&snap, &song_ids))
    }

    /// 指定公演の出演キャストがオリメンの曲 song_id 列。
    /// SQL 時代の fetchOriginalSongIds(forShowCastOf:) 相当。
    pub fn original_song_ids_for_show_cast(
        &self,
        show_id: String,
    ) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::original_song_ids_for_show_cast(&snap, &show_id))
    }

    /// 会場マスタ一式 (施設・改名履歴・ホール)。SQL 時代の fetchVenueDirectory 相当。
    pub fn venue_directory(&self) -> Result<VenueDirectoryRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::venue_directory(&snap))
    }

    /// 指定会場 (venue_id) で公演があったイベント id 列 (受け側で集合化)。
    /// SQL 時代の fetchEventIdsAtVenue 相当。
    pub fn event_ids_at_venue(&self, venue_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_ids_at_venue(&snap, &venue_id))
    }

    /// 検索語に一致した会場を event_id ごとに 1 件返す (検索結果の一致理由表示用)。
    /// SQL 時代の fetchVenuesMatching(query:eventIds:) 相当。
    pub fn venues_matching(
        &self,
        query: String,
        event_ids: Vec<String>,
    ) -> Result<HashMap<String, String>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::venues_matching(&snap, &query, &event_ids))
    }

    /// 単一イベント。SQL 時代の fetchEvent(id:) 相当。
    pub fn event_record(&self, id: String) -> Result<Option<EventDetailRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_record(&snap, &id))
    }

    /// イベント統計 (公演数・のべ曲数・ユニーク曲数・キャスト数)。
    /// SQL 時代の fetchEventStats 相当。
    pub fn event_stats(&self, event_id: String) -> Result<EventStatsRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_stats(&snap, &event_id))
    }

    /// DAY 別出席表 (母集団・公演・出席/lead/guest 集合)。
    /// SQL 時代の fetchEventAttendance 相当 (brand 無し・母集団ゼロは None)。
    pub fn event_attendance(
        &self,
        event_id: String,
    ) -> Result<Option<EventAttendanceRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_attendance(&snap, &event_id))
    }

    /// イベントの映像円盤一覧 (release_date, sort_order 順)。
    /// SQL 時代の fetchEventReleases 相当 (表の無い Bundle DB では常に空)。
    pub fn event_releases(
        &self,
        event_id: String,
    ) -> Result<Vec<EventReleaseRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::event_releases(&snap, &event_id))
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
        assert!(matches!(store.latest_show(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.venue_directory(), Err(SnapshotError::NotLoaded)));
        assert!(matches!(store.event_stats("x".into()), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        let latest = store.latest_show().unwrap().expect("公演は 1 件以上ある");
        let shows = store.shows_by_event(latest.event_id.clone()).unwrap();
        assert!(shows.iter().any(|s| s.id == latest.id));
        assert_eq!(store.show_record(latest.id.clone()).unwrap().map(|s| s.id), Some(latest.id));

        let all = store.all_shows_with_event_name(10).unwrap();
        assert_eq!(all.len(), 10);
        assert!(!store.venue_directory().unwrap().venues.is_empty());

        let stats = store.event_stats(latest.event_id.clone()).unwrap();
        assert!(stats.show_count >= 1);
        assert!(store.event_record(latest.event_id.clone()).unwrap().is_some());
        // Bundle には event_releases 表が無い → 空。
        assert!(store.event_releases(latest.event_id).unwrap().is_empty());
        assert!(store.venues_matching("".into(), vec![]).unwrap().is_empty());
    }
}
