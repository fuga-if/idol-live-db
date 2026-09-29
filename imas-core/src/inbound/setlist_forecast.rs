//! セトリの機械予測の FFI 口。規則は `domain::setlist_forecast`。
//!
//! 下ごしらえ ([`ForecastPrep`]) はスナップショット 1 世代につき 1 回だけ作り、
//! 学習した重みは「学習に使う公演の数」ごとに持つ。未来の公演はどれも同じ数になるので、
//! 普段は 1 回学習すれば使い回せる。開催中のイベント (DAY1 が済んで DAY2 を見る) と、
//! 過去の公演を見返したときだけ、その区切りで学習し直す。

use std::sync::{Arc, Weak};

use crate::domain::setlist_forecast::{forecast_show, ForecastModel, ForecastPrep, SetlistForecastRecord};
use crate::domain::snapshot::Snapshot;
use crate::inbound::snapshot_store::{SnapshotError, SnapshotStore};

/// 持っておく重みの数 (区切りの種類)。超えたら古いものから捨てる。
const CACHED_MODELS: usize = 4;

/// スナップショット 1 世代ぶんの下ごしらえと、学習した重み。
#[derive(Default)]
pub(crate) struct ForecastCache {
    entry: Option<CacheEntry>,
}

struct CacheEntry {
    /// どの世代のものか。`Weak` なので古い世代を生かしておかない
    /// (割り当ては残るので、同じ番地を新しい世代が使うことも無い)。
    snapshot: Weak<Snapshot>,
    prep: Arc<ForecastPrep>,
    /// (学習公演の数, 重み)。新しく使ったものが末尾。
    models: Vec<(usize, Arc<ForecastModel>)>,
}

impl ForecastCache {
    pub(crate) fn clear(&mut self) {
        self.entry = None;
    }

    /// 世代が変わっていれば下ごしらえを作り直し、`prefix` が返す学習公演の数の重みを引く (無ければ学習する)。
    fn prep_and_model(
        &mut self,
        snap: &Arc<Snapshot>,
        prefix: impl FnOnce(&ForecastPrep) -> Option<usize>,
    ) -> Option<(Arc<ForecastPrep>, Arc<ForecastModel>)> {
        let fresh = self.entry.as_ref().is_some_and(|e| Weak::ptr_eq(&e.snapshot, &Arc::downgrade(snap)));
        if !fresh {
            self.entry = Some(CacheEntry {
                snapshot: Arc::downgrade(snap),
                prep: Arc::new(ForecastPrep::build(snap)),
                models: Vec::new(),
            });
        }
        let entry = self.entry.as_mut().expect("直前に入れた");
        let key = prefix(&entry.prep)?;
        let model = match entry.models.iter().position(|(k, _)| *k == key) {
            Some(i) => {
                let hit = entry.models.remove(i);
                entry.models.push(hit.clone());
                hit.1
            }
            None => {
                let model = Arc::new(entry.prep.train(key));
                if entry.models.len() >= CACHED_MODELS {
                    entry.models.remove(0);
                }
                entry.models.push((key, model.clone()));
                model
            }
        };
        Some((entry.prep.clone(), model))
    }
}

#[uniffi::export]
impl SnapshotStore {
    /// 公演 1 つのセトリ予想。点数の高い順に最大 `limit` 曲。
    ///
    /// 1 画面 1 回で呼ぶ。初回は下ごしらえと学習で重い (手元の release で数百ミリ秒) ので、
    /// メインスレッドから呼ばないこと。同じスナップショットの 2 回目以降は速い。
    /// 公演が無い・リアルライブ (live / festival) でない・日付が読めないときは None。
    pub fn setlist_forecast(&self, show_id: String, limit: u32) -> Result<Option<SetlistForecastRecord>, SnapshotError> {
        let snap = self.current()?;
        let Some(&show) = snap.show_index_by_id.get(&show_id) else { return Ok(None) };
        let cached = self
            .forecast
            .lock()
            .expect("forecast cache lock poisoned")
            .prep_and_model(&snap, |prep| prep.training_prefix(&snap, show));
        Ok(cached.and_then(|(prep, model)| forecast_show(&snap, &prep, &model, show, limit)))
    }
}

#[cfg(test)]
mod tests {
    use crate::domain::setlist_forecast::forecast_show_uncached;

    #[test]
    fn delegates_to_the_domain_and_reuses_the_cache() {
        let store = crate::test_support::bundle_store();
        let snap = store.current().unwrap();
        let show = snap
            .shows_in_date_order
            .iter()
            .rev()
            .map(|&s| &snap.shows[s as usize])
            .find(|s| !snap.cast_by_show[snap.show_index_by_id[&s.id] as usize].is_empty()
                && crate::domain::collection_gap::is_real_live(&snap, snap.show_index_by_id[&s.id]))
            .expect("出演者のいるライブがある")
            .id
            .clone();
        let first = store.setlist_forecast(show.clone(), 20).unwrap().unwrap();
        let second = store.setlist_forecast(show.clone(), 20).unwrap().unwrap();
        assert_eq!(first, second);
        assert_eq!(Some(first), forecast_show_uncached(&snap, &show, 20));
        assert_eq!(store.setlist_forecast("no-such-show".into(), 20).unwrap(), None);
    }
}
