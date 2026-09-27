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
    EventStatsRecord, PerformerDisplayName, PerformerNameMode, PerformerNameOption,
    SetlistEntryRecord, SetlistPerformerRecord, ShowRecord, ShowWithEventNameRecord,
    VenueDirectoryRecord,
};
use crate::domain::setlist_lineup::{self, SetlistLineupNote};
use crate::domain::screen_composition::SetlistDisplayMode;
use crate::domain::collection_gap::{self as collection, AttendanceMarkRecord};
use crate::domain::setlist_row_meta::{setlist_row_meta, SetlistRowMetaBundle};
use crate::domain::setlist_sections;
use std::collections::{BTreeSet, HashMap};

/// セトリの歌唱者をどの名前で出すか。
///
/// **スナップショットを要らない純関数として出す。** 行 (`SetlistPerformerRecord`) は
/// 既に `setlist_performers_by_item` で受け取っているので、表示のたびに
/// スナップショットを引き直す理由がない。
///
/// `is_character_live` は `ShowRecord.performer_type == "character"`。
#[uniffi::export]
pub fn performer_display_name(
    record: SetlistPerformerRecord,
    mode: PerformerNameMode,
    is_character_live: bool,
) -> PerformerDisplayName {
    queries::performer_display_name(&record, mode, is_character_live)
}

/// 回収に数える参加マークを選ぶ (既定は現地のみ・設定で配信も含める)。
///
/// **スナップショットを要らない純関数として出す。** 参加マークはプラットフォームが
/// 持っているので、渡された射影から id 列を作るだけ。規則をアプリ側に書くと
/// iOS / Android / 一覧 / セトリ で 4 つに増える (実際 iOS には 2 つあった)。
#[uniffi::export]
pub fn collection_attended_shows(
    marks: Vec<AttendanceMarkRecord>,
    include_stream: bool,
) -> Vec<String> {
    collection::collection_attended_show_ids(marks, include_stream)
}

/// 回収の対象になる催しの `events.kind`。
///
/// **SQL 経路が IN 句を組むために引く。** 同じ値を Swift / Kotlin のリテラルで持つと、
/// 対象を足したときに片方だけ古いまま残る (回収バッジと「未回収」が食い違う)。
#[uniffi::export]
pub fn collection_real_live_kinds() -> Vec<String> {
    collection::collection_real_live_kinds()
}

/// 催しがリアルライブでも回収に数えない公演の `shows.performer_type` (上映会)。
/// SQL 経路が `COALESCE(sh.performer_type, '') NOT IN (…)` を組むために引く。
#[uniffi::export]
pub fn collection_excluded_performer_types() -> Vec<String> {
    collection::collection_excluded_performer_types()
}

/// 回収に数える参加形態 (`user_marks.text_value`)。**空なら形態を問わない。**
/// SQL 経路が `text_value IS NULL OR text_value IN (…)` を組むために引く。
#[uniffi::export]
pub fn collection_attendance_types(include_stream: bool) -> Vec<String> {
    collection::collection_attendance_types(include_stream)
}

/// 2 段に積めない場所 (簡易表示・共有文) 向けの 1 行表記。
#[uniffi::export]
pub fn performer_display_name_joined(name: PerformerDisplayName) -> String {
    name.joined()
}

/// 設定画面に並べる選択肢一式 (順・保存値・文言)。
///
/// **これを並べるだけにする。** 4 モードのラベルと保存値を各プラットフォームの
/// enum に書き写すと、文言を直したときに 1 面だけ古いまま残る。
#[uniffi::export]
pub fn performer_name_options() -> Vec<PerformerNameOption> {
    queries::performer_name_options()
}

/// 保存値からモードを復元する。未知の値・未設定は既定 (アイドル名)。
#[uniffi::export]
pub fn performer_name_mode_from_raw(raw: Option<String>) -> PerformerNameMode {
    PerformerNameMode::from_raw(raw.as_deref())
}

/// 公演がキャラライブか (`shows.performer_type == "character"`)。
#[uniffi::export]
pub fn is_character_live(performer_type: Option<String>) -> bool {
    queries::is_character_live(performer_type.as_deref())
}

fn id_set(ids: &[String]) -> BTreeSet<&str> {
    ids.iter().map(String::as_str).collect()
}

/// 原唱者 (`song_artists.role = 'original'`、原曲の並び順)・歌唱者・公演の出演者 (`show_cast`)
/// の idol_id から、行に付ける札。付けない行 (判定できない・ソロ曲を本人が歌う・
/// 出演者全員で歌う行の部分一致) は `None`。
///
/// **スナップショットを要らない純関数として出す。** 3 つの集合は既に受け取っている
/// (`original_artist_ids_map` / `setlist_performers_by_item` / `show_cast_idol_ids`)。
#[uniffi::export]
pub fn setlist_lineup(
    original_ids: Vec<String>,
    performer_ids: Vec<String>,
    cast_ids: Vec<String>,
) -> Option<SetlistLineupNote> {
    let original: Vec<&str> = original_ids.iter().map(String::as_str).collect();
    setlist_lineup::row_lineup(&original, &id_set(&performer_ids), &id_set(&cast_ids))
        .summary
        .map(|s| s.note())
}

/// 公演の出演者全員で歌う行なら `全員` の札 (出演者 2 人以上・歌唱者と完全一致)。
#[uniffi::export]
pub fn setlist_full_cast_label(performer_ids: Vec<String>, cast_ids: Vec<String>) -> Option<String> {
    setlist_lineup::is_full_cast(&id_set(&cast_ids), &id_set(&performer_ids))
        .then(|| setlist_lineup::FULL_CAST_LABEL.to_string())
}

/// セトリの区切りの見出し。`encore` / `ENCORE` / `アンコール` は 1 つに畳み、空は区切り無し。
#[uniffi::export]
pub fn setlist_section_label(raw: Option<String>) -> Option<String> {
    setlist_sections::section_label(raw.as_deref())
}

#[uniffi::export]
impl SnapshotStore {
    /// 曲詳細の「現地回収 N 公演」の公演 (新しい順)。参加マークは show 単位・event 単位とも
    /// `collection_attended_shows(marks, include_stream)` を通した id を渡す
    /// (一覧の回収バッジと同じ規則。リアルライブだけに絞るのはこちら)。
    pub fn song_collected_shows(
        &self,
        song_id: String,
        attended_show_ids: Vec<String>,
        attended_event_ids: Vec<String>,
    ) -> Result<Vec<ShowWithEventNameRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(collection::song_collected_shows(&snap, &song_id, &attended_show_ids, &attended_event_ids))
    }

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

    /// セトリ 1 行ぶんの添え物 (名義・ユニットのチップ・全員・何回目・いつぶり・
    /// 自分の回収) と、公演の頭に出す回収の要約。
    /// 行の並びは [`Self::show_setlist`] と同じなので、受け側は zip するだけでよい。
    ///
    /// **名義の決め方 (その披露の名義 → 曲の名義 → 個人名併記 → 顔ぶれ推論 → 名前)
    /// も、「いつぶりか」の言い回しも、「初回収 / 回収 N 回目 / 未回収」の判断もコアが持つ。**
    /// 画面でユニットを逆引きしたり「N 年ぶり」を組み立てたりしないこと
    /// (規則が両 OS に写経される)。
    ///
    /// `attended_*` は参加マーク (`user_marks`) をプラットフォーム側で解決した id 列。
    /// show 側は参加形態の条件を適用済みで渡す ([`collection_attended_shows`])。
    /// 空で渡せば回収の表示は何も出ない。
    pub fn show_setlist_row_meta(
        &self,
        show_id: String,
        mode: PerformerNameMode,
        display_mode: SetlistDisplayMode,
        attended_show_ids: Vec<String>,
        attended_event_ids: Vec<String>,
    ) -> Result<SetlistRowMetaBundle, SnapshotError> {
        let snap = self.current()?;
        Ok(setlist_row_meta(
            &snap,
            &show_id,
            mode,
            display_mode,
            &attended_show_ids,
            &attended_event_ids,
        ))
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
    use crate::test_support::bundle_store;

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = bundle_store();
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
