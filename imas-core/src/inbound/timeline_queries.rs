//! 年表 (ブランド史) のスナップショットクエリ (FFI 面・impl 分割)。
//!
//! SQL 時代の対応: iOS `AppDatabase+TimelineQueries.fetchTimelineBarsAsync`
//! (= `TimelineReading.timelineBars(brandId:)`)。ここは domain::timeline_queries への
//! 委譲だけ。
//!
//! FFI 形状の規約:
//! - 年表を開く 1 操作 = 1 呼び出し。全レーンの帯 ([`TimelineBarRecord`]) を
//!   milestone → event → series → cdSeries → oneOff の連結順でまとめて返す
//!   (レーンごとの往復呼び出しにしない)。
//! - 日付は JST 0 時の epoch 秒。Phase 1 の timeline_layout (pack_rows /
//!   year_range / x_positions) にそのまま流せる。
//! - イベント帯の `title` は正式名称のまま。表示用省略 (eventDisplayName) は
//!   UserDefaults の設定に依存するため、アダプタが `target == Event` の帯にだけ
//!   適用すること (domain 側 doc 参照)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::timeline_queries::{self as queries, TimelineBarRecord};

#[uniffi::export]
impl SnapshotStore {
    /// 年表の帯を全レーン分まとめて返す。`brand_id` が None なら全ブランド横断。
    /// SQL 時代の fetchTimelineBarsAsync(brandId:) 相当 — ただし 1:1 置換ではない:
    /// Swift 原本がフェッチ時に掛けていた eventDisplayName (作品名プレフィックスの
    /// 表示用省略) は UserDefaults 依存のため core は適用せず、イベント帯の `title` は
    /// events.name の正式名称のまま返す。呼び出し側は `target == Event` の帯にだけ
    /// 表示用省略を適用すること。
    pub fn timeline_bars(
        &self,
        brand_id: Option<String>,
    ) -> Result<Vec<TimelineBarRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::timeline_bars(&snap, brand_id.as_deref()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::timeline_queries::{TimelineBarLane, TimelineBarTarget};

    fn loaded_store() -> std::sync::Arc<SnapshotStore> {
        let store = SnapshotStore::new();
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        store.load(db).expect("bundle DB はロードできる");
        store
    }

    #[test]
    fn not_loaded_is_a_typed_error() {
        let store = SnapshotStore::new();
        assert!(matches!(store.timeline_bars(None), Err(SnapshotError::NotLoaded)));
    }

    #[test]
    fn ffi_surface_smoke() {
        // ロジックの等価性は domain 側の照合テストが担う。ここは委譲の疎通だけ確認する。
        let store = loaded_store();
        let all = store.timeline_bars(None).unwrap();
        assert!(all.len() > 500, "全ブランドの帯は数百本規模 (len={})", all.len());
        assert!(all.iter().any(|b| b.lane == TimelineBarLane::Milestone));
        assert!(all.iter().any(|b| b.lane == TimelineBarLane::Live));
        assert!(all.iter().any(|b| b.lane == TimelineBarLane::Music));

        let cg = store.timeline_bars(Some("cg".into())).unwrap();
        assert!(!cg.is_empty() && cg.len() < all.len());
    }

    /// FFI 面の回帰固定: イベント帯の title は正式名称のままアダプタへ届く。
    /// 表示用省略 (eventDisplayName) の適用はアダプタの責務 (メソッド doc と
    /// domain 側 event_bar_titles_stay_official_names 参照)。
    #[test]
    fn event_titles_arrive_unabbreviated() {
        let store = loaded_store();
        let bars = store.timeline_bars(None).unwrap();
        assert!(
            bars.iter().any(|b| matches!(b.target, TimelineBarTarget::Event { .. })
                && b.title.starts_with("THE IDOLM@STER ")),
            "作品名プレフィックス付きの正式名称がそのまま返るはず (core は省略しない)"
        );
    }
}
