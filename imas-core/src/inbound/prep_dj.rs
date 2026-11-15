//! 予習 DJ の FFI 口。並べ方は `domain::prep_dj`、ChatGPT プランでの語りは `agent::tools::prep_dj`。
//!
//! どの口も、予測 (`inbound::setlist_forecast` のキャッシュ) を引いてから委譲するだけ。
//! 初回は予測の下ごしらえで重いので、メインスレッドから呼ばないこと。

use super::natural_search::PlanTaskRequest;
use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::agent::tools::prep_dj as dj;
use crate::domain::prep_dj::{base_plan, PrepDjPlan, FORECAST_CANDIDATES};
use crate::domain::setlist_forecast::SetlistForecastRecord;
use crate::domain::snapshot::Snapshot;
use std::sync::Arc;

/// 1 往復ぶんの結末。
///
/// - `next_input` が空でなければ、それでもう 1 往復する。
/// - 空なら終わり。`plan` があればそれを出す。無ければ使える流れにならなかった
///   (画面はコアの流れのまま、`failure_message` を添える)。
#[derive(Debug, Clone, uniffi::Record)]
pub struct PrepDjStep {
    pub plan: Option<PrepDjPlan>,
    pub next_input: Vec<String>,
    pub failure_message: Option<String>,
}

/// 注文の例 (「盛り上がる曲を前半に」)。
#[uniffi::export]
pub fn prep_dj_order_examples() -> Vec<String> {
    dj::order_examples().into_iter().map(String::from).collect()
}

/// 注文の上限 (文字数)。入力欄の上限に使う。
#[uniffi::export]
pub fn prep_dj_max_order_chars() -> u32 {
    dj::MAX_ORDER_CHARS as u32
}

impl SnapshotStore {
    /// セトリの無い公演だけ予測を引く (ある公演は披露順に流すので要らない)。
    fn prep_dj_forecast(&self, snap: &Arc<Snapshot>, show_id: &str) -> Option<SetlistForecastRecord> {
        let &show = snap.show_index_by_id.get(show_id)?;
        if !snap.setlist_items_by_show[show as usize].is_empty() {
            return None;
        }
        self.forecast_for(snap, show, FORECAST_CANDIDATES)
    }
}

#[uniffi::export]
impl SnapshotStore {
    /// 入口に出す名前 (「予習 DJ」「復習 DJ」)。None なら入口を出さない。軽いので画面から直接呼べる。
    pub fn prep_dj_entry_label(&self, show_id: String) -> Result<Option<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(crate::domain::prep_dj::entry_label(&snap, &show_id).map(String::from))
    }

    /// 公演 1 つの流れをコアだけで組む (つないでいない人にも出す)。組めない公演は None。
    pub fn prep_dj_plan(&self, show_id: String) -> Result<Option<PrepDjPlan>, SnapshotError> {
        let snap = self.current()?;
        let forecast = self.prep_dj_forecast(&snap, &show_id);
        Ok(base_plan(&snap, &show_id, forecast.as_ref()))
    }

    /// ChatGPT プランで語りつきの流れを組むリクエスト。組めない公演は None。
    pub fn prep_dj_request(
        &self,
        show_id: String,
        order: String,
        today_key: String,
    ) -> Result<Option<PlanTaskRequest>, SnapshotError> {
        let snap = self.current()?;
        let forecast = self.prep_dj_forecast(&snap, &show_id);
        Ok(dj::request(&snap, &show_id, forecast.as_ref(), &order, &today_key).map(Into::into))
    }

    /// 1 往復の応答を受けて、次にどうするかを決める (1 往復 = 1 呼び出し)。
    pub fn prep_dj_step(
        &self,
        show_id: String,
        input: Vec<String>,
        output_items: Vec<String>,
        text: String,
        today_key: String,
    ) -> Result<PrepDjStep, SnapshotError> {
        let snap = self.current()?;
        let forecast = self.prep_dj_forecast(&snap, &show_id);
        Ok(match dj::step(&snap, &show_id, forecast.as_ref(), &input, &output_items, &text, &today_key) {
            dj::Step::Continue(next_input) => PrepDjStep { plan: None, next_input, failure_message: None },
            dj::Step::Finished(Some(plan)) => PrepDjStep { plan: Some(plan), next_input: Vec::new(), failure_message: None },
            dj::Step::Finished(None) => PrepDjStep {
                plan: None,
                next_input: Vec::new(),
                failure_message: Some("うまく組めませんでした。もう一度試してください".into()),
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_store;

    #[test]
    fn 予習の流れからリクエストと往復まで通る() {
        let store = bundle_store();
        let (id, _) = crate::domain::prep_dj::test_upcoming_forecast();
        let plan = store.prep_dj_plan(id.clone()).unwrap().unwrap();
        assert!(!plan.tracks.is_empty() && !plan.by_model);

        let req = store.prep_dj_request(id.clone(), "ソロ曲を多めに".into(), "2026-11-16".into()).unwrap().unwrap();
        assert!(req.max_rounds > 0);
        let done = store.prep_dj_step(id.clone(), req.input, Vec::new(), "読めない".into(), "2026-11-16".into()).unwrap();
        assert!(done.plan.is_none() && done.next_input.is_empty() && done.failure_message.is_some());

        assert!(store.prep_dj_plan("no-such-show".into()).unwrap().is_none());
        assert!(!prep_dj_order_examples().is_empty());
    }
}
