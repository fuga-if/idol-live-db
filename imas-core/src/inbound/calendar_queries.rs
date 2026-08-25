//! カレンダーのスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `AppDatabase+CalendarQueries` (= `CalendarReading` ポートの全実装)。
//! ここは domain::calendar_queries への委譲だけ。
//!
//! FFI 形状の規約 (song_list_queries.rs と同じ):
//! - 1 ユーザー操作 (= カレンダー月送り) = 1 呼び出し。6 系統 (公演 / リリース /
//!   誕生日 / スタッフ誕生日 / 記念日 / チケット) を整列済みの 1 本の列で返す。
//! - 公演・チケットは表示に必要な射影を JOIN 済みで持つ (プラットフォーム側の再クエリ不要)。
//!   リリース曲・誕生日・記念日は id で返し、実体化はプラットフォーム側が自国の store で行う。
//! - 範囲は JST の日付文字列 (YYYY-MM-DD)・両端含む。iOS の `DateInterval` からの変換は
//!   アダプタが従来どおり JST の DateFormatter で行う (`calendarDateFormatter` 相当)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::calendar_queries::{self as queries, CalendarEntryRecord};

#[uniffi::export]
impl SnapshotStore {
    /// 表示範囲 [start_day, end_day] (JST 日付・両端含む) の全カレンダーエントリ。
    /// SQL 時代の `fetchCalendarEntriesAsync(in:)` = `calendarEntries(in:)` 相当。
    /// 並びは Swift `assembleCalendarEntries` と同じ (ソート日付, カテゴリ順位) の安定ソート。
    pub fn calendar_entries(
        &self,
        start_day: String,
        end_day: String,
    ) -> Result<Vec<CalendarEntryRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::calendar_entries(&snap, &start_day, &end_day))
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
        assert!(matches!(
            store.calendar_entries("2026-04-01".into(), "2026-04-30".into()),
            Err(SnapshotError::NotLoaded)
        ));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        let entries = store
            .calendar_entries("2026-04-01".into(), "2026-05-31".into())
            .unwrap();
        assert!(!entries.is_empty());
        assert!(entries.iter().any(|e| matches!(e, CalendarEntryRecord::Show { .. })));
        assert!(entries.iter().any(|e| matches!(e, CalendarEntryRecord::Birthday { .. })));
    }
}
